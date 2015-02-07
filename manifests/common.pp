class lxc::common ($use_bind = $lxc::params::use_bind, $unprivileged = $lxc::params::unprivileged) inherits lxc::params {
  if $use_bind {
    file { '/etc/bind/named.conf.options': source => "puppet:///modules/lxc/named.conf.options" }

    Bind::A <<| |>>

  }

  if defined(Package['shorewall']) {
    shorewall::zones::entry { 'lxc': type => 'ip' }

    shorewall::policy::entry { 'lxc-to-all':
      sourcezone      => 'lxc',
      destinationzone => 'all',
      policy          => 'ACCEPT',
      order           => 110
    }

    shorewall::policy::entry { 'lxc-to-all':
      sourcezone      => '$FW',
      destinationzone => 'lxc',
      policy          => 'ACCEPT',
      order           => 110
    }

    shorewall::rules::entry {
      'lxc ping-to-host':
        source      => 'lxc',
        destination => '$FW',
        order       => 210,
        action      => 'Ping(ACCEPT)';

      'icmp $FW->lxc':
        source      => '$FW',
        destination => 'lxc',
        proto       => 'icmp',
        order       => 210,
        action      => 'ACCEPT';
    }

  }

  package { 'lxc': ensure => installed }

  package { 'cgroup-bin': ensure => installed }

  # Poniższy kod powinien być dobry, ale nie chcę Puppetem zarządzać ssh_hosts
  #  $rsa_priv = ssh_keygen({
  #    name => "ssh_host_rsa_${::fqdn}",
  #    dir  => 'ssh/hostkeys'
  #  }
  #  )
  #  $rsa_pub  = ssh_keygen({
  #    name   => "ssh_host_rsa_${::fqdn}",
  #    dir    => 'ssh/hostkeys',
  #    public => 'true'
  #  }
  #  )
  #
  #  file { '/etc/ssh/ssh_host_rsa_key':
  #    owner   => 'root',
  #    group   => 'root',
  #    mode    => 0600,
  #    content => $rsa_priv,
  #  }
  #
  #  file { '/etc/ssh/ssh_host_rsa_key.pub':
  #    owner   => 'root',
  #    group   => 'root',
  #    mode    => 0644,
  #    content => "ssh-rsa $rsa_priv host_rsa_${::hostname}\n",
  #  }

  exec { "Add localhost to known hosts...":
    unless  => "/usr/bin/ssh-keygen -F localhost",
    command => "/usr/bin/ssh-keyscan -H localhost | /usr/bin/tee -a /root/.ssh/known_hosts",
    require => [File["/root/.ssh"]]
  }

  exec { "Add ${::fqdn} to known hosts...":
    unless  => "/usr/bin/ssh-keygen -F ${::fqdn}",
    command => "/usr/bin/ssh-keyscan -H ${::fqdn} | /usr/bin/tee -a /root/.ssh/known_hosts",
    require => [File["/root/.ssh"]]
  }

  # ssh-keyscan -t rsa,dsa HOST 2>&1 | sort -u - ~/.ssh/known_hosts > ~/.ssh/tmp_hosts


  if $unprivileged {
    # Zrób użytkownika ${user}
    file { '/opt/lxc':
      ensure => directory,
      owner  => $user,
    }

    sshkey { 'localhost':
      name         => $fqdn,
      ensure       => present,
      type         => 'rsa',
      key          => $::sshecdsakey,
      host_aliases => ["localhost", $::fqdn],
    }

    sshkeys::create_ssh_key { "root": }

  }
  $dnsmasq_conffile = '/etc/dnsmasq.conf'

  #  concat { $dnsmasq_conffile: notify => Service[lxc-dnsmasq], }

  concat { "/etc/lxc/dnsmasq.conf":
    ensure_newline => true,
    require        => Package['lxc']
  }

  package { 'dnsmasq': ensure => installed }

  file { '/etc/lxc/dnsmasq.d':
    ensure  => directory,
    require => Package['lxc']
  }

  file { '/etc/lxc/default':
    ensure  => file,
    require => Package['lxc'],
    content => ''
  }

  concat::fragment { "conf-dir=/etc/lxc/dnsmasq.d":
    target  => "/etc/lxc/dnsmasq.conf",
    content => 'conf-dir=/etc/lxc/dnsmasq.d',
    order   => 10,
    require => Package['lxc']
  }

  concat::fragment { 'user=lxc-dnsmasq':
    target  => "/etc/lxc/dnsmasq.conf",
    content => 'user=lxc-dnsmasq',
    order   => 10
  }

  concat::fragment { 'strict-order':
    target  => "/etc/lxc/dnsmasq.conf",
    content => 'strict-order',
    order   => 10
  }

  concat::fragment { 'bind-interfaces':
    target  => "/etc/lxc/dnsmasq.conf",
    content => 'bind-interfaces',
    order   => 10
  }

  concat::fragment { 'dhcp-no-override':
    target  => "/etc/lxc/dnsmasq.conf",
    content => 'dhcp-no-override',
    order   => 10
  }

  concat::fragment { 'except-interface=lo':
    target  => "/etc/lxc/dnsmasq.conf",
    content => 'except-interface=lo',
    order   => 10
  }

  concat::fragment { 'dhcp-leasefile=/var/lib/misc/lxc-dnsmasq.leases':
    target  => "/etc/lxc/dnsmasq.conf",
    content => 'dhcp-leasefile=/var/lib/misc/lxc-dnsmasq.leases',
    order   => 10
  }

  concat::fragment { 'dhcp-authoritative':
    target  => "/etc/lxc/dnsmasq.conf",
    content => 'dhcp-authoritative',
    order   => 10
  }

  #  file { '/etc/lxc/bridge-networks':
  #    ensure  => file,
  #    require => Package['lxc']
  #  }

  file { '/etc/init/lxc-net.conf':
    source  => 'puppet:///modules/lxc/lxc-net.conf',
    owner   => root,
    group   => root,
    require => Package['lxc'],
    notify  => Service['lxc-net'],
  }

  file { '/etc/init/lxc-dnsmasq.conf':
    source  => 'puppet:///modules/lxc/lxc-dnsmasq.conf',
    owner   => root,
    group   => root,
    require => [Package['lxc'], File['/etc/init/lxc-net.conf']],
    notify  => Service['lxc-dnsmasq']
  }

  file { '/etc/init/lxc-unprivileged-autostart.conf':
    source  => 'puppet:///modules/lxc/lxc-unprivileged-autostart.conf',
    owner   => root,
    group   => root,
    require => [Package['lxc'], File['/etc/init/lxc-dnsmasq.conf']],
    notify  => Service['lxc-dnsmasq']
  }

  file { '/etc/init/lxc-unprivileged-autostarts.conf':
    source  => 'puppet:///modules/lxc/lxc-unprivileged-autostarts.conf',
    owner   => root,
    group   => root,
    require => [Package['lxc'], File['/etc/init/lxc-unprivileged-autostart.conf']],
  #    notify  => Service['lxc-unprivileged-autostarts']
  }

  service { 'lxc-dnsmasq':
    ensure  => running,
    require => [Package['lxc'], File['/etc/init/lxc-dnsmasq.conf'], Service['dnsmasq']],
    enable  => true,
  }

  #  service { 'lxc-unprivileged-autostarts':
  #    ensure  => running ,
  #    require => File['/etc/init/lxc-unprivileged-autostarts.conf'],
  #    enable  => true,
  #  }

  concat { '/etc/lxc/lxc-usernet':
    ensure         => present,
    ensure_newline => true,
    require        => Package['lxc']
  }

  concat { "/etc/lxc/bridge-networks":
    ensure         => present,
    ensure_newline => true,
  }

  concat::fragment { "bridge-networks header 1":
    target  => "/etc/lxc/bridge-networks",
    content => "#Format pliku:",
    order   => '01'
  }

  concat::fragment { "bridge-networks header 2":
    target  => "/etc/lxc/bridge-networks",
    content => "#<ifname>:<network domain>[:<hostip>:[<dhcprange>]]",
    order   => '02'
  }

  concat::fragment { 'lxc-usernet heading 1':
    target  => '/etc/lxc/lxc-usernet',
    content => '# USERNAME TYPE BRIDGE COUNT',
    order   => '01'
  }

  concat::fragment { 'lxc-usernet heading 2':
    target  => '/etc/lxc/lxc-usernet',
    content => '# File is managed by Puppet',
    order   => '02'
  }

  service { 'lxc-net':
    ensure  => running,
    enable  => true,
    notify  => [Service['lxc-dnsmasq']],
    require => Package['lxc']
  }

  file { '/usr/local/lib/lxc-scripts': ensure => directory, }

  file { '/usr/local/lib/lxc-scripts/init-bridges.sh':
    source => 'puppet:///modules/lxc/init-bridges.sh',
    mode   => 0755,
  }

  file { '/usr/local/lib/lxc-scripts/max-subuid.sh':
    source => 'puppet:///modules/lxc/max-subuid.sh',
    mode   => 0755,
  }

  file { '/usr/local/lib/lxc-scripts/lxc-bridge-parser.sh':
    source => 'puppet:///modules/lxc/lxc-bridge-parser.sh',
    mode   => 0755,
  }

  service { 'dnsmasq':
    ensure  => stopped,
    require => Package['lxc']
  }

  #  file { '/etc/init.d/dnsmasq.override':
  #    content => 'manual',
  #    require => Package['dnsmasq']
  #  }

  augeas { "DISABLE dnsmasq":
    incl    => "/etc/default/dnsmasq",
    lens    => 'Shellvars.lns',
    onlyif  => "get ENABLED != 0",
    changes => "set ENABLED 0",
    require => Package['dnsmasq']
  }

