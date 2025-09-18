require 'spec_helper_acceptance'

test_name 'gpasswd extension'

describe 'gpasswd' do
  hoopy_froods = [
    'marvin',
    'arthur',
    'ford',
    'zaphod',
    'trillian',
  ]

  meddling_kids = [
    'fred',
    'daphne',
    'velma',
    'shaggy',
    'scooby',
  ]

  let(:manifest) do
    <<~EOM
      $users = ['#{users.join("','")}']
      $users.each |$user| { user { $user: ensure => 'present' } }

      group { '#{group}': members => $users, gid => #{gid}, system => #{system}, auth_membership => #{auth_membership} }
    EOM
  end

  let(:auth_membership) { true }
  let(:system) { false }
  let(:group) { 'test' }
  let(:gid) { '1111' }

  hosts.each do |host|
    context 'with a sorted list of users' do
      # When the tests pass with this in place, then upstream puppet has
      # achieved functionaly parity
      #       it 'should whack the module' do
      #         on(host, 'rm -rf /etc/puppetlabs/code/environments/production/modules/gpasswd')
      #         on(host, 'rm -rf `puppet config print vardir`/lib/*')
      #       end

      let(:users) { hoopy_froods.sort }

      # Using puppet_apply as a helper
      it 'works with no errors' do
        apply_manifest_on(host, manifest, catch_failures: true)
      end

      it 'is idempotent' do
        apply_manifest_on(host, manifest, { catch_changes: true })
      end

      it 'has populated the group' do
        group_members = on(host, "getent group #{group}").output.strip.split(':')[3].split(',') || []

        expect(group_members - users).to be_empty
      end
    end

    context 'with an unsorted list of users' do
      let(:users) { hoopy_froods - [hoopy_froods.last] }

      # Using puppet_apply as a helper
      it 'works with no errors' do
        apply_manifest_on(host, manifest, catch_failures: true)
      end

      it 'is idempotent' do
        apply_manifest_on(host, manifest, { catch_changes: true })
      end

      it 'has populated the group' do
        group_members = on(host, "getent group #{group}").output.strip.split(':')[3].split(',') || []

        expect(group_members - users).to be_empty
      end
    end

    context 'when replacing existing users' do
      let(:users) { meddling_kids }

      # Using puppet_apply as a helper
      it 'works with no errors' do
        apply_manifest_on(host, manifest, catch_failures: true)
      end

      it 'is idempotent' do
        apply_manifest_on(host, manifest, { catch_changes: true })
      end

      it 'has populated the group' do
        group_members = on(host, "getent group #{group}").output.strip.split(':')[3].split(',') || []

        expect(group_members - users).to be_empty
      end
    end

    context 'when adding all users' do
      let(:users) { hoopy_froods }

      # Using puppet_apply as a helper
      it 'works with no errors' do
        apply_manifest_on(host, manifest, catch_failures: true)
      end

      it 'is idempotent' do
        apply_manifest_on(host, manifest, { catch_changes: true })
      end

      it 'has populated the group' do
        group_members = on(host, "getent group #{group}").output.strip.split(':')[3].split(',') || []

        expect(group_members - (users + meddling_kids)).to be_empty
      end
    end

    context 'when adding system groups' do
      let(:users) { ['user1', 'user2'] }
      let(:system) { true }
      let(:gid) { '333' }

      # Using puppet_apply as a helper
      it 'works with no errors' do
        apply_manifest_on(host, manifest, catch_failures: true)
      end
      it 'is idempotent' do
        apply_manifest_on(host, manifest, { catch_changes: true })
      end

      it 'has populated the group' do
        group_members = on(host, "getent group #{group}").output.strip.split(':')[3].split(',') || []

        expect(group_members - ['user1', 'user2']).to be_empty
      end

      it 'has a GID of 333' do
        group_gid = on(host, "getent group #{group}").output.strip.split(':')[2]
        expect(group_gid).to eq '333'
      end
    end

    context 'with a user that does not exist' do
      let(:manifest) do
        <<~EOM
          user { 'real': ensure => 'present' }
          user { 'fake': ensure => 'absent' }
          group { 'real': members => ['real','fake'] }
        EOM
      end

      it 'adds the real user to the real group' do
        apply_manifest_on(host, manifest, catch_failures: true)
      end

      it 'is idempotent' do
        apply_manifest_on(host, manifest, catch_changes: true)
      end
    end

    context 'ensure that "puppet resource group" still functions' do
      it 'runs "puppet resource group" without issue' do
        on(host, 'puppet resource group')
      end
    end
  end
end
