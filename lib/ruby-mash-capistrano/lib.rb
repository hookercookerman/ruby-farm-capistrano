require 'right_aws'
require "tempfile"
require "open3"
require "yaml"

# The default region is east us

def initialise_ec2(access_key, secret, region)
  begin
    logger = Logger.new(STDOUT)
    logger.level = Logger::ERROR

    $ec2 = RightAws::Ec2.new(access_key, secret, :region => region, :logger => logger)
    $s3 = RightAws::S3.new(access_key, secret, :region => region, :logger => logger)
  rescue
      p $!
      puts "WARN: problem starting AWS"
  end
end

def user_choose_instance(client)
  client.get_instances().each_index do |i|
    instance = client.get_instances()[i]
    puts "#{i}. #{instance.to_s()}"
  end
  print "Please choose an instance: "; STDOUT.flush
  decision = STDIN.gets.chomp.to_i
  if decision < client.get_instances().length
    return client.get_instances()[decision]
  end
end

# Load a ssh key into the ssh-agent
def load_ssh_key(key_path)
  full_key_path = File.expand_path(key_path)
  result = Open3.popen3("ssh-add #{full_key_path}") do |stdin, stdout, stderr|
    err = stderr.read()
    if err.index("Identity added:").nil?
      puts err
      raise StandardError, "Error adding SSH key: #{full_key_path}"
    end
  end
  return result
end


# Check if we need to add the client's key to ssh-agent and do so. Error if there is no
# key
def check_ssh_key()
  key_file = "config/farmkey"

  # Check that it exists
  if !File.exists?(key_file)
    raise StandardError, "Error: can't find farm private ssh key in config/farmkey. Add a key with aws:create_keypair"
  end

  # Read in the keypair so we can compare it with the agent's keys
  key = File.readlines(key_file)

  # Check if this key is in the agent, if not add it
  agent = Net::SSH::Authentication::Agent.connect()
  found = agent.identities().select { |i| i == key }
  if found.length == 0
    load_ssh_key(key_file)
  end

  agent.close()
end
