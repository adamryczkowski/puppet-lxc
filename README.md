puppet-lxc
==========

This is Puppet module for managing a host with a farm of (by default unprivileged) LXC containers.

## Features
* Allows creation of unprivileged LXC container under a pre-existing user.
* Installs (replaces) upstart scripts that manage multiple independent bridge networks (i.e. you can have lxcbr0  and lxcbr1)
* Supports autostarting the containers; ships with custom upstart scripts for that.
* All static IPs are managed by dnsmasq (in /etc/lxc/dnsmasq.conf) rather than in the container itself. This ensures there are no IP collisions.
* Supports installation of puppet client on the guest (uses supplied fqdn as a certname identifying the node)
* Allows for simple management of user's subuids a subgids. At this moment allows only for one continuous block of ids.

## Possible problems
* Due to the lxc bug, after the first run you must restart the host.
* Because of usage of custom facts, full deployment of new lxc container requires three runs of the manifest (errors are gracefully handled).
* Because of the conflict of default configuration of dnsmasq, the repository is *incompatible* with service dnsmasq (the service gets installed, as it is boundled with the `dnsmasq` package, but gets overriden to 'manual'.

## Supported OS:
* Ubuntu 14.04 LTS

Tested Containers:
* apt-get - compatible. 

## Example manifest
    node 'mylxcfarm.example.com' {
      #First we need to create the unprivileged user 'myuser':
      user { 'myuser':
        ensure => present,
        home   => "/home/myuser",
        purge_ssh_keys => true,
      }
    
      group { "myuser": ensure => present, }
    
      exec { "myuser homedir":
        command => "/bin/cp -R /etc/skel /home/myuser; /bin/chown -R myuser:myuser /home/myuser",
        creates => "/home/myuser",
        require => [User['myuser'], Group['myuser']]
      }
    
      file { ["/home/myuser/.config", "/home/myuser/.cache", "/home/myuser/.local", "/home/myuser/.local/share"]:
        ensure  => directory,
        owner   => 'myuser',
        group   => 'myuser',
        require => Exec["myuser homedir"]
      }
    
      #Declare 'myuser' for unprivileged containers and create necessary bridge networks
      lxc { "myuser":
        user           => "myuser",
        bridge_iface   => 'lxcbr1',
        bridge_gw      => '10.0.16.1',
        bridge_network => '10.0.16.0/24',
        bridge_netmask => '255.255.255.0',
        dhcp_range     => '10.0.16.200,10.0.16.254',
      }
    
      #Define the actual container with static IP
      lxc::container { "mycontainer":
        user               => "myuser",
        ip                 => '10.0.16.10',
        autoboot           => true,
        puppet             => true,
        fqdn               => 'mycontainer.mylxcfarm.example.com',
        aptproxy           => '192.168.56.1:3142',
        puppet_server_host => 'puppetmaster.example.com'
      }
    }

## Custom facts
### `getsubuid` and `getsubgid`
`getsubuid` returns and array of subuids and subgids necessary for managing unprivileged containers. For parsing this array use custom functions `getbasesubuid`, `getbasesubgid`, `getcntsubuid` and `getcntsubgid`.

**Example:**
`getsubuid => myuser:100000:65536|myuser2:165536:65536|mlxc:231072:65536|alxc:296608:65536|pupecik:362144:65536|`
`getsubgid => myuser:100000:65536|myuser2:165536:65536|mlxc:231072:65536|alxc:296608:65536|pupecik:362144:65536|`

### `uid_myuser`
Each user gets `uid_<username>` fact with his uid. 

**Example**

`uid_myuser => 1001`
`uid_alxc => 1004`

## Custom functions
### `getbasesubuid` and `getbasesubgid`
`getbasesubuid('myuser')` returns base of the range of the continuous block of subuids/subgids

### `getcntsubuid` and `getcntsubgid`
`getcntsubuid('myuser')` returns number of uids in the continuous block of subuids/subgids

