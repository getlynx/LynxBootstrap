#!/bin/bash

# ==============================================================================
# Lynx Bootstrap Archive Creation Script
# ==============================================================================
# Purpose: Creates a bootstrap archive for Lynx blockchain synchronization
# Requirements:
#   - Lynx must be installed
#   - Staking should be disabled to avoid Python socket errors
#   - Creates 125MB chunks of the bootstrap file
#   - Be sure to save the manifest.txt and chunk files for reassembly
# Documentation: https://docs.getlynx.io/lynx-administration/bootstraps
# ==============================================================================

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

set -euo pipefail  # Enable strict error handling

# -----------------------------
# Helper Functions
# -----------------------------
cleanup() {
    echo "Cleaning up temporary files..."
    local patterns=("linearize.cfg" "linearize-data.py" "linearize-hashes.py" "hashlist.txt" "bootstrap.dat" "manifest.txt")
    for pattern in "${patterns[@]}"; do
        rm -rf "${LYNX_HOME:?}/$pattern"
    done
}

fatal() {
    echo "ERROR: $1" >&2
    exit 1
}

log_step() {
    echo "======================================"
    echo "🔷 $1"
    echo "======================================"
}

# -----------------------------
# Configuration
# -----------------------------

# Get LYNX_HOME path
LYNX_DIR=$(find ~/ -name ".lynx" -type d) || fatal "Could not locate .lynx directory"
LYNX_HOME=$(dirname "$LYNX_DIR")

# Remove trailing slash if present
LYNX_HOME="${LYNX_HOME%/}"

# Set dependent paths
readonly LYNX_HOME
readonly LYNX_CONF="$LYNX_HOME/.lynx/lynx.conf"
readonly BLOCKS_DIR="$LYNX_HOME/.lynx/blocks"
readonly GITHUB_RAW="https://raw.githubusercontent.com/getlynx/Lynx/master/contrib/linearize"
readonly RPCPORT="8332"

# Chain identity, used in the release title, tag and notes.
# CHAIN_ID and NETWORK form the key ("lynx-mainnet") that extraction tools match on.
readonly CHAIN_NAME="Lynx"
readonly CHAIN_ID="lynx"
readonly NETWORK="mainnet"
readonly CHAIN_KEY="$CHAIN_ID-$NETWORK"

log_step "Absolute path to ~/.lynx directory"
echo "Path: $LYNX_HOME"

# To prevent extra / with the tar command
cd "$LYNX_HOME"

# -----------------------------
# Validation
# -----------------------------
log_step "Performing initial validation checks"

# Check if Lynx CLI is available and executable
echo "Checking Lynx CLI availability..."
if ! lynx-cli -version >/dev/null 2>&1; then
    fatal "lynx-cli is not available or not executable"
fi

# Check if Lynx directory and configuration are accessible
echo "Verifying access to required directories and files..."
[[ -r "$LYNX_CONF" ]] || fatal "Cannot read Lynx configuration file: $LYNX_CONF"
[[ -d "$BLOCKS_DIR" ]] || fatal "Cannot access Lynx blocks directory: $BLOCKS_DIR"
[[ -w "$LYNX_HOME" ]] || fatal "Cannot write to Lynx home directory: $LYNX_HOME"

# -----------------------------
# Main Script
# -----------------------------
log_step "Starting bootstrap creation process"

# Clean up any previous files
cleanup

# Extract RPC credentials from config
echo "Extracting RPC credentials..."
rpcuser="$(/bin/sed -ne 's|[\t]*main.rpcuser=[\t]*||p' "$LYNX_CONF")"
rpcpassword="$(/bin/sed -ne 's|[\t]*main.rpcpassword=[\t]*||p' "$LYNX_CONF")"

# Get current block height
echo "Getting current block height..."
getCurrentBlock="$(lynx-cli getblockcount)"
echo "Round down to the nearest thousand."
# Integer division by 1000 drops the last 3 digits
getCurrentBlock=$(( getCurrentBlock / 1000 * 1000 ))
echo "Using block height: $getCurrentBlock"

