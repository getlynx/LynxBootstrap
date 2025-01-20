# Lynx Bootstrap Tools

Tools for creating and reassembling Lynx blockchain bootstrap archives. These tools help speed up the initial synchronization process for new Lynx nodes.

## Available Tools

### Bootstrap Reassembly (`reassemble.sh`)
Reassembles downloaded bootstrap chunks into a usable bootstrap.dat file:
```bash
wget -O - https://raw.githubusercontent.com/getlynx/LynxBootstrap/master/reassemble.sh | bash
```
[View Reassembly Documentation](reassemble/README.md)


### Archive Creation (`archive.sh`)
Creates a bootstrap archive from a fully synced Lynx node:
```bash
wget -O - https://raw.githubusercontent.com/getlynx/LynxBootstrap/master/archive.sh | bash
```
[View Archive Creation Documentation](archive/README.md)

## Purpose
These tools facilitate the distribution and implementation of Lynx blockchain bootstraps, making it easier to:
- Create standardized bootstrap archives
- Share the blockchain data in manageable chunks
- Verify data integrity with SHA256 checksums
- Reassemble chunks into a working bootstrap.dat file

## Documentation
Full documentation for each tool can be found in their respective directories:
- [Archive Creation Tool](archive/README.md)
- [Reassembly Tool](reassemble/README.md)

## Support
For more information about Lynx bootstraps, visit our [documentation](https://docs.getlynx.io/lynx-administration/bootstraps).