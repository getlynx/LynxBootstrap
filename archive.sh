#!/bin/bash

# ==============================================================================
# Lynx Bootstrap Archive Creation Script
# ==============================================================================
# Purpose: Creates a bootstrap archive for any chain built from the Lynx codebase
# Usage:   archive.sh <chain>          e.g. archive.sh alioth
#          wget -O - <url>/archive.sh | bash -s -- <chain>
# Requirements:
#   - The chain's daemon must be running with its data in ~/.<chain>
#     (override with DATA_DIR=/path/to/datadir)
#   - Staking should be disabled to avoid Python socket errors
#   - curl and python3 must be installed
#   - Creates 125MB chunks of the bootstrap file
#   - Be sure to save the manifest and chunk files for reassembly
# Documentation: https://docs.getlynx.io/lynx-administration/bootstraps
# ==============================================================================

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

set -euo pipefail  # Enable strict error handling

# -----------------------------
# Supported Chains
# -----------------------------
# Values from src/kernel/chainparams.cpp in getlynx/Lynx:
# display name, RPC port, network magic (pchMessageStart)
declare -A CHAINS=(
    [alioth]="Alioth 55802 ddf4c1db"
    [borrelly]="Borrelly 58401 d3ae84cc"
    [cassiopeia]="Cassiopeia 53054 b282e4c4"
    [delphinus]="Delphinus 57691 c999f9e6"
    [digitalcoin]="Digitalcoin 7998 fbc0b6db"
    [enceladus]="Enceladus 58611 9a87b7c8"
    [fenrir]="Fenrir 54826 efdacfe1"
    [galatea]="Galatea 55786 bbe789aa"
    [halley]="Halley 53837 d085c0fe"
    [indus]="Indus 54701 edfdadeb"
    [infiniloop]="InfiniLooP 9459 71332100"
    [lynx]="Lynx 8332 facfb3dc"
)

