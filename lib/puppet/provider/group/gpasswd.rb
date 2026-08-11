require 'puppet/provider/group/groupadd'

# @summary Local group membership management via `gpasswd`
Puppet::Type.type(:group).provide :gpasswd, parent: Puppet::Type::Group::ProviderGroupadd do
  require 'shellwords'

  desc <<~EOM
    Group management via `gpasswd`.

    Extends the standard `groupadd` provider with support for the
    `manages_members` feature so that the members of a local group can be
    managed with the native `group` type, even when the users themselves are
    defined in a remote system such as LDAP:

        group { 'test':
          members => ['foo', 'bar', 'baz'],
        }

    The group's `auth_membership` parameter selects exclusive membership
    (`gpasswd -M`, membership matches the catalog exactly) or additive
    membership (`gpasswd -a` per user, existing members are preserved).

    Members that the system cannot resolve (via `getpwnam`/`getpwuid`) are
    skipped with a warning instead of failing the resource, and errors from
    individual membership changes are downgraded to warnings so that one bad
    member does not abort management of the rest of the group.
  EOM

  commands  addmember: 'gpasswd',
            modmember: 'gpasswd'

  has_feature :manages_members unless ['HP-UX', 'Solaris'].include? Facter.value(:operatingsystem)
  has_feature :libuser if Puppet.features.libuser?
  has_feature :system_groups unless ['HP-UX', 'Solaris'].include? Facter.value(:operatingsystem)

  # Whether the running Puppet represents the `members` property as a
  # `Puppet::Property::List` (comma-joined string) rather than a plain Array
  #
  # @return [Boolean]
  def is_new_format? # rubocop:disable Style/PredicatePrefix
    defined?(Puppet::Property::List) &&
      @resource.parameter('members').class.ancestors.include?(Puppet::Property::List)
  end

  # Create the group and add any initial members with `gpasswd -a`
  #
  # The parent provider's group creation command and the per-member `gpasswd`
  # commands are executed here (see `mod_group`) rather than returned, because
  # the Nameservice layer can only execute a single command.
  #
  # @return [String] a no-op command for the Nameservice layer to execute
  def addcmd
    # This pulls in the main group add command should the group need
    # to be added from scratch.
    cmd = Array(super.map { |x| x.to_s }.shelljoin)

    if @resource.parameter('members')
      cmd += @resource.property('members').shouldorig.map do |x|
        [ command(:addmember), '-a', x, @resource[:name] ].shelljoin
      end
    end

    mod_group(cmd)

    # We're returning /bin/true here since the Nameservice classes
    # would execute whatever is returned here.
    '/bin/true'
  end

  # Build the command that modifies a group property
  #
  # This is a repeat from puppet/provider/nameservice/objectadd.
  # The self.class.name matches are hard coded so cannot be easily
  # overridden.
  #
  # @param param [Symbol] the property being modified
  # @param value [String] the new value
  # @return [Array<String>] the command to execute
  def modifycmd(param, value)
    cmd_type = (param.to_s =~ %r{password_.+_age}) ? :password : :modify
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
      cmd << '-o'
    end
    cmd << @resource[:name]

    cmd
  end

  # Current group members, as read from the system group database
  #
  # When `auth_membership` is false and all desired members are already
  # present, the desired value is returned instead so that the property is
  # seen as in sync.
  #
  # @return [Array<String>, String, nil] the membership in the format the
  #   running Puppet's `members` property expects (see `is_new_format?`)
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
    return retval.join(',') if is_new_format?

    retval
  end

  # Whether the current membership matches the desired membership
  #
  # @param is [Array<String>] the current members
  # @param should [Array<String>, String] the desired members
  # @return [Boolean]
  def members_insync?(is, should)
    # We need to remove any user that the system doesn't recognize, otherwise
    # the add and/or remove commands will fail.

    sorted_should = Array(should).dup.sort.uniq

    sorted_should.delete_if do |user|
      # This is an integer
      if user.to_i.to_s == user
        Puppet::Etc.send('getpwuid', user)
      else
        Puppet::Etc.send('getpwnam', user)
      end

      Puppet.debug("Ignoring unknown user: '#{user}'")

      false
    rescue
      true
    end

    Array(is).sort.uniq == sorted_should
  end

  # Set the group membership with `gpasswd`
  #
  # Uses `gpasswd -M` (exclusive) when `auth_membership` is true and
  # per-member `gpasswd -a` (additive) otherwise.
  #
  # @param to_set [Array<String>, String] the desired members, in the format
  #   the running Puppet's `members` property provides (see `is_new_format?`)
  # @return [void]
  def members=(to_set)
    cmd = []

    to_be_added = if is_new_format?
                    to_set.split(',')
                  else
                    to_set.dup
                  end

    return if to_be_added.empty?
    if @resource[:auth_membership]
      cmd << [ command(:modmember), '-M', to_be_added.join(','), @resource[:name] ].shelljoin
    else
      to_be_added |= @current_members

      !to_be_added.empty? && cmd += to_be_added.map do |x|
        [ command(:addmember), '-a', x, @resource[:name] ].shelljoin
      end
    end

    mod_group(cmd)
  end

  private

  # Execute a list of group modification commands in order
  #
  # A useful warning message is output if there is an issue modifying
  # the group but all members that can be added are added. This is an
  # attempt to do the "right thing" without actually breaking a run
  # or creating a whole new type just to override an insignificant
  # segment of the native group type.
  #
  # The run of the type *will* succeed in all cases and present warnings to the
  # user.
  #
  # @param cmds [Array<String>] shell commands to execute
  # @return [void]
  def mod_group(cmds)
    cmds.each do |run_cmd|
      output = execute(run_cmd, custom_environment: @custom_environment, failonfail: false, combine: true)

      if output.exitstatus != 0
        Puppet.warning("Error modifying #{@resource[:name]} using '#{run_cmd}': #{output}")
      else
        Puppet.debug("Success: #{run_cmd}")
      end
    end
  end
end
