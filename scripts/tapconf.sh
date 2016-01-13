#!/bin/bash -x
sudo /usr/sbin/tunctl -u nobody
sudo /sbin/ifconfig tap0 20.0.0.1 down
sudo /sbin/ifconfig tap0 20.0.0.1 up
sudo /usr/bin/uml_switch -hub -tap tap0 -daemon < /dev/null > /dev/null
sudo chmod ugo+w /tmp/uml.ctl
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo sysctl net.ipv4.ip_forward=1
sudo brctl addbr route1
sudo brctl stp route1 off
sudo ip link set route1 up
sudo brctl addif route1 tap0
#sudo brctl addif route1 eth0
