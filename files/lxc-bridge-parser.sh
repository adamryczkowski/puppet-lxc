#!/bin/bash

#Skrypt tworzący konfigurację dla dnsmasq i lxc-usernet na podstawie informacji zawartych w /etc/lxc/bridge-networks

#Plan jest następujący:
#Będzie plik: /etc/lxc/bridge-networks. Wewnątrz tego pliku, każda sieć będzie miała jeden wiersz, następującego formatu:
#<ifname>:<network domain>:<user>[:<hostip>:[<dhcprange>]]
#Plik będzie wczytywany i na jego podstawie będą tworzone sieci.

INSTALLDIR="/usr/local/lib/lxc-scripts"

cd `dirname $0`

if [ -f common.sh ]; then 
	. ./common.sh
fi

#syntax:
#lxc-bridge-parser.sh [--conf-file <path>] [--remove-dhcp-leases | --remove-all ]
# --conf-file - path to the configuration file
# --remove-dhcp-leases
# --remove-all - destroys all bridges


#mode=0 - make dnsmasq i user-net config files only, =1 - manage-bridges
#action=1 - start, =2 - stop, =3 - restart
mode=0
action=1
conffile="/etc/lxc/bridge-networks"

dnsmasq_conffile="/etc/lxc/dnsmasq.conf"
lxcusernet_conffile="/etc/lxc/lxc-usernet"
fixconffile=0

while [[ $# > 0 ]]
do
key="$1"
shift

case $key in
	--fix-dnsmasq-conffile)
	fixconffile=1
	;;
	--conf-file)
	conffile="$1"
	shift
	;;
	--remove-dhcp-leases)
	mode=0
	action=3
	;;
	--stop-bridges)
	action=2
	mode=1
	;;
	--restart-bridges)
	action=3
	mode=1
	;;
	--start-bridges)
	mode=1
	action=1
	;;
	*)
	echo "Unkown parameter '$key'. Aborting."
	exit 1
	;;
esac
done


if [ ! -f $conffile ]; then
	echo "Configuration file $conffile is missing!" >/dev/stderr
	exit 1
fi

if [ "$fixconffile" == "1" ]; then

	if [ ! -f $dnsmasq_conffile ]; then
		sudo touch $dnsmasq_conffile
	fi
	
	if ! grep -Fxq "user=lxc-dnsmasq" $dnsmasq_conffile; then
		echo "user=lxc-dnsmasq" | sudo tee -a $dnsmasq_conffile
	fi
	
	if ! grep -Fxq "strict-order" $dnsmasq_conffile; then
		echo "strict-order" | sudo tee -a $dnsmasq_conffile
	fi
	
	if ! grep -Fxq "bind-interfaces" $dnsmasq_conffile; then
		echo "bind-interfaces" | sudo tee -a $dnsmasq_conffile
	fi
	
	if ! grep -Fxq "dhcp-no-override" $dnsmasq_conffile; then
		echo "dhcp-no-override" | sudo tee -a $dnsmasq_conffile
	fi
	
	if ! grep -Fxq "except-interface=lo" $dnsmasq_conffile; then
		echo "except-interface=lo" | sudo tee -a $dnsmasq_conffile
	fi
	
	if ! grep -Fxq "dhcp-leasefile=/var/lib/misc/lxc-dnsmasq.leases" $dnsmasq_conffile; then
		echo "dhcp-leasefile=/var/lib/misc/lxc-dnsmasq.leases" | sudo tee -a $dnsmasq_conffile
	fi
	
	if ! grep -Fxq "dhcp-authoritative" $dnsmasq_conffile; then
		echo "dhcp-authoritative" | sudo tee -a $dnsmasq_conffile
	fi
fi	



if dpkg -s dnsmasq >/dev/null 2>/dev/null; then
	if [ ! -f /etc/dnsmasq.d-available ]; then
		sudo touch /etc/dnsmasq.d-available
	fi
	if [ ! -L /etc/dnsmasq.d/lxc ]; then
		sudo ln -s /etc/dnsmasq.d-available /etc/dnsmasq.d/lxc
	fi
	if ! egrep -q "^bind-interfaces$" /etc/dnsmasq.d/lxc; then
		echo "bind-interfaces" | sudo tee -a /etc/dnsmasq.d/lxc
	fi
else
	sudo apt-get --yes install dnsmasq
fi

