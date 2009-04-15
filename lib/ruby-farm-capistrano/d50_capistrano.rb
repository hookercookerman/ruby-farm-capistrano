$: << File.expand_path(File.dirname(__FILE__))

require 'rubygems'
require 'lib'
require 'net/ssh'
require 'json'

require 'lib'

require 'capistrano'

load(File.expand_path(File.dirname(__FILE__)) + '/chef_capistrano.rb')
load(File.expand_path(File.dirname(__FILE__)) + '/aws_capistrano.rb')

on :start, 'add_ssh_key', :except => ['aws:create_keypair']
on :start, 'farm:configure_couch_db'
on :start, 'load_roles', :except => [ 'farm:create_client']

after 'deploy:setup', 'farm:change_app_to_deploy_user'

# Make sure all the roles exist
roles[:app]
roles[:db]
roles[:web]
roles[:rails]
roles[:all]

namespace :farm do
  desc "Create the database entries for this client"
  task :create_client do
    Client.create(application)
  end

  desc "Print instances in this client's farm"
  task :print_farm do
    client = Client.get_by_name(application)
    Instance.print_for_client(client)
  end

  task :print_db, :roles => [:db] do
    run "echo 'est'"
  end

  desc "Assign the rails app server role to an instance"
  task :assign_rails do
    client = Client.get_by_name(application)
    instance = user_choose_instance(client)
    instance.set_rails()
  end

  desc "Assign web role to an instance"
  task :assign_web do
    client = Client.get_by_name(application)
    instance = user_choose_instance(client)
    instance.set_web()
  end

  desc "Assign db role to an instance"
  task :assign_db do
    client = Client.get_by_name(application)
    instance = user_choose_instance(client)

    # Make sure a volume is attached
    volume = Volume.get_for_client(client, ebs_size, ec2_zone)
    if volume.attached_instance != instance.id
      volume.detach()
      volume.attach(instance)
    end

    instance.set_DB()
  end

  desc "Update the database.yml file"
  task :update_database_yml, :roles => [:rails] do
    next if find_servers_for_task(current_task).empty?
    run "cp /tmp/database.yml #{current_path}/config/database.yml && chown deploy:deploy #{current_path}/config/database.yml"
  end

  desc "Run a rake task for each app instance"
  task :rake, :roles => :rails do
    command = ENV["COMMAND"]
    run "cd #{current_path} && RAILS_ENV=production rake #{command}"
  end

  desc "Make sure the git host is in known_hosts"
  task :add_git_known_host, :roles => :rails do
    unless git_host_key.nil?
      run "echo '#{git_host_key}' >> ~/.ssh/known_hosts"
    else
      puts "git_host_key isn't set"
    end
  end

  desc "chown the app to the deploy user"
  task :change_to_deploy_user do
    run "chown -R deploy:deploy #{latest_release}"
  end

  desc "Change the owner of the app to deploy"
  task :change_app_to_deploy_user do
    run "chown -R deploy:deploy #{deploy_to}"
  end

  desc "Configure couch database INTERNAL"
  task :configure_couch_db do
    $CouchDB = couch_db
    require 'instance'
    require 'client'
    require 'volume'
  end

  namespace :db do
    desc "Backup the production database"
    task :backup, :roles => :db do
      bucket = application + "-db-backup"
      database, username, password, host = retrieve_db_info()
      # backup the database
      run "mysqldump -u#{username} -p#{password} #{database} > /mnt/backup.sql"
      run "gzip -f /mnt/backup.sql"

      # Upload to S3
      run "s3cmd put /mnt/backup.sql.gz s3://#{bucket}/snapshot.sql.gz"
    end

    desc "Create S3 bucket for backups"
    task :s3_setup, :roles => :db do
      bucket = application + "-db-backup"
      run "s3cmd mb s3://#{bucket}"
    end

  end

end

# NOTE: This must not be in a namespace because capistrano won't let roles be defined
# in a namespace
desc "Load the farm roles from the DB"
task :load_roles do
  # Get the current client
  client = Client.get_by_name(application)

  # Check that the client exists
  if client.nil?
    raise Error, "Error: Client doesn't exist in database. Run cap farm:create_client."
  end

  # Get the client's instances
  client.get_instances().each do |instance|
    role :app, instance.external_host if instance.is_app == 1
    role :db, instance.external_host, :primary => true if instance.is_db == 1
    role :web, instance.external_host if instance.is_web == 1
    role :rails, instance.external_host if instance.is_rails == 1

    # We have the :all role for tasks that work on any instance
    role :all, instance.external_host
  end
end

desc "Make sure the farm-ssh key is present, and load it if necessary"
task :add_ssh_key do
  check_ssh_key()
end

before "deploy:restart", "farm:change_to_deploy_user"
before "deploy:restart", "farm:update_database_yml"
after "farm:update_database_yml", "chef:update_passenger"

after "deploy:update_code", "deploy:submodules"
after "farm:update_database_yml", "deploy:build_gems"

namespace :deploy do
  task :restart do
    run "touch #{current_path}/tmp/restart.txt"
  end

  desc "Pull submodules"
  task :submodules do
    run "cd #{release_path} && (git submodule update --init || git submodule update)"
  end

  desc "Build any bundled gems"
  task :build_gems do
    run "cd #{release_path} && RAILS_ENV='production' rake gems:build"
  end
end

def update_chef_attributes(attributes)
    # Upload the file
    file_path = '/tmp/chef-attributes.json'
    put(attributes.to_json(), file_path)

    # Load with chef
    run("chef-client -j #{file_path}")
end
