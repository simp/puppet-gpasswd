#!/usr/bin/env rspec
require 'spec_helper'

describe Puppet::Type.type(:group).provider(:gpasswd) do
  before do
    described_class.stubs(:command).with(:add).returns '/usr/sbin/groupadd'
    described_class.stubs(:command).with(:delete).returns '/usr/sbin/groupdel'
    described_class.stubs(:command).with(:modify).returns '/usr/sbin/groupmod'
    described_class.stubs(:command).with(:addmember).returns '/usr/bin/gpasswd'
    described_class.stubs(:command).with(:modmember).returns '/usr/bin/gpasswd'

    if members
      @resource = Puppet::Type.type(:group).new(:name => 'mygroup', :members => members, :provider => provider)
    else
      @resource = Puppet::Type.type(:group).new(:name => 'mygroup', :provider => provider)
    end
  end

  let(:provider) { described_class.new(:name => 'mygroup') }
  let(:members) { nil }
  let(:success_output) { Puppet::Util::Execution::ProcessOutput.new('', 0) }
  let(:failure_output) { Puppet::Util::Execution::ProcessOutput.new('Failure', 1) }

  describe "#create" do
    it "should add -o when allowdupe is enabled and the group is being created" do
      @resource[:allowdupe] = :true
      @resource[:gid] = '555'
      # This is an unfortunate hack to prevent the parent class from
      # breaking when we execute everything in gpasswd instead of
      # returning the expected string to execute.
      provider.expects(:execute).with('/bin/true',
        :custom_environment => {},
        :failonfail         => true,
        :combine            => true,
        :sensitive          => false)

      provider.expects(:execute).with(
        '/usr/sbin/groupadd -g 555 -o mygroup',
        {
          :custom_environment => {},
          :failonfail         => false,
          :combine            => true
        }
      ).returns(success_output)

      provider.create
    end

    describe "on system that feature system_groups", :if => described_class.system_groups? do
      it "should add -r when system is enabled and the group is being created" do
        @resource[:system] = :true
        provider.expects(:execute).with('/bin/true',
          :custom_environment => {},
          :failonfail         => true,
          :combine            => true,
          :sensitive          => false)

        provider.expects(:execute).with(
          '/usr/sbin/groupadd -r mygroup',
          {
            :custom_environment => {},
            :failonfail         => false,
            :combine            => true
          }
        ).returns(success_output)
        provider.create
      end
    end

    describe "on system that do not feature system_groups", :unless => described_class.system_groups? do
      it "should not add -r when system is enabled and the group is being created" do
        @resource[:system] = :true
        provider.expects(:execute).with('/bin/true',
          :custom_environment => {},
          :failonfail         => true,
          :combine            => true,
          :sensitive          => false)

        provider.expects(:execute).with(
          '/usr/sbin/groupadd mygroup',
          {
            :custom_environment => {},
            :failonfail         => false,
            :combine            => true
          }
        ).returns(success_output)

        provider.create
      end
    end

    describe "when adding additional group members to a new group" do
       let(:members) { ['test_one','test_two','test_three'] }

      it "should pass all members individually as group add options to gpasswd" do
        provider.expects(:execute).with('/bin/true',
          :custom_environment => {},
          :failonfail         => true,
          :combine            => true,
          :sensitive          => false)

        provider.expects(:execute).with(
          '/usr/sbin/groupadd mygroup',
          {
            :custom_environment => {},
            :failonfail         => false,
            :combine            => true
          }
        ).returns(success_output)

        members.each do |member|
          provider.expects(:execute).with(
            "/usr/bin/gpasswd -a #{member} mygroup",
            {
              :custom_environment => {},
              :failonfail         => false,
              :combine            => true
            }
          ).returns(success_output)
        end

        provider.create
      end
    end

    describe "when adding additional group members to an existing group with no members" do
      let(:members) { ['test_one','test_two','test_three'] }

      it "should add all new members" do
        Etc.stubs(:getgrnam).with('mygroup').returns(
          Struct::Group.new('mygroup','x','99999',[])
        )
        @resource[:auth_membership] = :false
        members.each do |member|
          provider.expects(:execute).with(
            "/usr/bin/gpasswd -a #{member} mygroup",
            {
              :custom_environment => {},
              :failonfail         => false,
              :combine            => true
            }
          ).returns(success_output)
        end
        provider.create

        provider.members
        provider.members=(@resource.property('members').should)
      end
    end

    describe "when adding additional group members to an existing group with members" do
      let(:members) { ['test_one','test_two','test_three'] }

      it "should add all new members and preserve all existing members" do
        old_members = ['old_one','old_two','old_three','test_three']
        Etc.stubs(:getgrnam).with('mygroup').returns(
          Struct::Group.new('mygroup','x','99999',old_members)
        )
        @resource[:auth_membership] = :false
        (members | old_members).each do |member|
          provider.expects(:execute).with(
            "/usr/bin/gpasswd -a #{member} mygroup",
            {
              :custom_environment => {},
              :failonfail         => false,
              :combine            => true
            }
          ).returns(success_output)
        end
        provider.create

        provider.members
        provider.members=(@resource.property('members').should)
      end
    end

    describe "when adding exclusive group members to an existing group with members" do
      let(:members) { ['test_one','test_two','test_three'] }

      it "should add all new members and delete all, non-matching, existing members" do
        old_members = ['old_one','old_two','old_three','test_three']

        Etc.stubs(:getgrnam).with('mygroup').returns(
          Struct::Group.new('mygroup','x','99999',old_members)
        )

        @resource[:auth_membership] = :true

        provider.expects(:execute).with(
          "/usr/bin/gpasswd -M #{members.join(',')} mygroup",
          {
            :custom_environment => {},
            :failonfail         => false,
            :combine            => true
          }
        ).returns(success_output)

        provider.create

        provider.members
        provider.members=(@resource.property('members').should)
      end
    end
  end

  describe "#gid=" do
    it "should add -o when allowdupe is enabled and the gid is being modified" do
      @resource[:allowdupe] = :true
      if Gem::Version.new(Puppet.version) >= Gem::Version.new('5.4.0')
        provider.expects(:execute).with(['/usr/sbin/groupmod', '-g', 150, '-o', 'mygroup'], {
          :combine            => true,
          :sensitive          => false,
          :custom_environment => {},
          :failonfail         => true
        })
      else
        provider.expects(:execute).with(['/usr/sbin/groupmod', '-g', 150, '-o', 'mygroup'])
      end

      provider.gid = 150
    end
  end
end

