#!/bin/bash -x

rm vnlab.sh
rm tapconf.sh
rm /etc/vnlab/start
rm /etc/init.d/tapconf.sh
wget https://raw.githubusercontent.com/patrix/VNLab/master/scripts/vnlab.sh
wget https://raw.githubusercontent.com/patrix/VNLab/master/scripts/tapconf.sh
mv vnlab.sh /etc/vnlab/start
ln -s /etc/vnlab/start /usr/bin/vnlab
mv tapconf.sh /etc/init.d/tapconf.sh
chmod +x /etc/vnlab/start
chmod +x /etc/init.d/tapconf.sh
/etc/init.d/tapconf.sh

update-rc.d tapconf.sh defaults