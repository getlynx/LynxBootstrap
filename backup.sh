#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
#
# wget -qO - https://backup.getlynx.io/ | bash
#

[ $EUID -ne 0 ] && echo "This script must be run from the root account. Exiting." && exit

systemctl stop lynxd

cd && currentDate=$(date +%F)

echo "Backup process is running. This may take a while."

tar -cf - --ignore-failed-read -C /home/lynx/.lynx/blocks . | gzip | split -b 125M - "$currentDate"-blocks.tar.gz.
tar -cf - --ignore-failed-read -C /home/lynx/.lynx/chainstate . | gzip | split -b 125M - "$currentDate"-chainstate.tar.gz.

sha256sum "$currentDate"-* > manifest.txt
