require 'rubygems'
require 'couchrest'
require 'ftools'

require File.expand_path(File.dirname(__FILE__) + "/instance")

class Client < CouchRest::ExtendedDocument
  use_database CouchRest.database!($CouchDB)

  unique_id :name
  property :name
  view_by :name

  def Client.create(name)
    # Check if a client with this name already exists
    client = Client.get_by_name(name)
    unless client.nil?
      # ask user
      puts "This client already exists, do you want to overwrite? [y/N]"
      option = STDIN.gets.chomp
      if option == 'y'
          puts "... removing old client"
          client.destroy()
      else
          return
      end
    end

    client = Client.new(:name => name)
    client.save()
  end

  def Client.get_by_name(name)
    results = Client.by_name(:key => name)
    return results.first()
  end

  # Get volumes
  def get_volumes()
    return Volume.by_client_name(:key =>  self.name)
  end

  # *************************************************************************
  # Get instances

  def get_instances()
    results = Instance.by_client_id(:key => self.name)
    return results
  end

  def get_instance_by_id(id)
    instance = self.get_instances().find { |instance| instance.id == id }
    return instance
  end

  def get_app_instances()
    return self.get_instances().find_all { |instance| instance.is_app == 1}
  end

  def get_web_instances()
    return self.get_instances().find_all { |instance| instance.is_web == 1}
  end

  def get_rails_instances()
    return self.get_instances().find_all { |instance| instance.is_rails == 1 }
  end

  # Get the database instance
  def get_db_instance()
    return self.get_instances().find { |instance| instance.is_db == 1 }
  end

end
