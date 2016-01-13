#!/bin/bash

LABNAME="VNLab"
DEPS="screen ip vde_switch linux bash start-stop-daemon racoon vtysh"
PROGNAME="$0"
PROGARGS="$@"
TMP='/tmp/vnlab'
set net      = "20.0.0.0/8"
set gw       = 20.0.0.1
set vmdomain = vnlab
set flags    = 'noprocmm'

#if ( $?DISPLAY ) then
#  set display = `echo $DISPLAY|sed "s/.*:/${gw}:/"` 
#else
#  set display = ${gw}:1.0
#fi

# Check for dependencies needed by this tool
check_dependencies() {
    for dep in $DEPS; do
	which $dep 2> /dev/null > /dev/null || {
	    echo "[!] Dependencia faltando: $dep"
	    exit 1
	}
    done
}
display_help() {
  clear;
  echo "==============================================================";
  echo "               VNLab: Virtual Network Lab";
  echo "==============================================================";
  echo "  NAVEGACAO:";
  echo "    - Ctrl+A+Espaco : Proxima Tela";
  echo "    - Ctrl+A+K      : Encerrar Tela";
  echo "";
  echo "  MENU:";
  echo "    C) Criar maquina virtual";
  echo "    E) Excluir maquinas antigas";
  echo "    A) Atualizar VNLab"
  echo "    S) Sair";
  echo "";

  echo "  Informe uma opcao do menu: ";
  read menu;
  
  
  case ${menu} in
    C)
        echo -e "  Informe o nome do host (ex.: \033[4mDNS, Firewall, etc\033[m)  ";
        read hostname;
        #setup_switch site1
        #start_vm V1	
        start_vm $hostname
        #eth0=vde,$TMP/switch-site1.sock eth1=vde,$TMP/switch-internet.sock
        display_help
    ;;
    E)
        #trap "rm -rf $TMP" EXIT
    ;;
    A)
        wget https://raw.githubusercontent.com/patrix/VNLab/master/scripts/update.sh
        chmod +x update.sh
        ./update.sh
        exit
    ;;
    S)
        exit
    ;;
    *)
        display_help
    ;;
  esac
}


# Run our lab in screen
setup_screen() {
    [ x"$TERM" = x"screen" ] || \
	exec screen -ln -S $LABNAME -c /dev/null -t MENU "$PROGNAME" "$PROGARGS"
    sleep 1
    screen -X zombie cr
    screen -X caption always "%{= wk}%-w%{= BW}%n %t%{-}%+w %-="
}

# Setup a VDE switch
setup_switch() {
    echo "[+] Setup switch $1"
    screen -t "switch-$1" \
	start-stop-daemon --make-pidfile --pidfile "$TMP/switch-$1.pid" \
	--start --startas $(which vde_switch) -- \
	--sock "$TMP/switch-$1.sock"
    screen -X select 0
}

# Start a VM
start_vm() {
    echo "[+] Start VM $1"
    name="$1"
    shift
    screen -t $name \
	start-stop-daemon --make-pidfile --pidfile "$TMP/vnlab.$name.pid" \
	--start --startas $(which linux) -- \
	uts=$name mem=64M \
	HOSTHOME=$name \
	GATEWAY=$gw \
	VMDOMAIN=$vmdomain \
	eth0=tuntap,,,20.0.0.1 \
	root=/dev/root rootfstype=hostfs init=$(readlink -f "$PROGNAME") \
	"$@"
}

