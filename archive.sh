#!/bin/bash

# ==============================================================================
# Lynx Bootstrap Archive Creation Script
# ==============================================================================
# Purpose: Creates a bootstrap archive for Lynx blockchain synchronization
# Requirements:
#   - Lynx must be installed
#   - Staking should be disabled to avoid Python socket errors
#   - Creates 128MB chunks of the bootstrap file
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

# Get current block height (minus 100 blocks for safety)
echo "Getting current block height..."
getCurrentBlock="$(lynx-cli getblockcount)"
getCurrentBlock=$((getCurrentBlock - 100))
echo "Using block height: $getCurrentBlock (current height minus 100 blocks)"

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
tar -cf - "bootstrap.dat" | gzip | split -b 125M - "$currentDate-bootstrap.tar.gz."
echo "Compression complete"

# Generate manifest with checksums
log_step "Generating manifest"
echo "Creating SHA256 checksums..."
sha256sum "$currentDate"-* > "$currentDate"-manifest.txt
echo "Manifest saved as: $currentDate-manifest.txt"

# Clean up temporary files
log_step "Finalizing"
cleanup

log_step "Process Complete!"
echo "Bootstrap archive creation completed successfully!"
echo "Output files:"
echo "- Bootstrap chunks: $currentDate-bootstrap.tar.gz.*"
echo "- Manifest: $currentDate-manifest.txt"
echo ""
echo "Note: Be sure to keep the manifest file for proper reassembly of the bootstrap archive."