# -----------------------------
# Helper Functions
# -----------------------------
cleanup() {
    echo "Cleaning up temporary files..."
    local patterns=("linearize.cfg" "linearize-data.py" "linearize-hashes.py" "hashlist.txt" "bootstrap.dat" "temp_bootstrap.tar" "temp_bootstrap.tar.gz")
    for pattern in "${patterns[@]}"; do
        rm -rf "${WORK_DIR:?}/$pattern"
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

usage() {
    echo "Usage: $0 <chain>" >&2
    echo "Supported chains: $(printf '%s\n' "${!CHAINS[@]}" | sort | tr '\n' ' ')" >&2
    exit 1
}

# Call the node's JSON-RPC interface. Prints the result, or one field of it.
rpc() {
    local method="$1" params="${2:-}" field="${3:-}"
    local response
    response="$(curl -s --user "$rpcuser:$rpcpassword" -H 'content-type: text/plain;' \
        --data-binary "{\"jsonrpc\":\"1.0\",\"id\":\"archive\",\"method\":\"$method\",\"params\":[$params]}" \
        "http://127.0.0.1:$RPCPORT/")" || fatal "Cannot reach the $CHAIN_NAME node on RPC port $RPCPORT"
    python3 -I -c '
import json, sys
try:
    r = json.loads(sys.argv[1])
except ValueError:
    sys.exit("RPC returned no JSON (wrong credentials?)")
if r.get("error"):
    sys.exit("RPC error: " + str(r["error"].get("message")))
v = r["result"]
print(v[sys.argv[2]] if len(sys.argv) > 2 else v)
' "$response" ${field:+"$field"} || fatal "RPC call '$method' failed"
}

# -----------------------------
# Configuration
# -----------------------------
CHAIN_ID="${1:-}"
[[ -n "$CHAIN_ID" ]] || usage
[[ -n "${CHAINS[$CHAIN_ID]:-}" ]] || { echo "ERROR: Unknown chain '$CHAIN_ID'" >&2; usage; }

read -r CHAIN_NAME RPCPORT NETMAGIC <<< "${CHAINS[$CHAIN_ID]}"
readonly CHAIN_ID CHAIN_NAME RPCPORT NETMAGIC

# InfiniLooP blocks up to version 6 are identified by their scrypt hash rather
# than SHA256d (src/primitives/block.cpp), so linearize-data.py must hash them the same way
SCRYPT_HASH_MAX_VERSION=""
[[ "$CHAIN_ID" != "infiniloop" ]] || SCRYPT_HASH_MAX_VERSION="6"
readonly SCRYPT_HASH_MAX_VERSION

# Chain identity, used in the release title, tag and notes.
# CHAIN_ID and NETWORK form the key ("lynx-mainnet") that extraction tools match on.
readonly NETWORK="mainnet"
readonly CHAIN_KEY="$CHAIN_ID-$NETWORK"

# Set dependent paths
DATA_DIR="${DATA_DIR:-$HOME/.$CHAIN_ID}"
readonly DATA_DIR="${DATA_DIR%/}"
readonly CHAIN_CONF="$DATA_DIR/$CHAIN_ID.conf"
readonly BLOCKS_DIR="$DATA_DIR/blocks"
# Each chain works in its own directory, so archives for several chains can be
# created on one machine without overwriting each other's files
readonly WORK_DIR="$HOME/$CHAIN_ID-bootstrap"
# linearize scripts are kept in this repo, with support for scrypt-hashed blocks
readonly GITHUB_RAW="https://raw.githubusercontent.com/getlynx/LynxBootstrap/master/linearize"

log_step "Creating $CHAIN_NAME ($CHAIN_KEY) bootstrap archive"
echo "Data directory: $DATA_DIR"
echo "Working directory: $WORK_DIR"

# -----------------------------
# Validation
# -----------------------------
log_step "Performing initial validation checks"

echo "Checking required tools..."
for tool in curl python3 wget; do
    command -v "$tool" >/dev/null 2>&1 || fatal "$tool is not installed"
done

# Check if the chain's directory and configuration are accessible
echo "Verifying access to required directories and files..."
[[ -r "$CHAIN_CONF" ]] || fatal "Cannot read $CHAIN_NAME configuration file: $CHAIN_CONF"
[[ -d "$BLOCKS_DIR" ]] || fatal "Cannot access $CHAIN_NAME blocks directory: $BLOCKS_DIR"
mkdir -p "$WORK_DIR" || fatal "Cannot create working directory: $WORK_DIR"
[[ -w "$WORK_DIR" ]] || fatal "Cannot write to working directory: $WORK_DIR"

# Every block file starts with the network magic, so this confirms the data
# directory really holds this chain's blocks
echo "Verifying network magic of block files..."
diskMagic="$(head -c 4 "$BLOCKS_DIR/blk00000.dat" | od -An -tx1 | tr -d ' \n')"
[[ "$diskMagic" == "$NETMAGIC" ]] || fatal "Block files in $BLOCKS_DIR have network magic $diskMagic, expected $NETMAGIC for $CHAIN_NAME"

# All files are created relative to the working directory
cd "$WORK_DIR"

# -----------------------------
# Main Script
# -----------------------------
log_step "Starting bootstrap creation process"

# Clean up any previous files
cleanup

# Extract RPC credentials from config, falling back to the cookie file
echo "Extracting RPC credentials..."
rpcuser="$(sed -ne 's|^[ \t]*\(main\.\)\?rpcuser=[ \t]*||p' "$CHAIN_CONF" | head -n 1)"
rpcpassword="$(sed -ne 's|^[ \t]*\(main\.\)\?rpcpassword=[ \t]*||p' "$CHAIN_CONF" | head -n 1)"
if [[ -z "$rpcuser" || -z "$rpcpassword" ]]; then
    [[ -r "$DATA_DIR/.cookie" ]] || fatal "No rpcuser/rpcpassword in $CHAIN_CONF and no $DATA_DIR/.cookie"
    IFS=: read -r rpcuser rpcpassword < "$DATA_DIR/.cookie"
fi

# Get genesis hash and current block height
echo "Getting genesis block hash..."
genesisHash="$(rpc getblockhash 0)"
echo "Genesis: $genesisHash"
echo "Getting current block height..."
getCurrentBlock="$(rpc getblockcount)"
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
cat > "$WORK_DIR/linearize.cfg" << EOF
rpcuser=$rpcuser
rpcpassword=$rpcpassword
host=127.0.0.1
port=$RPCPORT
max_height=$getCurrentBlock
netmagic=$NETMAGIC
genesis=$genesisHash
input=$BLOCKS_DIR
output_file=$WORK_DIR/bootstrap.dat
hashlist=hashlist.txt
out_of_order_cache_sz = 100000000
rev_hash_bytes = False
file_timestamp = 0
split_timestamp = 0
debug_output = False
EOF
if [[ -n "$SCRYPT_HASH_MAX_VERSION" ]]; then
    echo "scrypt_hash_max_version = $SCRYPT_HASH_MAX_VERSION" >> "$WORK_DIR/linearize.cfg"
fi

# Set proper permissions
echo "Setting file permissions..."
chmod 775 "$WORK_DIR"/linearize*

# Generate hash list
log_step "Generating block hashes"
echo "This may take several minutes..."
"$WORK_DIR/linearize-hashes.py" linearize.cfg > hashlist.txt
chmod 775 "$WORK_DIR/hashlist.txt"
echo "Hash list generation complete"

# Generate bootstrap data
log_step "Creating bootstrap.dat"
echo "This may take a considerable amount of time..."
"$WORK_DIR/linearize-data.py" linearize.cfg
echo "Bootstrap.dat creation complete"

# Create compressed archive split into 125MB chunks
log_step "Creating compressed archives"
currentDate=$(date +%F)
filePrefix="$currentDate-$CHAIN_ID"
chunkPrefix="$filePrefix-bootstrap.tar.gz."
manifest="$filePrefix-manifest.txt"
echo "Compressing and splitting bootstrap.dat into 125MB chunks..."
#tar -cf - "bootstrap.dat" | gzip | split -b 125M - "$chunkPrefix"
tar -cf - "bootstrap.dat" > temp_bootstrap.tar
gzip -c temp_bootstrap.tar > temp_bootstrap.tar.gz
split -b 125M temp_bootstrap.tar.gz "$chunkPrefix"
rm temp_bootstrap.tar temp_bootstrap.tar.gz
echo "Compression complete"

# Generate manifest with checksums
log_step "Generating manifest"
echo "Creating SHA256 checksums..."
sha256sum "$chunkPrefix"* > "$manifest"
echo "Manifest saved as: $manifest"

# Generate GitHub release notes
log_step "Generating release notes"
echo "Collecting release details..."
releaseNotes="$filePrefix-release-notes.md"
# hashlist.txt holds one hash per exported block, starting at genesis (height 0),
# so its last line is the terminal block and its line count is height + 1
archivedHeight=$(( $(wc -l < hashlist.txt) - 1 ))
terminalHash="$(tail -n 1 hashlist.txt)"
echo "Verifying archived block range against the node..."
[[ "$archivedHeight" -eq "$getCurrentBlock" ]] || fatal "Archive ends at height $archivedHeight, expected $getCurrentBlock"
[[ "$terminalHash" == "$(rpc getblockhash "$archivedHeight")" ]] || fatal "Terminal block hash $terminalHash does not match node at height $archivedHeight"
echo "Verified: height $archivedHeight, hash $terminalHash"
formattedHeight=$(echo "$archivedHeight" | sed ':a;s/\B[0-9]\{3\}\>/,&/;ta')
terminalTime="$(rpc getblockheader "\"$terminalHash\"" time)"
terminalTimeUtc="$(date -u -d "@$terminalTime" '+%Y-%m-%d %H:%M:%S UTC')"
nodeVersion="$(rpc getnetworkinfo "" subversion)"
chunkCount=$(ls "$chunkPrefix"* | wc -l)
archiveSize=$(cat "$chunkPrefix"* | wc -c | numfmt --to=iec --suffix=B)
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
genesis_hash=$genesisHash
date=$currentDate
manifest=$manifest
chunk_prefix=$chunkPrefix
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
| **Genesis block hash** | \`$genesisHash\` |
| **Terminal block hash** | \`$terminalHash\` |
| **Terminal block time** | $terminalTimeUtc |
| **Created** | $currentDate with node \`$nodeVersion\` |
| **Format** | gzipped tarball of \`bootstrap.dat\`, split into 125MB chunks |
| **Chunks** | $chunkCount files, $archiveSize total |
| **Uncompressed size** | $datSize (\`bootstrap.dat\`) |
| **Verification** | SHA256 manifest (\`$manifest\`) |

## Required files

Download **all** of these. The archive cannot be reassembled if any chunk is missing.

- Bootstrap chunks: \`$chunkPrefix*\` ($chunkCount files)
- Manifest: \`$manifest\`

## Usage

**Automated:** run [\`extract.sh\`](https://github.com/getlynx/LynxBootstrap/blob/master/extract.sh). It finds the latest $CHAIN_NAME release, downloads and verifies every chunk, and extracts \`bootstrap.dat\` into \`~/.$CHAIN_ID/\`:

\`\`\`bash
wget -O - https://raw.githubusercontent.com/getlynx/LynxBootstrap/master/extract.sh | bash -s -- $CHAIN_ID
\`\`\`

**Manual:** put all chunks and the manifest in one directory, then:

\`\`\`bash
# 1. Verify every chunk (each line should end in "OK")
sha256sum -c $manifest

# 2. Reassemble and extract bootstrap.dat into the $CHAIN_NAME data directory
cat $chunkPrefix* | tar -xzf - -C ~/.$CHAIN_ID/

# 3. Restart $CHAIN_NAME. It imports bootstrap.dat on startup, then syncs the remaining blocks from peers.
\`\`\`

After the import finishes, check that block $archivedHeight on your node has the hash \`$terminalHash\`.

## Documentation

For detailed instructions and usage guidelines, see the [Lynx Bootstrap Documentation](https://docs.getlynx.io/lynx-administration/bootstraps).

<details>
<summary>Chunk checksums (SHA256)</summary>

\`\`\`
EOF
cat "$manifest"
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
echo "Output files (in $WORK_DIR):"
echo "- Bootstrap chunks: $chunkPrefix*"
echo "- Manifest: $manifest"
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
