require 'rubygems'
require 'dm-core'

# Represents an elastic IP address. These are free (up to 100) but only if they are
# associated with an instance. They are charged if not, so it's important to make sure
# they're always associated or else disallocated them. This is probably a cron job, but
# need human interaction to make sure it doesn't delete something it shouldn't.
class Address
    include DataMapper::Resource

    property :id, Serial
    property :public_ip, String

    belongs_to :client
    has 1, :instance

    # Update this address's instance based on a AWS address object
    def update_instance(address)
      # If this address is assigned to an instance, save this
      unless address[:instance_id].nil?
        instance = Instance.first(:id => address[:instance_id])
        unless instance.nil?
          self.instance = instance
          
          # As we have an instance, we take the opportunity to keep track of the client
          self.client = instance.client
        else
          self.instance = nil
          puts "WARNING: Instance referenced in address record not in our DB"
        end
      else
        self.instance = nil
      end
      self.save()
    end

    # Assign an IP to a new instance
    def assign_instance(instance)
      # If this address is already assign to another instance, warn the user
      unless self.instance.nil?
        puts "WARN: This address is already assigned to #{self.instance.id}, reassign? [y/N]"
        decision = STDIN.gets.chomp.downcase
        if decision != 'y'
          puts "Skipping IP assign..."
          return
        end
      end

      # Assign the new instance
      $ec2.associate_address(instance.id, self.public_ip)

      # Assigning instances changes the external_host of the instance, we need to make sure that
      # its up to date
      instance.reset_external_host()

      # Save the result
      self.instance = instance
      self.save()
    end

    # -------------------------------------------------------------------------
    # Static methods
    
    # Reset the addresses from EC2
    def Address.reset_addresses()
      existing_addresses = Address.all()
      $ec2.describe_addresses().each do |address|
        # Check if this address is already in our database
        matching_addresses = existing_addresses.select { |x| x.public_ip == address[:public_ip] }
        if matching_addresses.length > 0
          # We found a match so we check if the instance is the same
          existing_address = matching_addresses[0]
          if existing_address.instance.nil? and not address[:instance_id].nil?
            # We don't know about an instance association
            existing_address.update_instance(address)
          elsif not existing_address.instance.nil? and address[:instance_id].nil?
            # Our instance association is out of date
            existing_address.update_instance(address)
          elsif not existing_address.instance.nil? and not address[:instance_id].nil?
            # We need to check the instances are the same
            if existing_address.instance.id != address[:instance_id]
              existing_address.update_instance(address)
            end
          end
          
          # Delete from existing_addresses, so we know what to remove later on
          existing_addresses.delete(existing_address)
        else
          # There wasn't a match, so we create it
          new_address = Address.new
          new_address.public_ip = address[:public_ip]
          new_address.update_instance(address)
          new_address.save()
        end
      end

      # Remove any addresses which were not found
      existing_addresses.each { |address| address.destroy() }
    end

    # Create a new address for a client
    def Address.generate(client)
      puts "WARN: Make sure this address is associated right away, otherwise it is charged for"
      address = Address.new()
      address.public_ip = $ec2.allocate_address() 
      address.client = client
      address.save()
    end

    # Print out the addresses and their associations
    def Address.print()
      Address.all().each do |address|
        if address.instance.nil?
          instance = 'none'
        else
          instance = address.instance.id
        end
        puts "#{address.public_ip}: #{instance}"
      end
    end
end