# Download required Python scripts
log_step "Downloading required scripts"
echo "Fetching linearize scripts from GitHub..."
wget -q "$GITHUB_RAW/linearize-data.py"
wget -q "$GITHUB_RAW/linearize-hashes.py"

# Create linearize configuration
log_step "Creating configuration file"
echo "Generating linearize.cfg..."
cat > "$LYNX_HOME/linearize.cfg" << EOF
rpcuser=$rpcuser
rpcpassword=$rpcpassword
host=127.0.0.1
port=$RPCPORT
max_height=$getCurrentBlock
netmagic=facfb3dc
genesis=e7dd146b0867a671abf67d7292e2f62b1ae8854f58ca367547297f0b7f115498
input=$BLOCKS_DIR
output_file=$LYNX_HOME/bootstrap.dat
hashlist=hashlist.txt
out_of_order_cache_sz = 100000000
rev_hash_bytes = False
file_timestamp = 0
split_timestamp = 0
debug_output = False
EOF

# Set proper permissions
echo "Setting file permissions..."
chmod 775 "$LYNX_HOME"/linearize*

# Generate hash list
log_step "Generating block hashes"
echo "This may take several minutes..."
"$LYNX_HOME/linearize-hashes.py" linearize.cfg > hashlist.txt
chmod 775 "$LYNX_HOME/hashlist.txt"
echo "Hash list generation complete"

# Generate bootstrap data
log_step "Creating bootstrap.dat"
echo "This may take a considerable amount of time..."
"$LYNX_HOME/linearize-data.py" linearize.cfg
echo "Bootstrap.dat creation complete"

# Create compressed archive split into 125MB chunks
log_step "Creating compressed archives"
currentDate=$(date +%F)
echo "Compressing and splitting bootstrap.dat into 125MB chunks..."
#tar -cf - "bootstrap.dat" | gzip | split -b 125M - "$currentDate-bootstrap.tar.gz."
tar -cf - "bootstrap.dat" > temp_bootstrap.tar
gzip -c temp_bootstrap.tar > temp_bootstrap.tar.gz
split -b 125M temp_bootstrap.tar.gz "$currentDate-bootstrap.tar.gz."
rm temp_bootstrap.tar temp_bootstrap.tar.gz
echo "Compression complete"

# Generate manifest with checksums
log_step "Generating manifest"
echo "Creating SHA256 checksums..."
sha256sum "$currentDate"-bootstrap.tar.gz.* > "$currentDate"-manifest.txt
echo "Manifest saved as: $currentDate-manifest.txt"

