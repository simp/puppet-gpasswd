require 'spec_helper_acceptance'

test_name 'gpasswd extension'

describe 'gpasswd' do
  hoopy_froods = [
    'marvin',
    'arthur',
    'ford',
    'zaphod',
    'trillian'
  ]

  meddling_kids = [
    'fred',
    'daphne',
    'velma',
    'shaggy',
    'scooby'
  ]

  let(:manifest){<<-EOM
      $users = ['#{users.join("','")}']
      $users.each |$user| { user { $user: ensure => 'present' } }

      group { '#{group}': members => $users, system => #{system}, auth_membership => #{auth_membership} }
    EOM
  }

  hosts.each do |host|
    context 'with a sorted list of users' do
      let(:users) { hoopy_froods.sort }
      let(:auth_membership) { true }
      let(:system) { false }
      let(:group) { 'test' }

      # Using puppet_apply as a helper
      it 'should work with no errors' do
        apply_manifest_on(host, manifest, :catch_failures => true)
      end

      it 'should be idempotent' do
        apply_manifest_on(host, manifest, {:catch_changes => true})
      end

      it 'should have populated the group' do
        group_members = on(host, "getent group #{group}").output.strip.split(':').last.split(',')

        expect(group_members - users).to be_empty
      end
    end

    context 'with an unsorted list of users' do
      let(:users) { hoopy_froods - [hoopy_froods.last] }
      let(:auth_membership) { true }
      let(:system) { false }
      let(:group) { 'test' }

      # Using puppet_apply as a helper
      it 'should work with no errors' do
        apply_manifest_on(host, manifest, :catch_failures => true)
      end

      it 'should be idempotent' do
        apply_manifest_on(host, manifest, {:catch_changes => true})
      end

      it 'should have populated the group' do
        group_members = on(host, "getent group #{group}").output.strip.split(':').last.split(',')

        expect(group_members - users).to be_empty
      end
    end

    context 'when replacing existing users' do
      let(:users) { meddling_kids }
      let(:auth_membership) { true }
      let(:system) { false }
      let(:group) { 'test' }

      # Using puppet_apply as a helper
      it 'should work with no errors' do
        apply_manifest_on(host, manifest, :catch_failures => true)
      end

      it 'should be idempotent' do
        apply_manifest_on(host, manifest, {:catch_changes => true})
      end

      it 'should have populated the group' do
        group_members = on(host, "getent group #{group}").output.strip.split(':').last.split(',')

        expect(group_members - users).to be_empty
      end
    end

    context 'when adding all users' do
      let(:users) { hoopy_froods }
      let(:auth_membership) { false }
      let(:system) { false }
      let(:group) { 'test' }

      # Using puppet_apply as a helper
      it 'should work with no errors' do
        apply_manifest_on(host, manifest, :catch_failures => true)
      end

      it 'should be idempotent' do
        apply_manifest_on(host, manifest, {:catch_changes => true})
      end

      it 'should have populated the group' do
        group_members = on(host, "getent group #{group}").output.strip.split(':').last.split(',')

        expect(group_members - (users + meddling_kids)).to be_empty
      end
    end

    context 'when adding system groups' do
      let(:users) { ['user1', 'user2'] }
      let(:auth_membership) { true }
      let(:system) { true }
      let(:group) { 'test_system' }

      # Set the SYS_GID_[MAX/MIN] to be 499 so we can ensure we have a GID
      # within range
      it 'should set SYS_GID_[MAX,MIN] to 499' do
        on(host, "/usr/bin/grep -q 'SYS_GID_MIN' /etc/login.defs && /usr/bin/sed -i 's/SYS_GID_MIN.*/SYS_GID_MIN 499/g' /etc/login.defs || /usr/bin/echo 'SYS_GID_MIN 499' >> /etc/login.defs")
        on(host, "/usr/bin/grep -q 'SYS_GID_MAX' /etc/login.defs && /usr/bin/sed -i 's/SYS_GID_MAX.*/SYS_GID_MAX 499/g' /etc/login.defs || /usr/bin/echo 'SYS_GID_MAX 499' >> /etc/login.defs")
      end

      # Using puppet_apply as a helper
      it 'should work with no errors' do
        apply_manifest_on(host, manifest, :catch_failures => true)
      end
      it 'should be idempotent' do
        apply_manifest_on(host, manifest, {:catch_changes => true})
      end

      it 'should have populated the group' do
        group_members = on(host, "getent group #{group}").output.strip.split(':').last.split(',')
        expect(group_members - ['user1','user2']).to be_empty
      end

      it 'should have a GID of 499' do
        group_gid = on(host, "getent group #{group}").output.strip.split(':')[2]
        expect(group_gid).to eq '499'
      end
    end
  end
end
