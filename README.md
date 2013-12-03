puppet-gpasswd
==============

Puppet-driven local group modification capabilities for Linux systems
gpasswd

This is a module that enhances the native group type on systems
supporting gpasswd to allow for the manipulation of group memebers.

Specifically, it adds the :manages_members attribute to the native
Puppet group type. No alterations to your group code are required!

Examples
========

group { 'test':
  members => ['foo','bar','baz']
}

License
-------

Apache License 2.0

Contact
-------

Trevor Vaughan <tvaughan@onyxpoint.com>

Support
-------

Please log tickets and issues at our [Gpasswd Github Site](https://github.com/onyxpoint/puppet-gpasswd/issues)