# Generate GitHub release notes
log_step "Generating release notes"
echo "Collecting release details..."
releaseNotes="$currentDate-release-notes.md"
# hashlist.txt holds one hash per exported block, starting at genesis (height 0),
# so its last line is the terminal block and its line count is height + 1
archivedHeight=$(( $(wc -l < hashlist.txt) - 1 ))
terminalHash="$(tail -n 1 hashlist.txt)"
echo "Verifying archived block range against the node..."
[[ "$archivedHeight" -eq "$getCurrentBlock" ]] || fatal "Archive ends at height $archivedHeight, expected $getCurrentBlock"
[[ "$terminalHash" == "$(lynx-cli getblockhash "$archivedHeight")" ]] || fatal "Terminal block hash $terminalHash does not match node at height $archivedHeight"
echo "Verified: height $archivedHeight, hash $terminalHash"
formattedHeight=$(echo "$archivedHeight" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta')
terminalTime="$(lynx-cli getblockheader "$terminalHash" | grep '"time"' | tr -dc '0-9')"
terminalTimeUtc="$(date -u -d "@$terminalTime" '+%Y-%m-%d %H:%M:%S UTC')"
lynxVersion="$(lynx-cli -version | head -n 1)"
chunkCount=$(ls "$currentDate"-bootstrap.tar.gz.* | wc -l)
archiveSize=$(cat "$currentDate"-bootstrap.tar.gz.* | wc -c | numfmt --to=iec --suffix=B)
datSize=$(stat -c %s bootstrap.dat | numfmt --to=iec --suffix=B)
releaseTitle="[$CHAIN_KEY] $CHAIN_NAME Bootstrap Archive - Block Height $formattedHeight"
releaseTag="$CHAIN_KEY-$archivedHeight"

{
cat << EOF
<!-- bootstrap-metadata
chain=$CHAIN_ID
network=$NETWORK
height=$archivedHeight
terminal_hash=$terminalHash
date=$currentDate
manifest=$currentDate-manifest.txt
chunk_prefix=$currentDate-bootstrap.tar.gz.
chunks=$chunkCount
-->
> **Chain: $CHAIN_NAME ($NETWORK)**. This archive only works with $CHAIN_NAME $NETWORK nodes. Do not load it into a node for any other chain.

This release contains the $CHAIN_NAME $NETWORK blockchain as a bootstrap archive, split into $chunkCount chunks. Loading it lets a new node import the chain from a local file instead of downloading every block from peers.

## Details

| | |
|---|---|
| **Chain** | $CHAIN_NAME (\`$CHAIN_ID\`) |
| **Network** | $NETWORK |
| **Height range** | Block 0 (genesis) through $formattedHeight |
| **Terminal block hash** | \`$terminalHash\` |
| **Terminal block time** | $terminalTimeUtc |
| **Created** | $currentDate with $lynxVersion |
| **Format** | gzipped tarball of \`bootstrap.dat\`, split into 125MB chunks |
| **Chunks** | $chunkCount files, $archiveSize total |
| **Uncompressed size** | $datSize (\`bootstrap.dat\`) |
| **Verification** | SHA256 manifest (\`$currentDate-manifest.txt\`) |

## Required files

Download **all** of these. The archive cannot be reassembled if any chunk is missing.

- Bootstrap chunks: \`$currentDate-bootstrap.tar.gz.*\` ($chunkCount files)
- Manifest: \`$currentDate-manifest.txt\`

## Usage

**Automated:** run [\`extract.sh\`](https://github.com/getlynx/LynxBootstrap/blob/master/extract.sh) from this repository. It downloads, verifies and extracts the archive into \`~/.lynx/\`.

**Manual:** put all chunks and the manifest in one directory, then:

\`\`\`bash
# 1. Verify every chunk (each line should end in "OK")
sha256sum -c $currentDate-manifest.txt

# 2. Reassemble and extract bootstrap.dat into the Lynx data directory
cat $currentDate-bootstrap.tar.gz.* | tar -xzf - -C ~/.lynx/

# 3. Restart Lynx. It imports bootstrap.dat on startup, then syncs the remaining blocks from peers.
\`\`\`

After the import finishes, check that \`lynx-cli getblockhash $archivedHeight\` returns \`$terminalHash\`.

## Documentation

For detailed instructions and usage guidelines, see the [Lynx Bootstrap Documentation](https://docs.getlynx.io/lynx-administration/bootstraps).

<details>
<summary>Chunk checksums (SHA256)</summary>

\`\`\`
EOF
cat "$currentDate"-manifest.txt
cat << EOF
\`\`\`

</details>
EOF
} > "$releaseNotes"
echo "Release notes saved as: $releaseNotes"

# Clean up temporary files
log_step "Finalizing"
cleanup

log_step "Process Complete!"
echo "Bootstrap archive creation completed successfully!"
echo "Output files:"
echo "- Bootstrap chunks: $currentDate-bootstrap.tar.gz.*"
echo "- Manifest: $currentDate-manifest.txt"
echo "- Release notes: $releaseNotes"
echo ""
echo "Note: Be sure to keep the manifest file for proper reassembly of the bootstrap archive."

log_step "GitHub Release"
echo "Tag (suggested):"
echo ""
echo "$releaseTag"
echo ""
echo "Title (copy into the release title field):"
echo ""
echo "$releaseTitle"
echo ""
echo "Description (copy everything between the markers into the release description):"
echo "----------------------------- BEGIN -----------------------------"
cat "$releaseNotes"
echo "------------------------------ END ------------------------------"
echo ""
echo "Then set RELEASE_DATE=\"$currentDate\" (and RELEASE_TAG, if it changed) in extract.sh."