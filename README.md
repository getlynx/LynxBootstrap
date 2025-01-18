# Lynx Bootstrap Archive Creation Script

This script automates the process of creating a bootstrap archive for the Lynx blockchain. It generates a bootstrap.dat file from your local blockchain data and splits it into manageable chunks for easier distribution.

## Overview

The script performs the following operations:
1. Locates your Lynx installation directory
2. Validates the environment and required tools
3. Creates a bootstrap.dat file from your local blockchain
4. Compresses and splits the bootstrap file into 125MB chunks
5. Generates a manifest file with SHA256 checksums for verification

## Requirements

- Lynx Core must be installed and fully synced
- Python (for the linearize scripts)
- Sufficient disk space for the bootstrap file creation
- Staking should be disabled to avoid Python socket errors
- Write permissions in the Lynx home directory

## Installation

Download and execute the script:
```bash
wget -O - https://raw.githubusercontent.com/getlynx/LynxBootstrap/master/archive.sh | bash
```

## Output Files

The script generates the following files:
- `YYYY-MM-DD-bootstrap.tar.gz.*` - Compressed bootstrap chunks
- `YYYY-MM-DD-manifest.txt` - SHA256 checksums for verification

## Important Notes

- Keep both the chunk files and manifest.txt for proper reassembly
- The script expects the .lynx directory to be in its default location
- The process may take considerable time depending on blockchain size
- Ensure sufficient disk space is available before running

## Technical Details

- Chunks are created at 125MB size for easier transfer
- The script uses Python's linearize tools from the Lynx Core repository
- Block height is set to (current - 100) for safety
- RPC credentials are automatically extracted from lynx.conf

## Common Issues

1. **Permission Denied**: Ensure you have write access to the Lynx directory
2. **lynx-cli not found**: Make sure Lynx Core is properly installed and running
3. **Space Issues**: Ensure sufficient disk space for bootstrap creation

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Support

If you encounter any issues or need assistance, please:
1. Check the Common Issues section above
2. Create an issue in the GitHub repository
3. Visit the [Lynx Documentation](https://docs.getlynx.io) for more information

## Acknowledgments

- Lynx Core Development Team
- Bitcoin Core's linearize scripts (which were adapted for Lynx)