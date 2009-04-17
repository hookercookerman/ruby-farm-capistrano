require 'capistrano'

# This is a space separated list of extra apt packages to install
set :extra_apt_packages, ''

namespace :chef do
  desc "bootstrap an ec2 instance to work with chef"
  task :bootstrap, :roles => :all do
    run "apt-get update && apt-get -y upgrade"
    run "apt-get -y install ruby ruby1.8-dev rubygems libopenssl-ruby1.8 build-essential git-core"
    # Now we need to add the rubygem binaries to the path. Unfortunately, this is tricky
    # because SSH locks down this stuff we can only effect PATH in ~/.ssh/environment.
    # This also means that we can't use the PATH=$PATH:... format so we recreate a
    # standard path, this will work in ubuntu, but might break elsewhere

    # ... first we need to enable it
    run "if [ `cat /etc/ssh/sshd_config | grep PermitUserEnvironment | wc -l` = 0 ]; then echo 'PermitUserEnvironment yes' >> /etc/ssh/sshd_config; /etc/init.d/ssh restart; fi"
    
    # ... for the next step we need a ~/.ssh directory
    run "if [ ! -e ~/.ssh ]; then mkdir ~/.ssh; chmod 600 ~/.ssh; fi"

    # ... then we need to add our PATH to ~/.ssh/environment
    gem_bin_path = "/var/lib/gems/1.8/bin"
    path = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:#{gem_bin_path}"
    run "if [ `cat ~/.ssh/environment | grep PATH | wc -l` = 0 ]; then echo 'PATH=#{path}' >> ~/.ssh/environment; /etc/init.d/ssh restart; fi"

    # This next line doesn't seem to work on ubuntu - disabled in favour of apt
    # run "gem update --system || true"
    # ... this should hopefully work on most systems
    run "gem install rubygems-update && #{gem_bin_path}/update_rubygems"
    run "if [ -x /usr/bin/gem ]; then rm /usr/bin/gem; ln -s /usr/bin/gem1.8 /usr/bin/gem; fi"
    run "gem sources -a http://gems.opscode.com"
    run "gem install json --version '> 1.1.2'"
    run "gem install chef ohai"

    # Create the chef client file
    chef_config = <<-EOF
      log_level :info
      log_location  STDOUT
      ssl_verify_mode :verify_none
      registration_url  "http://#{chef_server}:4000"
      openid_url        "http://#{chef_server}:4001"
      template_url      "http://#{chef_server}:4000"
      remotefile_url    "http://#{chef_server}:4000"
      search_url        "http://#{chef_server}:4000"
      validation_token  "#{chef_validation}"
    EOF
    run("if [ ! -e /etc/chef ]; then mkdir /etc/chef; fi")
    put(chef_config, "/etc/chef/client.rb")

    # We also will need a deploy user
    run("if [ `cat /etc/group | grep deploy | wc -l` = 0 ]; then useradd -p '' -m deploy; fi")
  end

  desc "do a chef client run"
  task :run_client do
    run "chef-client"
  end

  # We want update nodes to also configure db and app roles
  after "chef:update_nodes", "chef:update_db_nodes"
  after "chef:update_nodes", "chef:update_web_nodes"
  after "chef:update_nodes", "chef:update_rails_nodes"
  after "chef:update_nodes", "chef:update_passenger"

  desc "Update rails node attributes"
  task :update_rails_nodes, :roles => :rails do
    next if find_servers_for_task(current_task).empty?
    attributes = { "recipes" => ["rails"] }

    update_chef_attributes(attributes)
  end

  desc "Update passenger configuration"
  task :update_passenger do
    # We need to add a path and port so that passenger know where to find the app
    # and the load balancer knows where to find it
    attributes = {}
    attributes['rails_apps'] = [ ["#{current_path}/public", application_port, rails_environment] ]
    update_chef_attributes(attributes)
  end

  desc "Update DB node attributes"
  task :update_db_nodes, :roles => :db do
    next if find_servers_for_task(current_task).empty?
    attributes = { "recipes" => ["mysql::server"]}

    # Set the variables for the mysql server
    update_chef_attributes(attributes)
  end

  desc "Update web node attributes"
  task :update_web_nodes, :roles => :web do
    next if find_servers_for_task(current_task).empty?
    attributes = { "recipes" => ["apache"] }

    # Add the attributes needed
    attributes["apache"] = {}
    attributes["apache"]["application_servers"] = []

    client = Client.get_by_name(application)
    client.get_rails_instances().each do |app|
      attributes["apache"]["application_servers"].push([app.internal_host, application_port])
    end

    update_chef_attributes(attributes)
  end

  desc "Update the node attributes"
  task :update_nodes do
    # For each node, write the necessary attributes
    client = Client.get_by_name(application)

    attributes = {}
    attributes["database"] = {}
    attributes["database"]["name"] = db_database
    attributes["database"]["user"] = db_user
    attributes["database"]["password"] = db_password
    attributes["database"]["root_password"] = db_root_password

    # Write the database host
    databaseInstance = client.get_db_instance()
    if databaseInstance.nil?
      attributes["database"]["host"] = 'localhost'
    else
      attributes["database"]["host"] = databaseInstance.internal_host
    end

    attributes["aws"] = {}
    attributes["aws"]["access_key"] = aws_access_key
    attributes["aws"]["secret"] = aws_secret

    # We also add any extra apt packages that may have been defined
    attributes['extra_apt_packages'] = extra_apt_packages

    update_chef_attributes(attributes)
  end
end
