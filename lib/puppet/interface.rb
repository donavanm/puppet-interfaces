require 'puppet'
require 'puppet/util/autoload'

class Puppet::Interface
  require 'puppet/interface/action_manager'

  include Puppet::Interface::ActionManager
  extend Puppet::Interface::ActionManager
  # This is just so we can search for actions.  We only use its
  # list of directories to search.
  def self.autoloader
    @autoloader ||= Puppet::Util::Autoload.new(:application, "puppet/interface")
  end

  def self.interfaces
    unless @loaded
      @loaded = true
      $LOAD_PATH.each do |dir|
        next unless FileTest.directory?(dir)
        Dir.chdir(dir) do
          Dir.glob("puppet/interface/*.rb").collect { |f| f.sub(/\.rb/, '') }.each do |file|
            iname = file.sub(/\.rb/, '')
            begin
              require iname
            rescue Exception => detail
              puts detail.backtrace if Puppet[:trace]
              raise "Could not load #{iname} from #{dir}/#{file}: #{detail}"
            end
          end
        end
      end
    end
    @interfaces.keys
  end

  # Return an interface by name, loading from disk if necessary.
  def self.interface(name)
    @interfaces ||= {}
    unless @interfaces[unify_name(name)]
      require "puppet/interface/#{unify_name(name)}"
    end
    @interfaces[unify_name(name)]
  rescue Exception => detail
    puts detail.backtrace if Puppet[:trace]
    $stderr.puts "Unable to find interface '#{name.to_s}': #{detail}."
  end

  def self.register_interface(name, instance)
    @interfaces ||= {}
    @interfaces[unify_name(name)] = instance
    const_set(name2const(name), instance)
  end

  def self.unload_interface(name)
    @interfaces ||= {}
    @interfaces.delete(unify_name(name))
    const = name2const(name)
    const_get(const)
    remove_const(const)
  rescue
    # nothing - if the constant-getting fails, just return
  end

  def self.unify_name(name)
    name.to_s.downcase.to_sym
  end

  def self.name2const(name)
    name.to_s.capitalize
  end

  attr_accessor :default_format

  def set_default_format(format)
    self.default_format = format.to_sym
  end

  # Return the interface name.
  def name
    @name || self.to_s.sub(/.+::/, '').downcase
  end

  attr_accessor :type, :verb, :name, :arguments, :options

  # Print the configuration for the current terminus class
  action :showconfig do |*args|
    if t = indirection.terminus_class
      puts "Run mode #{Puppet.run_mode}: #{t}"
    else
      $stderr.puts "No default terminus class for run mode #{Puppet.run_mode}"
    end
  end

  def initialize(name, options = {}, &block)
    @name = name

    @default_format = :pson
    options.each { |opt, val| send(opt.to_s + "=", val) }

    # We have to register before loading actions,
    # since the actions require the registration
    # Use the full class name, so this works with
    # subclasses.
    Puppet::Interface.register_interface(name, self)

    load_actions

    if block_given?
      instance_eval(&block)
    end
  end

  # Try to find actions defined in other files.
  def load_actions
    path = "puppet/interface/#{name}"

    loaded = []
    self.class.autoloader.search_directories.each do |dir|
      fdir = ::File.join(dir, path)
      next unless FileTest.directory?(fdir)

      Dir.chdir(fdir) do
        Dir.glob("*.rb").each do |file|
          aname = file.sub(/\.rb/, '')
          if loaded.include?(aname)
            Puppet.debug "Not loading duplicate action '#{aname}' for '#{name}' from '#{fdir}/#{file}'"
            next
          end
          loaded << aname
          Puppet.debug "Loading action '#{aname}' for '#{name}' from '#{fdir}/#{file}'"
          require "#{path}/#{aname}"
        end
      end
    end
  end

  def to_s
    name.to_s
  end
end