# poniższy for popraw tak, aby iterował po kolejnych wierszach pliku konfiguracyjnego
while read line || [[ -n $line ]]; do
	regex1="^#.*$"
	regex2="^\s*$"
	if [[ ! $line =~ $regex1 ]] && [[ ! $line =~ $regex2 ]]; then
		slot1="[[:lower:]]+[[:digit:]]*"
		slot4="[0-2]?[[:digit:]]{1,2}\.[0-2]?[[:digit:]]{1,2}\.[0-2]?[[:digit:]]{1,2}\.[0-2]?[[:digit:]]{1,2}"
		slot2="$slot4\/[[:digit:]]+"
		slot3="[[:lower:]]+[[:digit:][:lower:]]*"
		slot5="$slot4,$slot4"
		regex1="^($slot1):($slot2):($slot3):($slot4):($slot5)\s*$"
		regex2="^($slot1):($slot2):($slot3):($slot4)\s*$"
		regex3="^($slot1):($slot2):($slot3)\s*$"
		if [[ "$line" =~ $regex1 ]]; then
			ifname=${BASH_REMATCH[1]}
			network=${BASH_REMATCH[2]}
			user=${BASH_REMATCH[3]}
			hostip=${BASH_REMATCH[4]}
			dhcprange=${BASH_REMATCH[5]}
		elif [[ "$line" =~ $regex2 ]]; then
			ifname=${BASH_REMATCH[1]}
			network=${BASH_REMATCH[2]}
			user=${BASH_REMATCH[3]}
			hostip=${BASH_REMATCH[4]}
			dhcprange="auto" # należy zgadnąć dhcprange na podstawie network. 
		elif [[ "$line" =~ $regex3 ]]; then
			ifname=${BASH_REMATCH[1]}
			network=${BASH_REMATCH[2]}
			user=${BASH_REMATCH[3]}
			hostip="auto" # należy założyć, że hostip = pierwszy host w zadanym zakresie, tj. network xx.xx.xx.1
			dhcprange="auto" # należy zgadnąć dhcprange na podstawie network. 
		else
			echo "Malformed configuration line «$line» in file $conffile" >/dev/stderr
			exit 2
		fi
		regex1="^([0-2]?[[:digit:]]{1,2})\.([0-2]?[[:digit:]]{1,2})\.([0-2]?[[:digit:]]{1,2})\.([0-2]?[[:digit:]]{1,2})\/([[:digit:]]+)$"
		if [[ ! $network =~ $regex1 ]]; then
			echo "Malformed network parameter: $network in $conffile. Needs to be in form e.g. 192.168.13.0/24" >/dev/stderr
			exit 3
		fi
		ip1=${BASH_REMATCH[1]}
		ip2=${BASH_REMATCH[2]}
		ip3=${BASH_REMATCH[3]}
		ip4=${BASH_REMATCH[4]}
		netsize=${BASH_REMATCH[5]}
		if [ "$hostip" == "auto" ]; then
			hostip="$ip1.$ip2.$ip3.1"
		fi
		if [ "$dhcprange" == "auto" ]; then
		case $netsize in
			24)
			dhcprange="$ip1.$ip2.$ip3.2,$ip1.$ip2.$ip3.254"
			;;
			16)
			dhcprange="$ip1.$ip2.0.2,$ip1.$ip2.254.254"
			;;
			8)
			dhcprange="$ip1.0.0.2,$ip1.0.254.254"
			;;
			*)
			echo "Cannot guess dhcprange from network other than 24, 16 or 8." >/dev/stderr
			exit 4
			;;
		esac
		fi
		if [ "$mode" -eq "0" ]; then
			dnsmasqrow="dhcp-range=$dhcprange"
			if ! grep -Fxq "$dnsmasqrow" $dnsmasq_conffile && [ "$fixconffile" == "1" ]; then
				echo "$dnsmasqrow" | sudo tee -a $dnsmasq_conffile
			fi
			if ! egrep -q "^except-interface=$ifname" /etc/dnsmasq.d/lxc; then
				echo "except-interface=$ifname" | sudo tee -a /etc/dnsmasq.d/lxc
			fi
			if [ "$user" != "root" ]; then
				usernetrow="$user veth $ifname 10"
				if ! grep -Fxq "$usernetrow" $lxcusernet_conffile; then
					regex1="^[[:alnum:]]+\s*[[:alnum:]]+\s*$ifname"
					if egrep -q "$regex1" $lxcusernet_conffile; then
						sudo sed -i -r "/$regex1/d" $lxcusernet_conffile
					fi
					echo "$usernetrow" | sudo tee -a $lxcusernet_conffile
				fi
			fi
			
			if [ "$action" -eq "3" ]; then
				#Restart dhcp leases. Requires dnsmasq down
				if [ -f /var/lib/misc/dnsmasq.$ifname.leases ]; then
					if sudo ls /var/lib/misc/dnsmasq.$ifname.leases >/dev/null; then
						sudo rm /var/lib/misc/dnsmasq.$ifname.leases 2>/dev/null
					fi
				fi
			fi
		elif [ "$mode" -eq "1" ]; then
			case $action in
				1)
					$INSTALLDIR/init-bridges.sh --internalif $ifname --hostip $hostip --network $network 
				;;
				2)
					$INSTALLDIR/init-bridges.sh --internalif $ifname --hostip $hostip --network $network --stop
				;;
				3)
					$INSTALLDIR/init-bridges.sh --internalif $ifname --hostip $hostip --network $network --stop
					$INSTALLDIR/init-bridges.sh --internalif $ifname --hostip $hostip --network $network 
				;;
				*)
				echo "INTERNAL ERROR 2" >/dev/stderr
				exit 101
				;;
			esac
		else
			echo "INTERNAL ERROR" >/dev/stderr
			exit 100
		fi
	fi
done <$conffile

