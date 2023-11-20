#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
#
# This script should be run as the Lynx user with regard to LynxCI. It assumes Lynx is already installed.
#
# wget -O - https://raw.githubusercontent.com/getlynx/LynxBootstrap/master/extract.sh | bash
#
# https://docs.getlynx.io/lynx-administration/bootstraps
#

# Lets determine where to place the final bootstrap.data file.
# If Lynx is installed in the home dir of the respective user,
# than place the file in the ~/.lynx dir, otherwise drop the file
# in the users ~/ directory.
target="$HOME"
[ -f "$HOME/.lynx/lynx.conf" ] && target="$HOME/.lynx" # Only support for mainnet.

# If an argument is not supplied with the shell script, then
# assume the latest release version is being requested. This
# is most often the case.
[ -z "$1" ] && tag="latest" || tag="$1" # vX.0-mainnet is default.
release="https://github.com/getlynx/LynxBootstrap/releases/download/$tag/" # Release version labeled by tag
[ "$tag" = "latest" ] && { release="https://github.com/getlynx/LynxBootstrap/releases/latest/download/"; }

echo "Deliverable will be found here: $target/bootstrap.dat"
#cd $target/ || exit
rm -rf "$target/manifest.txt" # If previously run, purge old file
rm -rf "$target/bootstrap.dat" # If previously run, purge old file
rm -rf "$target/bootstrap.dat.old" # If previously run, purge old file
rm -rf "$target"/*bootstrap.tar.gz*
wget -q -P "$target/" "$release"manifest.txt # Pull down the manifest
sed -i 's/  /:/' "$target/manifest.txt" # Clean it up for easy usage
while IFS= read -r line; do # Loop over each file and check the hashes match
	hash=$(echo "$line" | cut -d ":" -f 1)
	file=$(echo "$line" | cut -d ":" -f 2)
	if [ ! -f "$target/$file" ]; then # Only download the file if it doesn't exist locally
		wget -q -P "$target/" "$release$file"
	fi
	if [ "$(sha256sum "$target/$file" | awk '{print $1}')" = "$hash" ]; then
		echo "LynxCI: $target/$file hash match $hash"
	else # Hash doesn't match
		rm -rf "$file"
		wget -q -P "$target/" "$release$file"
		if [ "$(sha256sum "$target/$file" | awk '{print $1}')" = "$hash" ]; then
			echo "LynxCI: Sanity check - $target/$file hash match $hash"
		else
			echo "LynxCI: Corrupt bootstrap file"
			exit
		fi
	fi
done < "$target/manifest.txt"
echo "Recombining and cleanup..."
cat "$target"/*bootstrap.tar.gz.* | gunzip | (tar xf - -C "$target/")
rm -rf "${target}/manifest.txt"
rm -rf "${target}/home/lynx/bootstrap.dat" # Legacy. Only if it exists.
rmdir "${target}/home/lynx/" # Legacy. Only if it exists.
rmdir "${target}/home/" # Legacy. Only if it exists.
rm -rf "$target"/*bootstrap.tar.gz*
