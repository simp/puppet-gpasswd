# AGENTS.md

This file provides guidance to AI agents when working with code in this repository.

## What this module does

`puppet-gpasswd` (package name `simp-gpasswd`) is a small Puppet module that adds local group
*membership management* to the native `group` resource type via `gpasswd`. Puppet's built-in
group providers cannot add/remove individual members (e.g. when users are defined remotely, such
as via LDAP) — this module patches that in by registering a new provider, `gpasswd`, that
subclasses `Puppet::Type::Group::ProviderGroupadd` and layers `gpasswd` calls on top of it. No
custom type, class, or manifest code is involved; the entire implementation is one provider file:

- `lib/puppet/provider/group/gpasswd.rb` — the whole module logic lives here.

Key behaviors implemented by the provider:
- `addcmd` — when creating a group, runs the normal `groupadd` command and then adds each initial
  member via `gpasswd -a <user> <group>`.
- `modifycmd` — mirrors the parent nameservice provider's modify command, but no-ops (`/bin/true`)
  for the `-m` (members) flag on Puppet 6.20+ because that flag's behavior on these versions
  removes members instead of adding them.
- `members` / `members=` / `members_insync?` — read current members via `Puppet::Etc.getgrnam`,
  reconcile against desired members, and either exclusively set membership
  (`gpasswd -M user1,user2 group`, used when `auth_membership => true`) or incrementally add
  missing members (`gpasswd -a user group` per user, when `auth_membership => false`). Unknown
  users (not resolvable via `Puppet::Etc.getpwnam`/`getpwuid`) are filtered out of the "should"
  list rather than failing the run.
- `mod_group` (private) — executes the built-up list of `gpasswd`/`groupadd`/`groupmod` commands
  in order, logging (not raising) on failures so one bad member doesn't abort the whole group
  resource.
- `is_new_format?` — detects whether the running Puppet's `members` property is a
  `Puppet::Property::List` (newer Puppet) vs. a plain array (older Puppet), since the two
  represent "current"/"should" members differently (comma-joined string vs. array). Most of the
  quirky branching in this file exists to paper over that Puppet-version difference plus the
  Puppet 6.20+ `-m` regression noted above — don't "simplify" those branches without checking
  which Puppet versions are still supported (`metadata.json` / `openvox` requirement).

Consuming manifests need no changes — just use the native `group` type as usual:
```puppet
group { 'test':
  members => ['foo', 'bar', 'baz'],
}
```
`auth_membership` (native group parameter) controls exclusive vs. additive membership management,
as shown above.

## Common Commands

```bash
bundle install                                     # Install dependencies
bundle exec rake spec                              # Run unit tests (rspec-puppet)
bundle exec rspec spec/unit/provider/group/gpasswd_spec.rb   # Run the single unit test file
bundle exec rspec spec/unit/provider/group/gpasswd_spec.rb -e 'adds -o when allowdupe'  # Single example
bundle exec rake acceptance                        # Run acceptance tests (Beaker, requires Docker)
BEAKER_set=docker_rocky9 bundle exec rake acceptance # Run acceptance against one nodeset
bundle exec rake lint                               # Puppet-lint (there's no manifests/ here, mostly a no-op)
bundle exec rake syntax                             # Syntax checks
bundle exec rake metadata_lint                      # Validate metadata.json
bundle exec rubocop lib spec                        # Ruby lint (the actual linting that matters for this module)
```

Useful environment variables for `bundle install` (see `Gemfile`):
- `PUPPET_VERSION` / `OPENVOX_VERSION` — Pin the Puppet/OpenVox gem version (default: `>= 8, < 9`)
- `SIMP_RAKE_HELPERS_VERSION`, `SIMP_RSPEC_PUPPET_FACTS_VERSION`, `SIMP_BEAKER_HELPERS_VERSION`

## Testing notes

- Unit tests (`spec/unit/provider/group/gpasswd_spec.rb`) work by stubbing `described_class.command`
  and asserting on the exact shell command strings/arrays passed to `provider.execute`, including
  the `custom_environment:`/`failonfail:`/`combine:` options hash. When changing command
  construction in the provider, expect to update these exact-string expectations.
- One example (`'passes all members individually as groupadd options to gpasswd'`) is marked
  `pending 'FIXME'` — it documents a known-broken/unimplemented interaction between `addcmd` and
  initial member assignment on `create`. Don't be surprised it doesn't pass; don't "fix" it by
  changing the assertions without understanding why it's pending.
- Acceptance tests (`spec/acceptance/suites/default/00_default_spec.rb`) apply real manifests via
  Beaker across the OS matrix in `spec/acceptance/nodesets/` and check membership with
  `getent group`, covering: sorted/unsorted member lists, replacing members, additive vs. exclusive
  membership, system groups, and references to nonexistent users.
- `has_feature :manages_members`, `:libuser`, and `:system_groups` are gated off for `HP-UX`/`Solaris`
  and libuser availability — this module effectively only targets Linux with native `gpasswd`.

## Module Structure

This module deliberately has no `manifests/`, `functions/`, `types/`, `templates/`, or `data/` —
it is a pure Ruby type/provider extension:

```
lib/puppet/provider/group/gpasswd.rb   # entire implementation
spec/unit/provider/group/               # rspec unit tests
spec/acceptance/                        # Beaker acceptance tests + nodesets
build/rpm_metadata/requires             # RPM Obsoletes: pupmod-onyxpoint-gpasswd < 2.0.0 (old module name)
```

Note the RPM `Obsoletes:` entry — this module was renamed from `onyxpoint-gpasswd` to
`simp-gpasswd` (metadata `name`), so packaging still needs to obsolete the old package name for
upgrades.
