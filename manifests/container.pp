
define lxc::container (
  $hostname            = $name,
  $user                = 'root',
  $template            = $lxc::params::template,
  $release             = $lxc::params::release,
  $ensure              = 'present',
  $enable              = true,
  $mem_limit           = '512M',
  $mem_plus_swap_limit = '1024M',
  $ip                  = undef,
  $facts               = undef,
  $autoboot            = true,
  $puppet              = false,
  $fqdn                = undef,
  $lxcuser             = undef,
  $aptproxy            = undef,
  $ssh_nat_port        = undef,
  $puppet_server_host  = 'puppetmaster',
  $puppet_server_ip    = '127.0.0.1') {
  # directory of lxc_auto file is used to check if lxc container is created

  $user_home    = gethomedir("${user}")
  $bridge_iface = getparam(Lxc[$user], 'bridge_iface')

  #  notify { "Home directory at container ${name} for user ${user} is ${user_home}": }

  if $user_home {
    if $user == "root" {
      $unprivileged = false
      # lxc configuration file
      $lxc_prefix   = "/var/lib/lxc/${name}"

      if undef == $lxcuser {
        $lxc_prefix1 = ""
      } else {
        $lxc_prefix1 = "-u ${lxcuser}"
      }

      if undef == $aptproxy {
        $lxc_prefix2 = ""
      } else {
        $lxc_prefix2 = "--mirror ${aptproxy}/archive.ubuntu.com/ubuntu"
      }

      $lxc_create = "/usr/bin/lxc-create -n ${name} -t ${template} -- -r ${release} ${lxc_prefix1} ${lxc_prefix2}"
    } else {
      $unprivileged = true
      # lxc configuration file
      $lxc_prefix   = "${user_home}/.local/share/lxc/${name}"
      $lxc_create   = "/usr/bin/lxc-create -t download -n ${name} -- -d ${template} -r ${release} -a amd64"

    }
  } else {
    warning("Cannot find ${user}'s home directory ('${user_home}')")
  }

  if $fqdn == undef or $fqdn == $name {
    fail("Bad fqdn (${fqdn}) for container ${name}.")
  }

  if $lxc_prefix {
    $config_file = "${lxc_prefix}/config"
    $lxc_root    = "${lxc_prefix}/rootfs"

    case $ensure {
      'present' : {
        if $ssh_nat_port != undef and defined(Package['shorewall']) {
          shorewall::rules::entry { "incoming-ssh-${name}":
            source          => 'all',
            destination     => "lxc:${name}:22",
            action          => 'DNAT',
            proto           => 'tcp',
            destinationport => $ssh_nat_port,
            order           => 110;
          }
        }

        if $facts != undef {
          file { "${lxc_root}/etc/facter":
            ensure  => 'directory',
            owner   => $user,
            require => Exec["lxc-create ${name}"],
          }

          file { "${lxc_root}/etc/facter/facts.d":
            ensure => 'directory',
            owner  => $user
          }

          file { "{$lxc_root}/etc/facter/facts.d/lxc_module.yaml":
            ensure  => 'present',
            require => Exec["lxc-create ${name}"],
            content => inline_template('<%= facts.to_yaml %>');
          }
        }

        augeas { "lxc ${name} lxc.include local config":
          incl    => "${config_file}",
          lens    => 'PHP.lns',
          #       onlyif  => "get .anon/lxc.include != \"${user_home}/.config/lxc/default.conf\"",
          changes => "set .anon/lxc.include \"${user_home}/.config/lxc/default.conf\"",
          require => Exec["lxc-create ${name}"],
          before  => Exec["lxc-start ${name}"]
        }

        augeas { "lxc ${name} rm lxc.id_map":
          incl    => "${config_file}",
          lens    => 'PHP.lns',
          changes => "rm .anon/lxc.id_map",
          require => Exec["lxc-create ${name}"],
          before  => Exec["lxc-start ${name}"]
        }

        #        augeas { "lxc ${name} rm lxc.network.link":
        #          incl    => "${config_file}",
        #          lens    => 'PHP.lns',
        #          changes => "rm .anon/lxc.network.link",
        #          require => Exec["lxc-create ${name}"]
        #          before => Exec["lxc-start ${name}"]
        #        }

        if $ip != undef {
          file { "/etc/lxc/dnsmasq.d/${name}.conf":
            content => "dhcp-host=${name},${ip}",
            notify  => Service['lxc-dnsmasq'],
            before  => Exec["lxc-start ${name}"]
          }

          #        if $fqdn =~ /([[:alnum:]])+\..+/ {
          #          $honstname_final = $1
          #        } else {
          #          $hostname = $fqdn
          #        }

          host { "${fqdn}":
            ip           => $ip,
            host_aliases => $hostname,
            require      => Exec["lxc-create ${name}"]
          }

          file { "${lxc_root}/etc/hostname":
            content => "${fqdn} ${name}",
            owner   => getbasesubuid($user),
            before  => Exec["lxc-start ${name}"],
            require => [Exec["lxc-create ${name}"], User[$user]]
          }

          #        host { "${fqdn} for lxc ${name}":
          #          ip           => $ip,
          #          name         => $fqdn,
          #          host_aliases => $hostname,
          #          target       => "${lxc_root}/etc/hosts",
          #          require      => Exec["lxc-create ${name}"],
          #          before       => Exec["lxc-start ${name}"]
          #        }
        }

        if $unprivileged {
          file { "$config_file":
            owner   => $user,
            group   => $user,
            content => template("lxc/lxc-userspace.conf.erb"),
            before  => Exec["lxc-start ${name}"]
          }
          $sshprefix = "/usr/bin/ssh ${user}@${::fqdn}"
        } else {
          $sshprefix = ""
        }

        exec { "Add ${fqdn} to known hosts for user ${user}...":
          unless  => "/usr/bin/ssh-keygen -F ${fqdn}",
          command => "/usr/bin/ssh-keyscan -H ${fqdn} | /usr/bin/tee -a ${user_home}/.ssh/known_hosts",
          user    => $user,
          require => [File["${user_home}/.ssh"], Exec["lxc-start ${name}"]]
        }

        exec { "Add ${hostname} to known hosts for user ${user}...":
          unless  => "/usr/bin/ssh-keygen -F ${hostname}",
          command => "/usr/bin/ssh-keyscan -H ${hostname} | /usr/bin/tee -a ${user_home}/.ssh/known_hosts",
          user    => $user,
          require => [File["${user_home}/.ssh"], Exec["lxc-start ${name}"]]
        }

        exec { "lxc-create ${name}":
          command   => "${sshprefix} ${lxc_create}",
          logoutput => 'on_failure',
          creates   => $config_file,
          timeout   => 60000,
          #          user        => $user,
          #          environment => ["HOME=${user_home}"],
          require   => [Lxc["${user}"], User[$user], Exec["Add ${::fqdn} to known hosts..."]]
        }

        if $user != undef and $unprivileged {
          exec { "add user ${lxcuser} for lxc ${name}":
            command => "${sshprefix} /usr/bin/lxc-attach -n ${name} -- adduser --disabled-password --add_extra_groups --quiet --gecos '' ${lxcuser} ",
            creates => "${lxc_root}/home/${lxcuser}",
            #            user    => $user,
            require => [Exec["lxc-start ${name}"], Exec["Add ${::fqdn} to known hosts..."]]
          }
        }

        if $aptproxy != undef and $unprivileged {
          file { "${lxc_root}/etc/apt/apt.conf.d/31apt-cacher-ng":
            content => "Acquire::http { Proxy \"http://${aptproxy}\"; };",
            owner   => getbasesubuid($user),
            group   => getbasesubgid($user),
            mode    => 0644,
            require => Exec["lxc-create ${name}"]
          }
        }

        $user_uid = getuidfn($user)

        exec { "lxc-start ${name}":
          command => "${sshprefix} /usr/bin/lxc-start -d -n ${name} -o ${user_home}/lxc-${name}.log -l INFO && ${sshprefix} lxc-wait -n ${name} -s RUNNING -t 3",
          unless  => "${sshprefix} /usr/bin/lxc-info -n ${name} | /bin/grep 'State' | /bin/grep 'RUNNING'",
          require => [Exec["lxc-create ${name}"], Exec["Add ${::fqdn} to known hosts..."]],
          notify  => Service['lxc-dnsmasq']
        #        user        => $user,
        }

        exec { "Install ssh for lxc ${name}":
          command     => "${sshprefix} /usr/bin/lxc-attach -n ${name} -- apt-get install --yes language-pack-pl openssh-server",
          creates     => "${lxc_root}/usr/sbin/sshd",
          require     => [Host["${fqdn}"], Exec["lxc-start ${name}"], Exec["Add ${::fqdn} to known hosts..."]],
          environment => ["HOME=${user_home}", "XDG_RUNTIME_DIR=/run/user/${$user_uid}"],
        }

        file { "${lxc_root}/root/.ssh":
          ensure  => directory,
          owner   => getbasesubuid($user),
          group   => getbasesubgid($user),
          require => [Exec["lxc-create ${name}"]],
        }

        file { "${lxc_root}/root/.ssh/authorized_keys":
          ensure => file,
          owner  => getbasesubuid($user),
          group  => getbasesubgid($user),
        }

        if getvar("sshpubkey_${user}") {
          file_line { "added pubkey of ${user} on host to ${name} lxc":
            path => "${lxc_root}/root/.ssh/authorized_keys",
            line => getvar("sshpubkey_${user}")
          }

        } else {
          warning("sshpubkey_${user} fact not available. Please run manifest once more.")
        }

        if $puppet {
          exec { "Install puppetmaster for lxc ${name}":
            command     => "${sshprefix} /usr/bin/lxc-attach -n ${name} -- bash -- /usr/local/lib/lxc-scripts/configure-puppetclient.sh --puppetmaster ${puppet_server_host}",
            creates     => "${lxc_root}/usr/bin/puppet",
            #            user        => $user,
            require     => [
              Host["${fqdn}"],
              Exec["lxc-start ${name}"],
              File["${lxc_root}/usr/local/lib/lxc-scripts/configure-puppetclient.sh"],
              Exec["Add ${::fqdn} to known hosts..."]],
            environment => ["HOME=${user_home}", "XDG_RUNTIME_DIR=/run/user/${$user_uid}"],
          }

          file { "${lxc_root}/usr/local/lib/lxc-scripts":
            ensure  => directory,
            owner   => $user,
            group   => $user,
            require => Exec["lxc-create ${name}"]
          }

          file { "${lxc_root}/usr/local/lib/lxc-scripts/configure-puppetclient.sh":
            ensure  => file,
            owner   => $user,
            group   => $user,
            source  => "puppet:///modules/lxc/configure-puppetclient.sh",
            require => Exec["lxc-create ${name}"]
          }

          file { "${lxc_root}/usr/local/lib/lxc-scripts/common.sh":
            ensure  => file,
            owner   => $user,
            group   => $user,
            source  => "puppet:///modules/lxc/common.sh",
            require => Exec["lxc-create ${name}"]
          }
        }

      }
      'stopped' : {
        exec { "lxc-stop ${name}":
          unless  => "${sshprefix} /usr/bin/lxc_info | /bin/grep State | /bin/grep STOPPED",
          command => "${sshprefix} /usr/bin/lxc_stop -n ${name}",
          user    => $user,
          require => Lxc["${name}"]
        }

      }

      'absent'  : {
        if $ip != undef {
          file { "/etc/lxc/dnsmasq.d/${name}.conf":
            ensure  => absent,
            notify  => Service['lxc-dnsmasq'],
            require => Lxc["${name}"]
          }

          host { "$fqdn":
            ip      => $ip,
            ensure  => absent,
            require => Lxc["${name}"]
          }

        }

        exec { "lxc-destroy ${name}":
          onlyif  => "/usr/bin/test -d ${lxc_root}",
          command => "${sshprefix} /usr/bin/lxc_destroy -n ${name}",
          user    => $user,
          require => Exec["lxc-stop ${name}"]
        }

        file { $config_file:
          ensure  => 'absent',
          require => Exec["lxc-stop ${name}"]
        }

      }

      default   : {
        fail('ensure must be present, absent or stopped')
      }
    }
  }

}
