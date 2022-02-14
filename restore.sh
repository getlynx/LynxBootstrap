#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[ -z "$1" ] && tag="v7.0-mainnet" || tag="$1" # v7.0-mainnet is default.

release="https://github.com/getlynx/LynxBootstrap/releases/download/$tag/" # Release version

rm -rf manifest.txt # If previously run, purge old file
wget -q "$release"manifest.txt # Pull down the manifest
sed -i 's/  /:/' manifest.txt # Clean it up for easy usage
while IFS= read -r line; do # Loop over each file and check the hashes match
	hash=$(echo "$line" | cut -d ":" -f 1)
	file=$(echo "$line" | cut -d ":" -f 2)
	if [ ! -f "$file" ]; then # Only download the file if it doesn't exist locally
		wget -q "$release$file"
	fi
	if [ "$(sha256sum "$file" | awk '{print $1}')" = "$hash" ]; then
		echo "LynxCI: $file hash match $hash"
	else # Hash doesn't match
		rm -rf $file
		wget -q "$release$file"
		if [ "$(sha256sum "$file" | awk '{print $1}')" = "$hash" ]; then
			echo "LynxCI: Sanity check - $file hash match $hash"
		else
			echo "LynxCI: Corrupt bootstrap file"
			exit
		fi
	fi
done < manifest.txt
cat *blocks.tar.gz.* | gunzip | (rm -rf /tmp/blocks && mkdir -p /tmp/blocks && cd /tmp/blocks && tar xf -)
cat *chainstate.tar.gz.* | gunzip | (rm -rf /tmp/chainstate && mkdir -p /tmp/chainstate && cd /tmp/chainstate && tar xf -)
