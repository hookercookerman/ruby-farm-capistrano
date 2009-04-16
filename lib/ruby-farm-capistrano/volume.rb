require 'rubygems'
require 'couchrest'

class Volume < CouchRest::ExtendedDocument
  use_database CouchRest.database!($CouchDB)

  unique_id :id

  property :id
  property :attached_instance
  property :client_name

  view_by :id
  view_by :client_name


  # Delete this volume
  def delete_volume()
    # Check if this volume is in use
    descriptions = $ec2.describe_volumes([self.id])

    if descriptions.size == 0 then
      raise "Volume was not found in DB"
    end

    if descriptions[0][:aws_status] == 'in-use' then
      raise "This volume is still 'in-use', if you have just shut down it's instance, wait a few seconds and try again"
    end

    # Attempt to delete it on AWS
    if $ec2.delete_volume(self.id) then
      puts "Deleting volume: #{self.to_s()}"
      self.destroy()
    end
  end

  # Attach this volume to an instance
  def attach(instance)
    # Attach to the instance
    $ec2.attach_volume(self.id, instance.id, '/dev/sdh')

    # Wait for it to be attached
    while true
      done = false
      $ec2.describe_volumes([self.id]).each do |result|
        if result[:aws_attachment_status] == 'attached'
          done = true
        end
      end
      if done
        break
      end
      sleep(5)
    end

    # Update the database
    self.attached_instance = instance.id
    self.save()
  end

  # Detach this volume from any instance it may be attached to
  def detach()
    $ec2.describe_volumes([self.id]).each do |result|
      if result[:aws_attachment_status] == 'attached'
        $ec2.detach_volume(self.id)
      end
    end
    self.attached_instance = nil
    self.save()
  end

  # Check this volume is still up
  def check()
    # check if teh volume still exists
    begin
      volumes = $ec2.describe_volumes([self.id])
    rescue RightAws::AwsError
      if $!.errors[0][0] == "InvalidVolume.NotFound"
        puts "WARN: Volume #{self.id} is not running"
        delete()
        return
      else
        p $!.code
      end
    end

    # check that it is attached
    if volumes[0][:aws_attachment_status] == 'attached'
      if self.attached_instance != volumes[0][:aws_instance_id]
        self.attached_instance = volumes[0][:aws_instance_id]
        self.save()
        puts "WARN: volume #{self.id} is now attached to #{self.attached_instance}"
      end
    elsif self.attached_instance.nil?
      puts "WARN: volume #{self.id} is no longer attached"
      self.attached_instance = nil
      self.save()
    end
  end

  def to_s()
    return "#{self.id} attached to #{self.attached_instance}"
  end
    
  def Volume.check_all()
    # Check that all volumes are accounted for in the db
    $ec2.describe_volumes().each do |volume|
      # Try and get this volume from the database
      db_volume = Volume.by_id(:key => volume[:aws_id])
      if db_volume.nil?
        # The volume doesn't exist, we must warn the user and delete the volume
        print "WARN: The volume #{volume[:aws_id]} is not known... delete? "; STDIN.flush
        decision = STDIN.gets.chomp.downcase
        if decision == 'y'
          $ec2.delete_volume(volume[:aws_id])
        end
      end
    end
  end

  def Volume.get_for_client(client, size, zone)
    volumes = client.get_volumes()

    # Check that the volumes returned are still alive
    volumes.each do |volume|
      begin
        tmp = $ec2.describe_volumes([volume.id])
      rescue RightAws::AwsError
        if $!.errors[0][0] == "InvalidVolume.NotFound"
          puts "WARN: Volume #{self.id} is not running, deleting it"
          volume.delete()
          volumes.delete(volume)
        else
          p $!
        end
      end
    end

    if volumes.length > 1
      puts "WARNING: More than one volume is running"
    elsif volumes.length < 1
      # There isn't a volume so we create one
      result = $ec2.create_volume("", size, zone) 
      new_volume = Volume.new()
      new_volume.id = result[:aws_id]
      new_volume.client_name = client.name
      new_volume.save()

      volumes.push(new_volume)
    end

    return volumes[0]
  end
end
