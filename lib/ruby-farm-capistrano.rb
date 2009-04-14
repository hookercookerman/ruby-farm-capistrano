$:.unshift(File.dirname(__FILE__)) unless
  $:.include?(File.dirname(__FILE__)) || $:.include?(File.expand_path(File.dirname(__FILE__)))

def initialize_ruby_farm_capistrano() 
  load(File.dirname(__FILE__) + '/ruby-farm-capistrano/d50_capistrano.rb')
end

module RubyFarmCapistrano
  VERSION = '0.0.1'
end
