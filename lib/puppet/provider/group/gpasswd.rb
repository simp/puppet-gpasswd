require 'puppet/provider/group/groupadd'

Puppet::Type.type(:group).provide :gpasswd, :parent => Puppet::Type::Group::ProviderGroupadd do
  require 'shellwords'

  desc <<-EOM
    Group management via `gpasswd`. This allows for local group
    management when the users exist in a remote system.
  EOM

  commands  :addmember => 'gpasswd',
            :modmember => 'gpasswd'

  has_feature :manages_members unless %w{HP-UX Solaris}.include? Facter.value(:operatingsystem)
  has_feature :libuser if Puppet.features.libuser?
  has_feature :system_groups unless %w{HP-UX Solaris}.include? Facter.value(:operatingsystem)

  def is_new_format?
    defined?(Puppet::Property::List) &&
      @resource.parameter('members').class.ancestors.include?(Puppet::Property::List)
  end

  def addcmd
    # This pulls in the main group add command should the group need
    # to be added from scratch.
    cmd = Array(super.map{|x| x = "#{x}"}.shelljoin)

    if @resource.parameter('members')
      cmd += @resource.property('members').shouldorig.map{ |x|
        [ command(:addmember),'-a',x,@resource[:name] ].shelljoin
      }
    end

      mod_group(cmd)

    # We're returning /bin/true here since the Nameservice classes
    # would execute whatever is returned here.
    return '/bin/true'
  end

  # This is a repeat from puppet/provider/nameservice/objectadd.
  # The self.class.name matches are hard coded so cannot be easily
  # overridden.
  def modifycmd(param, value)
    cmd_type = param.to_s =~ /password_.+_age/ ? :password : :modify
    cmd = [command(cmd_type)]
    cmd_flag = flag(param)

    # Work around issues with Puppet 6.20+
    #
    # Basically, these versions are trying to approach something that works but
    # aren't quite there yet and will actually try to remove all of the users
    # instead of adding them.
    return ['/bin/true'] if (cmd_type == :modify) && (cmd_flag == '-m')

    cmd << cmd_flag << value
    if @resource.allowdupe? && (param == :gid)
      cmd << "-o"
    end
    cmd << @resource[:name]

    cmd
  end

  def members
    members_to_set = @resource.parameter('members').shouldorig

    return unless members_to_set

    @current_members = []
    begin
      current_members = Puppet::Etc.send('getgrnam', name)
      if current_members
        @current_members = current_members.mem
      end
    rescue ArgumentError
      # Noop
    end

    retval = @current_members

    if !@resource[:auth_membership] && (members_to_set - @current_members).empty?
      retval = members_to_set
    end

    retval = retval.sort

    # Puppet 5.5.7 breaking change workaround
    if is_new_format?
      return retval.join(',')
    else
      return retval
    end
  end

  def members_insync?(is, should)
    # We need to remove any user that the system doesn't recognize, otherwise
    # the add and/or remove commands will fail.

    _should = Array(should).dup.sort.uniq

    _should.delete_if do |user|
      begin
        # This is an integer
        if user.to_i.to_s == user
          Puppet::Etc.send('getpwuid', user)
        else
          Puppet::Etc.send('getpwnam', user)
        end

        false
      rescue
        Puppet.debug("Ignoring unknown user: '#{user}'")

        true
      end
    end

    Array(is).sort.uniq == _should
  end

  def members=(to_set)
    cmd = []

    if is_new_format?
      to_be_added = to_set.split(',')
    else
      to_be_added = to_set.dup
    end

    if @resource[:auth_membership]
      cmd << [ command(:modmember),'-M',to_be_added.join(','), @resource[:name] ].shelljoin
    else
      to_be_added = to_be_added | @current_members

      !to_be_added.empty? && cmd += to_be_added.map { |x|
        [ command(:addmember),'-a',x,@resource[:name] ].shelljoin
      }
    end

    mod_group(cmd)
  end

  private

  # This define takes an array of commands to run and executes them in
  # order to modify the group memberships on the system.
  # A useful warning message is output if there is an issue modifying
  # the group but all members that can be added are added. This is an
  # attempt to do the "right thing" without actually breaking a run
  # or creating a whole new type just to override an insignificant
  # segment of the native group type.
  #
  # The run of the type *will* succeed in all cases and present warnings to the
  # user.
  def mod_group(cmds)
    cmds.each do |run_cmd|
      begin
        output = execute(run_cmd, :custom_environment => @custom_environment, :failonfail => false, :combine => true)

        if output.exitstatus != 0
          Puppet.warning("Error modifying #{@resource[:name]} using '#{run_cmd}': #{output}")
        else
          Puppet.debug("Success: #{run_cmd}")
        end
      end
    end
  end
end
