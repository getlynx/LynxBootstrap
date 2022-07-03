#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
#
# This script should be run as the Lynx user with regard to LynxCI. It assumes Lynx is already installed.
#
# Runs best if miner is off. Weird Python socket errors pop up otherwise
# Lynx RPC can't respond fast enough to the scripts RPC calls.
#
#
# wget -O - https://raw.githubusercontent.com/getlynx/LynxBootstrap/master/archive.sh | bash
#
# https://docs.getlynx.io/lynx-administration/bootstraps
#

rpcuser="$(/bin/sed -ne 's|[\t]*rpcuser=[\t]*||p' /home/lynx/.lynx/lynx.conf)"
rpcpassword="$(/bin/sed -ne 's|[\t]*rpcpassword=[\t]*||p' /home/lynx/.lynx/lynx.conf)"
getCurrentBlock="$(lynx-cli getblockcount)"
getCurrentBlock=$((getCurrentBlock - 2900000))

rm -rf /home/lynx/linearize*
rm -rf /home/lynx/hashlist.txt
rm -rf /home/lynx/*bootstrap*
rm -rf /home/lynx/manifest.txt

wget -q https://raw.githubusercontent.com/getlynx/Lynx/master/contrib/linearize/linearize-data.py
wget -q https://raw.githubusercontent.com/getlynx/Lynx/master/contrib/linearize/linearize-hashes.py

echo "
rpcuser=$rpcuser
rpcpassword=$rpcpassword
host=127.0.0.1
port=9332
max_height=$getCurrentBlock
netmagic=facfb3dc
genesis=e7dd146b0867a671abf67d7292e2f62b1ae8854f58ca367547297f0b7f115498
input=/home/lynx/.lynx/blocks
output_file=/home/lynx/bootstrap.dat
hashlist=hashlist.txt
out_of_order_cache_sz = 100000000
rev_hash_bytes = False
file_timestamp = 0
split_timestamp = 0
debug_output = False
" > /home/lynx/linearize.cfg

chmod 775 /home/lynx/linearize*

sleep 5

/home/lynx/linearize-hashes.py linearize.cfg > hashlist.txt

sleep 5

chmod 775 /home/lynx/hashlist.txt

sleep 5

/home/lynx/linearize-data.py linearize.cfg

sleep 5

currentDate=$(date +%F)
tar -cf - --ignore-failed-read --warning=no-file-changed /home/lynx/bootstrap.dat . | gzip | split -b 125M - "$currentDate"-bootstrap.tar.gz.
sha256sum "$currentDate"-* > manifest.txt

rm -rf /home/lynx/linearize*
rm -rf /home/lynx/hashlist.txt
rm -rf /home/lynx/bootstrap.dat
