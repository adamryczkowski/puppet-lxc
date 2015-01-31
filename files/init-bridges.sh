#!/bin/bash

#Plan jest następujący:
#Będzie plik: /etc/lxc/bridge-networks. Wewnątrz tego pliku, każda sieć będzie miała jeden wiersz, następującego formatu:
#<ifname>:<network domain>[:<hostip>:<dhcprange>]
#Plik będzie wczytywany i na jego podstawie będą tworzone sieci.



cd `dirname $0`

if [ -f common.sh ]; then 
	. ./common.sh
fi

#Ten skrypt konfiguruje kolejny mostek dla lxc-net na gospodarzu

#syntax:
#init-bridges.sh [-i|--internalif] <internal if name, e.g. lxcbr0> [-h|--hostip] <host ip, e.g. 10.0.3.1> [-n|--network <network domain, e.g. 10.0.14.0/24>] [--dhcprange] <dhcp range, e.g. '10.0.14.3,10.0.14.254' [--stop]
# -i|--internalif - internal if name, e.g. lxcbr0
# -h|--hostip - host ip, e.g. 10.0.14.1
# -n|--network network domain e.g. 10.0.14.0/24

LXC_BRIDGE="lxcbr0"
LXC_ADDR="10.0.3.1"
LXC_NETMASK="255.255.255.0"
LXC_NETWORK="10.0.3.0/24"
LXC_DOMAIN=""
action=0

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	-i|--internalif)
	LXC_BRIDGE="$1"
	shift
	;;
	--stop)
	action=1
	;;
	--netmask)
	LXC_NETMASK="$1"
	shift
	;;
	-h|--hostip)
	LXC_ADDR="$1"
	shift
	;;
	-n|--network)
	LXC_NETWORK="$1"
	shift
	;;
	--lxc-domain)
	LXC_DOMAIN=$1
	shift
	;;
	--log)
	log=$1
	shift
	;;
	--debug)
	debug=1
	;;
	*)
	echo "Unkown parameter '$key'. Aborting."
	exit 1
	;;
esac
done

use_iptables_lock="-w"
sudo iptables -w -L -n > /dev/null 2>&1 || use_iptables_lock=""
cleanup() {
	# dnsmasq failed to start, clean up the bridge
	sudo iptables $use_iptables_lock -D INPUT -i ${LXC_BRIDGE} -p udp --dport 67 -j ACCEPT
	sudo iptables $use_iptables_lock -D INPUT -i ${LXC_BRIDGE} -p tcp --dport 67 -j ACCEPT
	sudo iptables $use_iptables_lock -D INPUT -i ${LXC_BRIDGE} -p udp --dport 53 -j ACCEPT
	sudo iptables $use_iptables_lock -D INPUT -i ${LXC_BRIDGE} -p tcp --dport 53 -j ACCEPT
	sudo iptables $use_iptables_lock -D FORWARD -i ${LXC_BRIDGE} -j ACCEPT
	sudo iptables $use_iptables_lock -D FORWARD -o ${LXC_BRIDGE} -j ACCEPT
	sudo iptables $use_iptables_lock -t nat -D POSTROUTING -s ${LXC_NETWORK} ! -d ${LXC_NETWORK} -j MASQUERADE || true
	sudo iptables $use_iptables_lock -t mangle -D POSTROUTING -o ${LXC_BRIDGE} -p udp -m udp --dport 68 -j CHECKSUM --checksum-fill
	sudo ifconfig ${LXC_BRIDGE} down || true
	sudo brctl delbr ${LXC_BRIDGE} || true
}