cleanup() {
    for pid in $TMP/*.pid; do
	kill $(cat $pid)
    done
    screen -X quit
}

setup_quagga() {
    echo "[+] Start Quagga"
    export VTYSH_PAGER=/bin/cat
    rm -rf /etc/quagga
    ln -s $PWD/$uts/quagga /etc/quagga
    mkdir /var/log/quagga
    chown quagga:quagga /var/log/quagga
    :> /etc/quagga/daemons
    for conf in /etc/quagga/*.conf; do
	echo "$(basename ${conf%.conf})=yes" >> /etc/quagga/daemons
    done
    cp quagga-debian.conf /etc/quagga/debian.conf
    /etc/init.d/quagga start
}

setup_racoon() {
    rm -f /etc/racoon/racoon.conf
    ln -s $PWD/$uts/racoon/racoon.conf /etc/racoon/.
    mkdir /var/run/racoon
    cp racoon-psk.txt /etc/racoon/psk.txt
    chmod 600 /etc/racoon/psk.txt
    chown root /etc/racoon/psk.txt
    echo "[+] Setup IPsec policy"
    local="$1" ; shift
    remote="$1" ; shift
    for net in "$@"; do
	net1=${net%-*}
	net2=${net#*-}
	cat <<EOF
spdadd $net2 $net1 any -P in ipsec
  esp/tunnel/${remote}-${local}/require;
spdadd $net1 $net2 any -P out ipsec
  esp/tunnel/${local}-${remote}/require;
EOF
    done | setkey -c
    echo "[+] Start racoon"
    /etc/init.d/racoon start
}

case $$ in
    1)
	# Inside UML. Three states:
	#   1. Setup the getty
	#   2. Setup AUFS
	#   3. Remaining setup
	STATE=${STATE:-1}

	case $STATE in
	    1)
		echo "[+] Set hostname"
		hostname -b ${uts}
		echo "[+] Set path"
		export TERM=xterm
		export PATH=/usr/local/bin:/usr/bin:/bin:/sbin:/usr/local/sbin:/usr/sbin
		
		# Setup getty
		export STATE=2
		exec setsid python -c '
import os, sys
os.close(0)
os.open("/dev/tty0", os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK, 0)
os.dup2(0, 1)
os.dup2(0, 2)
# os.tcsetpgrp(0, 1)
os.execv(sys.argv[1], [sys.argv[1]])' "$PROGNAME"
		;;
	    2)
		echo "[+] Setup AUFS"
		mount -n -t proc proc /proc
		mount -n -t sysfs sysfs /sys
		mount -o bind /usr/lib/uml/modules /lib/modules
		mount -n -t tmpfs tmpfs /tmp -o rw,nosuid,nodev
		mkdir /tmp/ro
		mkdir /tmp/rw
		#mkdir /tmp/aufs
		mount -n -t hostfs hostfs /tmp/ro -o /,ro
		#mount -n -t aufs aufs /tmp/aufs -o noatime,dirs=/tmp/rw:/tmp/ro=ro

		# Chroot inside our new root
		#export STATE=3
		#exec chroot /tmp/aufs "$PROGNAME"
		;;
	esac

	echo "[+] Set filesystems"
	rm /etc/mtab
	mount -t proc proc /proc
	mount -t sysfs sysfs /sys
	mount -t tmpfs tmpfs /dev -o rw && {
	    cd /dev
	    if [ -f $(dirname "$PROGNAME")/dev.tar ]; then
		tar xf $(dirname "$PROGNAME")/dev.tar
	    else
		MAKEDEV null consoleonly
	    fi
	}
	mount -o bind /usr/lib/uml/modules /lib/modules
	for fs in /var/run /var/tmp /var/log /tmp; do
	    mount -t tmpfs tmpfs $fs -o rw,nosuid,nodev
	done
	mount -t hostfs hostfs $(dirname "$PROGNAME") -o $(dirname "$PROGNAME")

	# Interfaces
	echo "[+] Set interfaces"
	for intf in /sys/class/net/*; do
	    intf=$(basename $intf)
	    ip a l dev $intf 2> /dev/null >/dev/null && ip link set up dev $intf
	done

	echo "[+] Start syslog"
	rsyslogd

	cd $(dirname "$PROGNAME")
	[ -f dev.tar ] || {
	    tar -C /dev -cf dev.tar.$uts . && mv dev.tar.$uts dev.tar
	}

	# Configure each UML
	echo "[+] Setup UML"
	sysctl -w net.ipv4.ip_forward=1
	case ${uts} in
	    R1)
		modprobe dummy
		ip link set up dev dummy0
		ip addr add 192.168.15.1/24 dev dummy0
		ip addr add 192.168.1.10/24 dev eth0
		#setup_quagga
		;;
	    R2)
		modprobe dummy
		ip link set up dev dummy0
		ip addr add 192.168.115.1/24 dev dummy0
		ip addr add 192.168.101.10/24 dev eth0
		#setup_quagga
		;;
	    V1)
		ip addr add 192.168.1.11/24 dev eth0
		ip addr add 1.1.2.1/24 dev eth1
		ip route add default via 1.1.2.10
		#setup_quagga
		setup_racoon 1.1.2.1 1.1.1.1 192.168.0.0/19-192.168.100.0/19
		;;
	    V2)
		ip addr add 192.168.1.12/24 dev eth0
		ip addr add 1.1.2.2/24 dev eth1
		ip route add default via 1.1.2.10
		#setup_quagga
		setup_racoon 1.1.2.2 1.1.1.2 192.168.0.0/19-192.168.100.0/19
		;;
	    V3)
		ip addr add 192.168.101.13/24 dev eth0
		ip addr add 1.1.1.1/24 dev eth1
		ip route add default via 1.1.1.10
		#setup_quagga
		setup_racoon 1.1.1.1 1.1.2.1 192.168.100.0/19-192.168.0.0/19
		;;
	    V4)
		ip addr add 192.168.101.14/24 dev eth0
		ip addr add 1.1.1.2/24 dev eth1
		ip route add default via 1.1.1.10
		#setup_quagga
		setup_racoon 1.1.1.2 1.1.2.2 192.168.100.0/19-192.168.0.0/19
		;;
	    I1)
		ip addr add 1.1.1.10/24 dev eth0
		ip addr add 1.1.2.10/24 dev eth0
		;;
	esac

	echo "[+] Drop to a shell"
	exec /bin/bash

	;;
    *)
	TMP=$(mktemp -d)
	trap "rm -rf $TMP" EXIT
	check_dependencies
	setup_screen
	display_help
	cleanup
	;;
esac