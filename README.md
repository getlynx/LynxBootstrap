![Lynx logo](https://get.clevver.org/9f72f19711a5784e0382d3e2fbfb3660171975b335f789404f149a146c08a05b.png)

# Lynx Bootstrap
For full details on using the bootstrap and snapshot creation scripts, please take a look at the official [documentation](https://docs.getlynx.io/lynx-administration/bootstraps). 

The archive.sh script can be run from any Debian 11 CLI VPS. It will take a long time on a Raspberry Pi 4 (not recommended). When complete, your /home/lynx/ directory will contain a list of tarballs and a manifest file. These can be stored offline for safekeeping. The Lynx Core development team stores a copy of these files to use with the extract.sh script. They are publicly available with this repo in the "Released" section.

When the extract.sh script runs, it will pull down the latest published bootstrap files from this repo. It does not require the files you created when you executed the archives.sh script. LynxCI uses this extract.sh script so it will automatically download, decompress, and assemble the bootstrap files for you.
