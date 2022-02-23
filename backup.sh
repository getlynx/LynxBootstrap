#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
#
# wget -qO - https://backup.getlynx.io/ | bash
#
# https://docs.getlynx.io/lynx-administration/snapshots
#

[ $EUID -ne 0 ] && echo "This script must be run from the root account. Exiting." && exit

systemctl stop lynxd

cd && currentDate=$(date +%F)

echo "Backup process is running. This may take a while."

if [[ -d /home/lynx/.lynx/testnet4 ]] # Check if testnet or mainnet
then
	tar -cf - --ignore-failed-read -C /home/lynx/.lynx/testnet4/blocks . | gzip | split -b 125M - "$currentDate"-blocks.tar.gz.
	tar -cf - --ignore-failed-read -C /home/lynx/.lynx/testnet4/chainstate . | gzip | split -b 125M - "$currentDate"-chainstate.tar.gz.
else
	tar -cf - --ignore-failed-read -C /home/lynx/.lynx/blocks . | gzip | split -b 125M - "$currentDate"-blocks.tar.gz.
	tar -cf - --ignore-failed-read -C /home/lynx/.lynx/chainstate . | gzip | split -b 125M - "$currentDate"-chainstate.tar.gz.
fi

sha256sum "$currentDate"-* > manifest.txt
