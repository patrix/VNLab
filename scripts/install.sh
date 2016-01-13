#!/bin/bash -x

apt-get install user-mode-linux screen vde2 racoon aufs-tools quagga csh

export PATH=$PATH:/usr/local/uml

mkdir /etc/vnlab
rm vnlab.sh
rm tapconf.sh
rm /etc/vnlab/start
rm /etc/init.d/tapconf.sh
#wget http://vnlab.patrickkaminski.com/vnlab.sh
#wget http://vnlab.patrickkaminski.com/tapconf.sh
wget https://raw.githubusercontent.com/patrix/VNLab/master/scripts/vnlab.sh
wget https://raw.githubusercontent.com/patrix/VNLab/master/scripts/tapconf.sh
mv vnlab.sh /etc/vnlab/start
ln -s /etc/vnlab/start /usr/bin/vnlab
mv tapconf.sh /etc/init.d/tapconf.sh
chmod +x /etc/vnlab/start
chmod +x /etc/init.d/tapconf.sh
/etc/init.d/tapconf.sh



update-rc.d tapconf.sh defaults
