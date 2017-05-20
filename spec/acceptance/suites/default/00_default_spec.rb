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

      group { 'test': members => $users, auth_membership => #{auth_membership} }
    EOM
  }

  hosts.each do |host|
    context 'with a sorted list of users' do
      let(:users) { hoopy_froods.sort }
      let(:auth_membership) { true }

      # Using puppet_apply as a helper
      it 'should work with no errors' do
        apply_manifest_on(host, manifest, :catch_failures => true)
      end

      it 'should be idempotent' do
        apply_manifest_on(host, manifest, {:catch_changes => true})
      end

      it 'should have populated the group' do
        group_members = on(host, 'getent group test').output.strip.split(':').last.split(',')

        expect(group_members - users).to be_empty
      end
    end

    context 'with an unsorted list of users' do
      let(:users) { hoopy_froods - [hoopy_froods.last] }
      let(:auth_membership) { true }

      # Using puppet_apply as a helper
      it 'should work with no errors' do
        apply_manifest_on(host, manifest, :catch_failures => true)
      end

      it 'should be idempotent' do
        apply_manifest_on(host, manifest, {:catch_changes => true})
      end

      it 'should have populated the group' do
        group_members = on(host, 'getent group test').output.strip.split(':').last.split(',')

        expect(group_members - users).to be_empty
      end
    end

    context 'when replacing existing users' do
      let(:users) { meddling_kids }
      let(:auth_membership) { true }

      # Using puppet_apply as a helper
      it 'should work with no errors' do
        apply_manifest_on(host, manifest, :catch_failures => true)
      end

      it 'should be idempotent' do
        apply_manifest_on(host, manifest, {:catch_changes => true})
      end

      it 'should have populated the group' do
        group_members = on(host, 'getent group test').output.strip.split(':').last.split(',')

        expect(group_members - users).to be_empty
      end
    end

    context 'when adding all users' do
      let(:users) { hoopy_froods }
      let(:auth_membership) { false }

      # Using puppet_apply as a helper
      it 'should work with no errors' do
        apply_manifest_on(host, manifest, :catch_failures => true)
      end

      it 'should be idempotent' do
        apply_manifest_on(host, manifest, {:catch_changes => true})
      end

      it 'should have populated the group' do
        group_members = on(host, 'getent group test').output.strip.split(':').last.split(',')

        expect(group_members - (users + meddling_kids)).to be_empty
      end
    end
  end
end
