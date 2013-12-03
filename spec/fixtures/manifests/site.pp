node default {
  group { 'foobar':
    ensure                => 'present',
    members               => [
      'root',
      'test',
      'tomcat',
      'ldap'
    ],
    attribute_membership  => 'inclusive'
  }
}
