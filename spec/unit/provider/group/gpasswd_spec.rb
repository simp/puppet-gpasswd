#!/usr/bin/env rspec
require 'spec_helper'

describe Puppet::Type.type(:group).provider(:gpasswd) do
  before do
    allow(described_class).to receive(:command).with(:add).and_return('/usr/sbin/groupadd')
    allow(described_class).to receive(:command).with(:delete).and_return('/usr/sbin/groupdel')
    allow(described_class).to receive(:command).with(:modify).and_return('/usr/sbin/groupmod')
    allow(described_class).to receive(:command).with(:addmember).and_return('/usr/bin/gpasswd')
    allow(described_class).to receive(:command).with(:modmember).and_return('/usr/bin/gpasswd')

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

      expect(provider).to receive(:execute).with(
        '/usr/sbin/groupadd -g 555 -o mygroup',
        hash_including(
          {
            :custom_environment => anything,
            :failonfail         => false,
            :combine            => true
          }
        )
      ).and_return(success_output)

      # This is an unfortunate hack to prevent the parent class from
      # breaking when we execute everything in gpasswd instead of
      # returning the expected string to execute.
      expect(provider).to receive(:execute).with(
        '/bin/true',
        hash_including(
          {
            :custom_environment => anything,
            :failonfail         => true,
            :combine            => true
          }
        )
      )

      provider.create
    end

    describe "on system that feature system_groups", :if => described_class.system_groups? do
      it "should add -r when system is enabled and the group is being created" do
        @resource[:system] = :true
        expect(provider).to receive(:execute).with(
          '/bin/true',
          hash_including(
            {
              :custom_environment => anything,
              :failonfail         => true,
              :combine            => true
            }
          )
        )

        expect(provider).to receive(:execute).with(
          '/usr/sbin/groupadd -r mygroup',
          hash_including(
            {
              :custom_environment => anything,
              :failonfail         => false,
              :combine            => true
            }
          )
        ).and_return(success_output)
        provider.create
      end
    end

    describe "on system that do not feature system_groups", :unless => described_class.system_groups? do
      it "should not add -r when system is enabled and the group is being created" do
        @resource[:system] = :true
        expect(provider).to receive(:execute).with(
          '/bin/true',
          hash_including(
            {
              :custom_environment => anything,
              :failonfail         => true,
              :combine            => true
            }
          )
        )

        expect(provider).to receive(:execute).with(
          '/usr/sbin/groupadd mygroup',
          hash_including(
            {
              :custom_environment => anything,
              :failonfail         => false,
              :combine            => true
            }
          )
        ).and_return(success_output)

        provider.create
      end
    end

    describe "when adding additional group members to a new group" do
       let(:members) { ['test_one','test_two','test_three'] }

      it "should pass all members individually as groupadd options to gpasswd" do
        expect(provider).to receive(:execute).with(
          '/usr/sbin/groupadd mygroup',
          hash_including(
            {
              :custom_environment => anything,
              :failonfail         => false,
              :combine            => true
            }
          )
        ).and_return(success_output)

        expect(provider).to receive(:execute).with(
          include('/bin/true'),
          hash_including(
            {
              :custom_environment => anything,
              :failonfail         => true,
              :combine            => true
            }
          )
        ).at_least(:once)

        members.each do |member|
          expect(provider).to receive(:execute).with(
            "/usr/bin/gpasswd -a #{member} mygroup",
            hash_including(
              {
                :custom_environment => anything,
                :failonfail         => false,
                :combine            => true
              }
            )
          ).and_return(success_output)
        end

        provider.create
      end
    end

    describe "when adding additional group members to an existing group with no members" do
      let(:members) { ['test_one','test_two','test_three'] }

      it "should add all new members" do
        allow(provider).to receive(:execute).with(
          include('/bin/true'),
          hash_including(
            {
              :custom_environment => anything,
              :failonfail         => true,
              :combine            => true
            }
          )
        )

        expect(Puppet::Etc).to receive(:getgrnam).with('mygroup').and_return(
          Struct::Group.new('mygroup','x','99999',[])
        ).at_least(:once)

        @resource[:auth_membership] = :false
        members.each do |member|
          expect(provider).to receive(:execute).with(
            "/usr/bin/gpasswd -a #{member} mygroup",
            hash_including(
              {
                :custom_environment => anything,
                :failonfail         => false,
                :combine            => true
              }
            )
          ).and_return(success_output)
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

        allow(provider).to receive(:execute).with(
          include('/bin/true'),
          hash_including(
            {
              :custom_environment => anything,
              :failonfail         => true,
              :combine            => true
            }
          )
        )

        expect(Puppet::Etc).to receive(:getgrnam).with('mygroup').and_return(
          Struct::Group.new('mygroup','x','99999',old_members)
        ).at_least(:once)

        @resource[:auth_membership] = :false
        (members | old_members).each do |member|
          expect(provider).to receive(:execute).with(
            "/usr/bin/gpasswd -a #{member} mygroup",
            hash_including(
              {
                :custom_environment => anything,
                :failonfail         => false,
                :combine            => true
              }
            )
          ).and_return(success_output)
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

        allow(provider).to receive(:execute).with(
          include('/bin/true'),
          hash_including(
            {
              :custom_environment => anything,
              :failonfail         => true,
              :combine            => true
            }
          )
        )

        expect(Puppet::Etc).to receive(:getgrnam).with('mygroup').and_return(
          Struct::Group.new('mygroup','x','99999',old_members)
        ).at_least(:once)

        @resource[:auth_membership] = :true

        expect(provider).to receive(:execute).with(
          "/usr/bin/gpasswd -M #{members.join(',')} mygroup",
          hash_including(
            {
              :custom_environment => anything,
              :failonfail         => false,
              :combine            => true
            }
          )
        ).and_return(success_output)

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
        expect(provider).to receive(:execute).with(
          ['/usr/sbin/groupmod', '-g', 150, '-o', 'mygroup'],
          hash_including(
            {
              :custom_environment => anything,
              :failonfail         => true,
              :combine            => true
            }
          )
        )
      else
        expect(provider).to receive(:execute).with(['/usr/sbin/groupmod', '-g', 150, '-o', 'mygroup'])
      end

      provider.gid = 150
    end
  end
end

