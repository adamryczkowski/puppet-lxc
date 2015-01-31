# Title: how to test with regex parameterized, like /\|\s*${user}/?
#
# I need to get a user's home directory. I decided to get it with parsing a ::getent_passwd string (which is a custom fact build as
# concatenation of the contents of the `/etc/passwd`)
# and extract the relevant information with the help of the regex.
#
# When I test the `::getent` with fixed string ("`adam`"), extraction works:
# if "$::getent_passwd" =~ /\|adam:x:[^:]+:[^:]+:[^:]*:([^:]*):/ {
#  $user_home = $1
#  notify{"This works":}
#  }
# But when I build a regex with the `$user` variable, nothing gets matched:
# if "$::getent_passwd" =~ /\|${user}:x:[^:]+:[^:]+:[^:]*:([^:]*):/ {
#  $user_home = $1
# } else {
#  fail{"this fails":}
#}


define lxc (
  $user           = 'root',
  $bridge_iface   = 'lxcbr0',
  $bridge_gw      = '10.0.17.1',
  $bridge_network = '10.0.17.0/24',
  $bridge_netmask = '255.255.255.0',
  $dhcp_range     = '10.0.17.200,10.0.17.254',
  $subuid_base    = undef,
  $subuid_cnt     = undef,
  $linktoopts     = true,
  $bind_ns        = 'ns',
  $bind_ttl       = '604800',
  $use_bind       = $lxc::params::use_bind) {
  $var1 = "zosia"

  include lxc::common

  $user_home = gethomedir($user)

  if $user_home {
    $config_file = "${user_home}/.config/lxc/default.conf"

    if $user == "root" {
      $unprivileged = false

    } else {
      $unprivileged = true

    }

    #  if $use_bind {
    #    if $bridge_network =~ /(\d{1,3}).(\d{1,3}).(\d{1,3}).(\d{1,3})\/(\d+)/ {
    #      $netsize = $5
    #
    #      if $netsize == "24" {
    #        $arparev = "$3.$2.$1"
    #        $netfile = "$1.$2.$3"
    #      } elsif $netsize == "16" {
    #        $arparev = "$2.$1"
    #        $netfile = "$1.$2"
    #      } elsif $netsize == "8" {
    #        $arparev = "$1"
    #        $netfile = "$1"
    #      } else {
    #        fail("Unsupported network size $5 in $bridge_network parameter. The valid network sizes are: 24, 16 and 8.")
    #      }
    #    } else {
    #      fail("Uncompatible form of bridge_network $bridge_network parameter. Should be something like «10.0.13.0/24». ")
    #    }
    #    $fqdn_domain = "statystyka.net"
    #    include bind
    #
    #    bind::zone { '$fqdn_domain':
    #      zone_contact => '$user.$fqdn_domain',
    #      zone_ns      => '$bind_ns.$fqdn_domain',
    #      zone_ttl     => '$bind_ttl',
    #    }
    #
    #  }

    concat::fragment { "/etc/lxc/bridge-networks for ${user}":
      target  => '/etc/lxc/bridge-networks',
      content => "${bridge_iface}:${bridge_network}:${user}:${bridge_gw}:${dhcp_range}",
      notify  => [Service['lxc-net']]
    }

    concat::fragment { "dhcp record for ${bridge_iface}":
      target  => "/etc/lxc/dnsmasq.conf",
      content => "dhcp-range=${dhcp_range}",
      order   => 20,
      require => Package['lxc'],
      notify  => Service['lxc-dnsmasq']
    }

    file { "/var/lib/misc/dnsmasq.${bridge_iface}.leases":
      ensure    => absent,
      subscribe => Service['lxc-net']
    }

    if $unprivileged {
      if $linktoopts == true {
        file { "/opt/lxc/${user}":
          ensure => directory,
          owner  => $user,
        }

        file { "/opt/lxc/${user}/config":
          ensure => directory,
          owner  => $user,
          group  => $user
        }

        file { "/opt/lxc/${user}/store":
          ensure => directory,
          owner  => $user
        }

        file { "${user_home}/.local/share/lxc":
          owner  => $user,
          group  => $user,
          ensure => link,
          target => "/opt/lxc/${user}/store"
        }

        file { "${user_home}/.config/lxc":
          ensure => link,
          target => "/opt/lxc/${user}/config",
          owner  => $user,
          group  => $user
        }

      } else {
        file { "${user_home}/.local/share/lxc":
          ensure => directory,
          mode   => 0755,
          owner  => $user,
          group  => $user,
        }

        file { "${user_home}/.config/lxc":
          ensure => directory,
          mode   => 0755,
          owner  => $user,
          group  => $user,
        }

      }

      #     Zrób użytkownika ${user}

      if $subuid_base == undef {
        $subuid_prefix1 = ""

      } else {
        $subuid_prefix1 = "--baseid $subuid_base"
      }

      if $subuid_cnt == undef {
        $subuid_prefix2 = ""

      } else {
        $subuid_prefix2 = "--idcnt $subuid_cnt"
      }

      exec { "add_subuids for ${user}":
        command   => "/bin/bash /usr/local/lib/lxc-scripts/max-subuid.sh --user ${user} --add --subuid ${subuid_prefix1} ${subuid_prefix2} ",
        logoutput => true,
        unless    => "/bin/bash /usr/local/lib/lxc-scripts/max-subuid.sh --user ${user} --check --subuid ${subuid_prefix1} ${subuid_prefix2}",
        require   => File['/usr/local/lib/lxc-scripts/max-subuid.sh']
      }

      exec { "add_subgids for ${user}":
        command   => "/bin/bash /usr/local/lib/lxc-scripts/max-subuid.sh --user ${user} --add --subgid ${subuid_prefix1} ${subuid_prefix2}",
        logoutput => true,
        unless    => "/bin/bash /usr/local/lib/lxc-scripts/max-subuid.sh --user ${user} --check --subgid ${subuid_prefix1} ${subuid_prefix2}",
        require   => File['/usr/local/lib/lxc-scripts/max-subuid.sh']
      }
      $x1 = getbasesubuid($user)
      $x2 = getcntsubuid($user)

      #      notify { "For user $user basesubuid = ${x1} and cnt = ${x2}": }

      concat::fragment { "lxc-usernet row for user ${user}":
        target  => '/etc/lxc/lxc-usernet',
        content => template("lxc/lxc-usernet.erb"),
        order   => '11'
      }

      file { "${config_file}":
        owner   => $user,
        content => template("lxc/lxc-userspace-default.conf.erb"),
      }

      sshkeys::set_authorized_key { "root@localhost to ${user}@localhost":
        local_user  => $user,
        remote_user => "root@${::fqdn}",
        require     => Sshkeys::Create_ssh_key[$user]
      }

      sshkeys::create_ssh_key { $user: }

      #      augeas { "lxc ${name} lxc.network.link":
      #        incl    => "${config_file}",
      #        lens    => 'PHP.lns',
      #        #       onlyif  => "get .anon/lxc.network.link != ${bridge_iface}",
      #        changes => "set .anon/lxc.network.link ${bridge_iface}",
      #        require => [File["${config_file}"]]
      #      }
    }

  } else {
    warning("${user}'s home directory facts not ready on this session of puppet. Please run manifest once more.")
  }

}
