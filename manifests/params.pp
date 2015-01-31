class lxc::params {
  $bridge_gw      = '"10.0.17.1"'
  $use_bind       = false
  $bridge_network = '"10.0.17.0/24"'
  $dhcp_range     = '"10.0.17.200,10.0.17.254"'
  $unprivileged   = true
  $template       = 'ubuntu'
  $release        = 'trusty'
  $bridge_iface   = 'lxcbr0'
  $bridge_netmask = '255.255.255.0'
  $fqdn_domain    = "statystyka.net"
}
