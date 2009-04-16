require 'capistrano'

# Default region
set :aws_region, 'eu-west-1'

# Initialise ec2 before all the aws tasks
before 'aws:', 'aws:init'
on :start, 'aws:init', :only => ['aws:start_instance', 'aws:stop_instance', 'aws:create_keypair', 'aws:delete_volume', 'farm:assign_db']

namespace :aws do
  task :init do
    initialise_ec2(aws_access_key, aws_secret, aws_region)
  end

  desc "Create a new elastic IP address"
  task :create_address do
    Address.generate($client)
    puts "Warning: this will be charged unless attached to an instance. i.e. aws:associate_address"
  end

  desc "Associate an elastic IP address with an instance"
  task :associate_address do
    # Get an address - only the first for now
    client = Client.first(:name => application)
    if client.addresses.length == 0:
      raise UserError, "This client doesn't have any addresses, use aws:create_address"
    end
    address = client.addresses[0]

    # Get an instance
    instance = getInstanceFromArg()
    address.assign_instance(instance)
  end

  desc "Start an EC2 instance"
  task :start_instance do

    # Make sure we have set the ami and keypair
    if not exists?(:ec2_image_ami) \
      or not exists?(:ec2_key_pair_name) \
      or not exists?(:ec2_security_group) \
      or not exists?(:ec2_zone)
      raise Error, "You must specify the :ec2_image_ami, :ec2_zone, :ec2_security_group and ec2_key_pair_name variables"
    end

    client = Client.get_by_name(application)
    Instance.start(client, ec2_image_ami, ec2_key_pair_name, ec2_security_group, ec2_zone)
  end

  desc "Stop an EC2 instance"
  task :stop_instance do
    client = Client.get_by_name(application)
    instance = user_choose_instance(client)
    instance.stop()
  end

  desc "Create a keypair on AWS and store in config/farmkey. uses :ec2_key_pair_name"
  task :create_keypair do
    if ec2_key_pair_name.nil?
      raise Error, "You need to set the key pair name in :ec2_key_pair_name"
    end
    result = $ec2.create_key_pair(ec2_key_pair_name)
    # save the file
    File::open("config/farmkey", 'w', 0600) do |file|
      file.write(result[:aws_material])
    end
  end

  desc "Delete an EBS volume"
  task :delete_volume do
    client = Client.get_by_name(application)
    volumes = client.get_volumes()

    if volumes.size == 0 then
      raise Error, "This client doesn't have any volumes"
    end

    # Attempt to delete the volume
    volumes[0].delete()
  end
end

