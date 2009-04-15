require 'rubygems'
require 'couchrest'
require 'capistrano'
require 'capistrano/configuration'

require File.expand_path(File.dirname(__FILE__) + "/lib")

class Instance < CouchRest::ExtendedDocument
  use_database CouchRest.database!($CouchDB)

  unique_id :id

  property :id, :cast_as => 'String', :default => ''
  property :internal_host, :cast_as => 'String', :default => ''
  property :external_host, :cast_as => 'String', :default => ''
  property :is_app, :default => 0
  property :is_db, :default => 0
  property :is_web, :default => 0
  property :is_rails, :default => 0
  property :client_id
    
  view_by :client_id


  # Stop an EC2 instance
  def stop()
    self.destroy()

    # Stop the EC2 instance
    $ec2.terminate_instances([self.id])
  end

  # Set the role of this instance as rails
  def set_rails()
    self.is_rails = 1
    save()
  end

  # Set the role of this instance as app
  def set_app()
    self.is_app = 1
    save()
  end

  # Add the DB role to this instace
  def set_DB()
    self.is_db = 1
    save()
  end

  # Add the web role to this instance
  def set_web()
    self.is_web = 1
    self.save()
  end

  #************************************************************************
  # Utility

  def fulfills_role?(role)
    if role == :app and self.is_app == 1
      return true
    elsif role == :db and self.is_db == 1
      return true
    elsif role == :web and self.is_web == 1
      return true
    elsif role == :rails and self.is_rails == 1
      return true
    else
      return false
    end
  end

  def to_s()
    roles = []
    roles.push('app') if self.fulfills_role?(:app)
    roles.push('db') if self.fulfills_role?(:db)
    roles.push('web') if self.fulfills_role?(:web)
    roles.push('rails') if self.fulfills_role?(:rails)
    roles = roles.join(',')
    "#{self.id}\t#{self.external_host}\t#{roles}"
  end

  # ***********************************************************************
  # Class methods

  def Instance.print_for_client(client)
    puts "\nInstances:"
    client.get_instances().each { |instance|
      puts "#{instance.to_s()}"
    }
    puts "\nVolumes:"
    client.get_volumes().each { |volume|
      puts "#{volume.to_s()}"
    }
    puts
  end

    
  # Start a new EC2 instance based on the AMI provided in the configuration.
  def Instance.start(client, ami, keypair, group, zone)
    puts "Starting EC2 instance..."

    # Start the EC2 instance
    instances = $ec2.run_instances(ami, 1, 1, 
                                   [group], 
                                   keypair, 
                                   '', nil, nil, nil, nil,
                                   zone)
    instance_ids = instances.map { |instance| instance[:aws_instance_id] }

    # Wait for instance to be available
    while instance_ids.length > 0
      $ec2.describe_instances(instance_ids).each { |instance|
        if instance[:aws_state] == 'running'
          # Create a new instance record
          new_instance = Instance.new()
          new_instance.id = instance[:aws_instance_id]
          new_instance.internal_host = instance[:private_dns_name]
          new_instance.external_host = instance[:dns_name]
          puts "New externalhost #{new_instance.external_host}"

          new_instance.client_id = client.name
          new_instance.save()
          
          puts "New instance started: #{new_instance.id}"

          # As we've started this one, remove from instance_ids
          instance_ids.delete(instance[:aws_instance_id])
        end
      }
      if instance_ids.length > 0:
        sleep(6)
      end
    end
  end

  # *************************************************************************
  # EC2 Stuff
  
  # Reset the external_host for this instance
  def reset_external_host()
    instances = $ec2.describe_instances([self.id])
    if instances.length == 0
      raise UserError, "Instance was not found when resetting external_host"
    end
    self.external_host = instances[0][:dns_name]
    self.save()
  end
end