if [ "$action" -eq "0" ]; then
	# set up the lxc network
	if ! brctl show | egrep "^${LXC_BRIDGE}" >/dev/null; then
		sudo brctl addbr ${LXC_BRIDGE} || { echo "Missing bridge support in kernel"; stop; exit 0; }
	fi
	if [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
		echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward >/dev/null
	fi

	curaddr=`ifconfig ${LXC_BRIDGE} | grep -Po 't addr:\K[\d.]+'`
	curnetmask=`ifconfig ${LXC_BRIDGE} | grep -Po 'Mask:\K[\d.]+'`

	if ifconfig | grep $LXC_BRIDGE >/dev/null; then
		ifup=1
	else
		ifup=0
	fi

	if [ "$ifup" -ne "1" ] || [ "$curaddr" != "${LXC_ADDR}" ] || [ "$curnetmask" != "$LXC_NETMASK" ]; then
		sudo ifconfig ${LXC_BRIDGE} ${LXC_ADDR} netmask ${LXC_NETMASK} up
	fi

	if ! sudo iptables $use_iptables_lock -C INPUT -i ${LXC_BRIDGE} -p udp --dport 67 -j ACCEPT 2>/dev/null; then
		sudo iptables $use_iptables_lock -I INPUT -i ${LXC_BRIDGE} -p udp --dport 67 -j ACCEPT
	fi
	if ! sudo iptables $use_iptables_lock -I INPUT -i ${LXC_BRIDGE} -p tcp --dport 67 -j ACCEPT 2>/dev/null; then
		sudo iptables $use_iptables_lock -I INPUT -i ${LXC_BRIDGE} -p tcp --dport 67 -j ACCEPT
	fi
	if ! sudo iptables $use_iptables_lock -C INPUT -i ${LXC_BRIDGE} -p udp --dport 53 -j ACCEPT 2>/dev/null; then
		sudo iptables $use_iptables_lock -I INPUT -i ${LXC_BRIDGE} -p udp --dport 53 -j ACCEPT
	fi
	if ! sudo iptables $use_iptables_lock -C INPUT -i ${LXC_BRIDGE} -p tcp --dport 53 -j ACCEPT 2>/dev/null; then
		sudo iptables $use_iptables_lock -I INPUT -i ${LXC_BRIDGE} -p tcp --dport 53 -j ACCEPT
	fi
	if ! sudo iptables $use_iptables_lock -C FORWARD -i ${LXC_BRIDGE} -j ACCEPT 2>/dev/null; then
		sudo iptables $use_iptables_lock -I FORWARD -i ${LXC_BRIDGE} -j ACCEPT
	fi
	if ! sudo iptables $use_iptables_lock -C FORWARD -o ${LXC_BRIDGE} -j ACCEPT 2>/dev/null; then
		sudo iptables $use_iptables_lock -I FORWARD -o ${LXC_BRIDGE} -j ACCEPT
	fi
	if ! sudo iptables $use_iptables_lock -t nat -C POSTROUTING -s ${LXC_NETWORK} ! -d ${LXC_NETWORK} -j MASQUERADE 2>/dev/null; then
		sudo iptables $use_iptables_lock -t nat -A POSTROUTING -s ${LXC_NETWORK} ! -d ${LXC_NETWORK} -j MASQUERADE
	fi
	if ! sudo iptables $use_iptables_lock -t mangle -C POSTROUTING -o ${LXC_BRIDGE} -p udp -m udp --dport 68 -j CHECKSUM --checksum-fill 2>/dev/null; then
		sudo iptables $use_iptables_lock -t mangle -A POSTROUTING -o ${LXC_BRIDGE} -p udp -m udp --dport 68 -j CHECKSUM --checksum-fill
	fi

	#if [ -n "$lxcdhcprange" ]; then
	#	restartdhcp=0
	#	if dpkg -s dnsmasq >/dev/null 2>/dev/null; then
	#		if [ ! -f /etc/dnsmasq.d-available ]; then
	#			sudo touch /etc/dnsmasq.d-available
	#		fi
	#		if [ ! -L /etc/dnsmasq.d/lxc ]; then
	#			sudo ln -s /etc/dnsmasq.d-available /etc/dnsmasq.d/lxc
	#		fi
	#		if ! egrep "^bind-interfaces$" /etc/dnsmasq.d/lxc; then
	#			echo "bind-interfaces" | sudo tee -a /etc/dnsmasq.d/lxc
	#			restartdhcp=1
	#		fi
	#		if ! egrep "^except-interface=$LXC_BRIDGE" /etc/dnsmasq.d/lxc; then
	#			echo "except-interface=$LXC_BRIDGE" | sudo tee -a /etc/dnsmasq.d/lxc
	#			restartdhcp=1
	#		fi
	#		if [ "$restartdhcp" -eq "1" ]; then
	#			if sudo service dnsmasq status >/dev/null; then
	#				sudo service dnsmasq restart
	#			fi
	#		fi
	#	else
	#		logexec sudo apt-get --yes install dnsmasq
	#	fi

	#	opts="-u lxc-dnsmasq --strict-order --bind-interfaces --pid-file=${varrun}/dnsmasq.pid --conf-file=${LXC_DHCP_CONFILE} --listen-address ${LXC_ADDR} --dhcp-range ${LXC_DHCP_RANGE} --dhcp-lease-max=${LXC_DHCP_MAX} --dhcp-no-override --except-interface=lo --interface=${LXC_BRIDGE} --dhcp-leasefile=/var/lib/misc/dnsmasq.${LXC_BRIDGE}.leases --dhcp-authoritative --keep-in-foreground"
	#	/usr/sbin/dnsmasq $opts &
	#fi
else
	# if $LXC_BRIDGE has attached interfaces, don't shut it down
	if ls /sys/class/net/${LXC_BRIDGE}/brif/* > /dev/null 2>&1; then
		exit 0
	fi
	cleanup
fi

