#!/bin/bash

# ==============================================================================
# Lynx Bootstrap Archive Extraction Script
# ==============================================================================
# Purpose: Creates a bootstrap.dat file for fast Lynx blockchain synchronization
# Requirements:
#   - Lynx must be installed
#   - Staking should be disabled to avoid Python socket errors
#   - Downloads latest bootstrap chunks, verifies and recombines
#   - Simply restart Lynx upon script completion to begin reindex process
# Documentation: https://docs.getlynx.io/lynx-administration/bootstraps
# ==============================================================================

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

set -euo pipefail  # Enable strict error handling

# -----------------------------
# Helper Functions
# -----------------------------
cleanup() {
    echo "Cleaning up temporary files..."
    local patterns=("$RELEASE_DATE-manifest.txt" "bootstrap.dat" "bootstrap.dat.old")
    for pattern in "${patterns[@]}"; do
		echo "Removing legacy file ${LYNX_HOME:?}/$pattern"
        rm -rf "${LYNX_HOME:?}/$pattern"
    done
	echo "Removing legacy file $LYNX_HOME/*bootstrap.tar.gz.*"
	rm -rf "$LYNX_HOME"/*bootstrap.tar.gz.*
}

fatal() {
    echo "ERROR: $1" >&2
    exit 1
}

log_step() {
    echo "======================================"
    echo "🔶 $1"
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

# Set dependent paths and configuration
readonly LYNX_CONF="$LYNX_HOME/.lynx/lynx.conf"
readonly BLOCKS_DIR="$LYNX_HOME/.lynx/blocks"
readonly RELEASE_URL="https://github.com/getlynx/LynxBootstrap/releases/download"
readonly RELEASE_TAG="v25.0"
readonly RELEASE_DATE="2025-02-03"

log_step "Initializing Bootstrap Process"
echo "Lynx Home Directory: $LYNX_HOME"

# Change to Lynx home directory for consistent operations
cd "$LYNX_HOME"

# -----------------------------
# Validation
# -----------------------------
log_step "Performing System Validation"

# Check if Lynx directory and configuration are accessible
echo "Verifying access to required directories and files..."
[[ -w "$LYNX_HOME" ]] || fatal "Cannot write to Lynx home directory: $LYNX_HOME"

# -----------------------------
# Bootstrap Download and Verification
# -----------------------------
log_step "Starting Bootstrap Download Process"

# Clean up any previous bootstrap files
cleanup

# Download manifest file
log_step "Downloading Manifest File"
echo "Fetching manifest from: $RELEASE_URL/$RELEASE_TAG-mainnet/$RELEASE_DATE-manifest.txt"
wget -q -P "$LYNX_HOME/" "$RELEASE_URL/$RELEASE_TAG-mainnet/$RELEASE_DATE-manifest.txt"

# Process manifest and download chunks
log_step "Processing Bootstrap Chunks"
sed -i 's/  /:/' "$LYNX_HOME/$RELEASE_DATE-manifest.txt"

while IFS= read -r line; do
    hash=$(echo "$line" | cut -d ":" -f 1)
    file=$(echo "$line" | cut -d ":" -f 2)

    log_step "Processing: $file"

    # Download file if not present
    if [ ! -f "$LYNX_HOME/$file" ]; then
        echo "Downloading: $file"
        wget -q -P "$LYNX_HOME/" "$RELEASE_URL/$RELEASE_TAG-mainnet/$file"
    fi

    # Verify hash
    if [ "$(sha256sum "$LYNX_HOME/$file" | awk '{print $1}')" = "$hash" ]; then
        echo "Hash verification successful: $file"
    else
        echo "Hash mismatch - attempting redownload"
        rm -rf "$file"
        wget -q -P "$LYNX_HOME/" "$RELEASE_URL/$RELEASE_TAG-mainnet/$file"
        if [ "$(sha256sum "$LYNX_HOME/$file" | awk '{print $1}')" = "$hash" ]; then
            echo "Redownload successful - hash verified"
        else
            fatal "Bootstrap file corruption detected"
        fi
    fi
done < "$LYNX_HOME/$RELEASE_DATE-manifest.txt"

# -----------------------------
# Bootstrap Extraction
# -----------------------------
log_step "Extracting Bootstrap Data"
echo "Combining chunks and extracting to the $LYNX_HOME/.lynx/ directory..."
LC_ALL=C cat "$LYNX_HOME"/*bootstrap.tar.gz.* | gunzip | (tar xf - -C "$LYNX_HOME/.lynx/")

# -----------------------------
# Cleanup and Completion
# -----------------------------
log_step "Performing Final Cleanup"
#cleanup

log_step "Bootstrap Process Complete!"
echo "Bootstrap extraction completed successfully!"
echo "Output files:"
echo "- Bootstrap: $LYNX_HOME/bootstrap.dat"
echo ""
echo "Note: Restart the Lynx daemon to begin the reindexing process."