class lxc::install::archlinux {
  $bridge_config = "Description=\"LXC Bridge\"
Interface=br0
Connection=bridge
BindsToInterfaces=(${bridge_iface})
IP=static
Address=(${bridge_ip})
Gateway=${bridge_gw}
FwdDelay=0"

  if $net_service != false {
    # iptables routing
    service { 'iptables':
      enable    => true,
      ensure    => 'running',
      require   => Exec[$net_service]
    }
    exec { 'iptables-cmd':
      command => "/sbin/iptables -t nat -A POSTROUTING -o br0 -j MASQUERADE && /usr/bin/iptables-save > /etc/iptables/iptables.rules",
      unless  => "/sbin/iptables -t nat -L | grep MASQUERADE",
      before  => File['/etc/netctl/lxcbridge'],
    }

    # ip forwarding (sysctl)
    file { '/etc/sysctl.d/20-ipforward.conf':
      ensure  => 'present',
      content => 'net.ipv4.ip_forward=1',
      before  => File['/etc/netctl/lxcbridge'],
    }
    exec { 'ipforward-lxcbridge':
      command => "/sbin/sysctl net.ipv4.ip_forward=1",
      unless  => "/sbin/sysctl -a | grep 'net.ipv4.ip_forward = 1'",
      before  => Exec[$net_service]
    }

    # netctl lxcbridge
    file { '/etc/netctl/lxcbridge':
      ensure  => 'present',
      content => "$bridge_config",
      notify  => Exec[$net_service],
    } ~>
    exec { $net_service:
      require   => [Package[$packages], File['/etc/netctl/lxcbridge']],
      unless    => "/usr/bin/ip addr | grep br0 | grep ${bridge_ip}",
      command   => "/sbin/netctl reenable ${net_service} && /sbin/netctl restart ${net_service} && /sbin/netctl store",
      subscribe => File['/etc/netctl/lxcbridge'],
    }

  }

}
