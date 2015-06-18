Summary: GPasswd Puppet Module
Name: pupmod-onyxpoint-gpasswd
Version: 1.0.0
Release: 1
License: Apache License, Version 2.0
Group: Applications/System
Source: %{name}-%{version}-%{release}.tar.gz
Buildroot: %{_tmppath}/%{name}-%{version}-%{release}-buildroot
Requires: puppet >= 2.7.0-0
Buildarch: noarch
Requires: simp-bootstrap >= 4.2.0
Obsoletes: pupmod-onyxpoint-gpasswd-test

Prefix: /etc/puppet/environments/simp/modules

%description
This puppet module adds gpasswd support to the native user type.

%prep
%setup -q

%build

%install
[ "%{buildroot}" != "/" ] && rm -rf %{buildroot}

mkdir -p %{buildroot}/%{prefix}/gpasswd

dirs='files lib manifests templates'
for dir in $dirs; do
  test -d $dir && cp -r $dir %{buildroot}/%{prefix}/gpasswd
done

%clean
[ "%{buildroot}" != "/" ] && rm -rf %{buildroot}

mkdir -p %{buildroot}/%{prefix}/gpasswd

%files
%defattr(0640,root,puppet,0750)
%{prefix}/gpasswd

%post
#!/bin/sh

%postun
# Post uninstall stuff

%changelog
* Thu Feb 12 2015 Trevor Vaughan <tvaughan@onyxpoint.com> - 1.0.0-1
- Migrated to the simp environment

* Wed Apr 23 2014 Trevor Vaughan <tvaughan@onyxpoint.com> - 1.0.0-0
- First RPM build
