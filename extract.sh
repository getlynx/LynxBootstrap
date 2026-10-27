#!/bin/bash

# ==============================================================================
# Lynx Bootstrap Archive Extraction Script
# ==============================================================================
# Purpose: Restores bootstrap.dat for fast synchronization of any chain built
#          from the Lynx codebase, from the latest release for that chain
# Usage:   extract.sh [chain] [release-tag]     e.g. extract.sh alioth (default: lynx)
#          wget -O - <url>/extract.sh | bash -s -- <chain>
# Requirements:
#   - The chain's node must be installed, with its data in ~/.<chain>
#     (override with DATA_DIR=/path/to/datadir)
#   - python3, wget, sha256sum and tar must be installed
#   - Downloads the latest bootstrap chunks, verifies and recombines them
#   - Simply restart the node upon script completion to begin the import
# Documentation: https://docs.getlynx.io/lynx-administration/bootstraps
# ==============================================================================

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

set -euo pipefail  # Enable strict error handling

# -----------------------------
# Supported Chains
# -----------------------------
declare -A CHAINS=(
    [alioth]="Alioth"
    [borrelly]="Borrelly"
    [cassiopeia]="Cassiopeia"
    [delphinus]="Delphinus"
    [digitalcoin]="Digitalcoin"
    [enceladus]="Enceladus"
    [fenrir]="Fenrir"
    [galatea]="Galatea"
    [halley]="Halley"
    [indus]="Indus"
    [infiniloop]="InfiniLooP"
    [lynx]="Lynx"
)

# -----------------------------
# Helper Functions
# -----------------------------
cleanup() {
    echo "Removing working directory $WORK_DIR..."
    rm -rf "${WORK_DIR:?}"
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

usage() {
    echo "Usage: $0 [chain] [release-tag]   (default chain: lynx)" >&2
    echo "Supported chains: $(printf '%s\n' "${!CHAINS[@]}" | sort | tr '\n' ' ')" >&2
    exit 1
}

# Download one chunk and check it against its manifest hash, retrying once
fetch_verified() {
    local file="$1" hash="$2"
    if [[ -f "$file" && "$(sha256sum "$file" | awk '{print $1}')" == "$hash" ]]; then
        echo "Already downloaded and verified: $file"
        return
    fi
    for attempt in 1 2; do
        echo "Downloading: $file (attempt $attempt)"
        rm -f "$file"
        wget -q -O "$file" "$DOWNLOAD_BASE/$file" || continue
        if [[ "$(sha256sum "$file" | awk '{print $1}')" == "$hash" ]]; then
            echo "Hash verification successful: $file"
            return
        fi
        echo "Hash mismatch: $file"
    done
    fatal "Bootstrap file corruption detected: $file could not be downloaded with the expected hash"
}

# -----------------------------
# Configuration
# -----------------------------
# Lynx is the default, so the original no-argument usage keeps working
CHAIN_ID="${1:-lynx}"
REQUESTED_TAG="${2:-}"
[[ -n "${CHAINS[$CHAIN_ID]:-}" ]] || { echo "ERROR: Unknown chain '$CHAIN_ID'" >&2; usage; }

readonly CHAIN_ID REQUESTED_TAG
readonly CHAIN_NAME="${CHAINS[$CHAIN_ID]}"
readonly NETWORK="mainnet"
readonly CHAIN_KEY="$CHAIN_ID-$NETWORK"

DATA_DIR="${DATA_DIR:-$HOME/.$CHAIN_ID}"
readonly DATA_DIR="${DATA_DIR%/}"
readonly WORK_DIR="$HOME/$CHAIN_ID-restore"
readonly RELEASE_REPO="getlynx/LynxBootstrap"
readonly GITHUB_API="${GITHUB_API:-https://api.github.com}"

log_step "Restoring $CHAIN_NAME ($CHAIN_KEY) bootstrap"
echo "Data directory: $DATA_DIR"
echo "Working directory: $WORK_DIR"

# -----------------------------
# Validation
# -----------------------------
log_step "Performing System Validation"

echo "Checking required tools..."
for tool in python3 wget sha256sum tar; do
    command -v "$tool" >/dev/null 2>&1 || fatal "$tool is not installed"
done

echo "Verifying access to required directories and files..."
[[ -d "$DATA_DIR" ]] || fatal "$CHAIN_NAME data directory not found: $DATA_DIR (is the $CHAIN_NAME node installed?)"
[[ -w "$DATA_DIR" ]] || fatal "Cannot write to $CHAIN_NAME data directory: $DATA_DIR"
mkdir -p "$WORK_DIR" || fatal "Cannot create working directory: $WORK_DIR"
cd "$WORK_DIR"
rm -f reconstructed.tar.gz reconstructed.tar

# -----------------------------
# Release Lookup
# -----------------------------
log_step "Finding the latest $CHAIN_NAME release"

# Releases created by archive.sh have a title starting with "[<chain>-mainnet]"
# and a hidden bootstrap-metadata block in the description. The published,
# non-prerelease match with the highest block height wins, unless a tag was requested.
lookupStatus=0
releaseInfo="$(python3 -I -c '
import json, os, re, sys, urllib.request

api, repo, key, tag = sys.argv[1:5]
headers = {"Accept": "application/vnd.github+json", "User-Agent": "LynxBootstrap-extract"}
if os.environ.get("GITHUB_TOKEN"):
    headers["Authorization"] = "Bearer " + os.environ["GITHUB_TOKEN"]

best = None
for page in range(1, 11):
    url = "%s/repos/%s/releases?per_page=100&page=%d" % (api, repo, page)
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=30) as r:
        releases = json.load(r)
    if not releases:
        break
    for rel in releases:
        if rel.get("draft") or rel.get("prerelease"):
            continue
        if not (rel.get("name") or "").startswith("[%s]" % key):
            continue
        if tag and rel["tag_name"] != tag:
            continue
        m = re.search(r"<!-- bootstrap-metadata\s*\n(.*?)-->", rel.get("body") or "", re.S)
        if not m:
            continue
        meta = {}
        for line in m.group(1).splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                meta[k.strip()] = v.strip()
        assets = {a["name"]: a["browser_download_url"] for a in rel.get("assets", [])}
        manifest = meta.get("manifest", "")
        if manifest not in assets:
            continue
        values = [rel["tag_name"], assets[manifest].rsplit("/", 1)[0], manifest,
                  meta.get("chunk_prefix", ""), meta.get("chunks", ""),
                  meta.get("height", ""), meta.get("terminal_hash", "")]
        if not all(re.fullmatch(r"[A-Za-z0-9._:/-]+", v) for v in values) or not values[5].isdigit():
            print("Skipping release %s: missing or invalid bootstrap metadata" % rel["tag_name"], file=sys.stderr)
            continue
        if best is None or int(values[5]) > int(best[5]):
            best = values
if best is None:
    sys.exit(3)
print("\n".join(best))
' "$GITHUB_API" "$RELEASE_REPO" "$CHAIN_KEY" "$REQUESTED_TAG")" || lookupStatus=$?

if [[ "$lookupStatus" -eq 0 ]]; then
    { read -r RELEASE_TAG; read -r DOWNLOAD_BASE; read -r MANIFEST; read -r CHUNK_PREFIX
      read -r CHUNK_COUNT; read -r HEIGHT; read -r TERMINAL_HASH; } <<< "$releaseInfo"
elif [[ "$lookupStatus" -eq 3 && "$CHAIN_ID" == "lynx" && -z "$REQUESTED_TAG" ]]; then
    # The Lynx release published before archive.sh added chain metadata
    echo "No chain-tagged Lynx release found, using the legacy v28.0-mainnet release"
    RELEASE_TAG="v28.0-mainnet"
    DOWNLOAD_BASE="https://github.com/$RELEASE_REPO/releases/download/$RELEASE_TAG"
    MANIFEST="2025-05-06-manifest.txt"
    CHUNK_PREFIX="2025-05-06-bootstrap.tar.gz."
    CHUNK_COUNT=""
    HEIGHT=""
    TERMINAL_HASH=""
elif [[ "$lookupStatus" -eq 3 ]]; then
    fatal "No $CHAIN_NAME release found in $RELEASE_REPO${REQUESTED_TAG:+ with tag $REQUESTED_TAG}"
else
    fatal "Could not look up releases from $GITHUB_API (rate limited? set GITHUB_TOKEN to raise the limit)"
fi
readonly RELEASE_TAG DOWNLOAD_BASE MANIFEST CHUNK_PREFIX CHUNK_COUNT HEIGHT TERMINAL_HASH

echo "Release: $RELEASE_TAG"
[[ -z "$HEIGHT" ]] || echo "Block height: $HEIGHT"

# -----------------------------
# Bootstrap Download and Verification
# -----------------------------
log_step "Downloading Manifest File"
echo "Fetching manifest from: $DOWNLOAD_BASE/$MANIFEST"
wget -q -O "$MANIFEST" "$DOWNLOAD_BASE/$MANIFEST" || fatal "Could not download $MANIFEST"

manifestCount=$(grep -c . "$MANIFEST" || true)
[[ "$manifestCount" -gt 0 ]] || fatal "Manifest $MANIFEST is empty"
if [[ -n "$CHUNK_COUNT" && "$manifestCount" -ne "$CHUNK_COUNT" ]]; then
    fatal "Manifest lists $manifestCount chunks, release metadata says $CHUNK_COUNT"
fi

log_step "Processing $manifestCount Bootstrap Chunks"
while read -r hash file; do
    [[ -n "$hash" ]] || continue
    # Only accept plain chunk file names, so the manifest cannot write outside the working directory
    [[ "$file" == "$CHUNK_PREFIX"* && "$file" =~ ^[A-Za-z0-9._-]+$ ]] || fatal "Unexpected file in manifest: $file"
    [[ "$hash" =~ ^[0-9a-f]{64}$ ]] || fatal "Invalid hash in manifest for $file"
    fetch_verified "$file" "$hash"
done < "$MANIFEST"

# -----------------------------
# Bootstrap Extraction
# -----------------------------
log_step "Extracting Bootstrap Data"
echo "Combining chunks..."
#LC_ALL=C cat "$CHUNK_PREFIX"* | gunzip | (tar xf - -C "$DATA_DIR/")
awk '{print $2}' "$MANIFEST" | xargs cat > reconstructed.tar.gz
gunzip -c reconstructed.tar.gz > reconstructed.tar
[[ "$(tar tf reconstructed.tar)" == "bootstrap.dat" ]] || fatal "Archive does not contain exactly one bootstrap.dat"
echo "Extracting bootstrap.dat to the $DATA_DIR/ directory..."
tar xf reconstructed.tar -C "$DATA_DIR/"

# -----------------------------
# Cleanup and Completion
# -----------------------------
log_step "Performing Final Cleanup"
cleanup

log_step "Bootstrap Process Complete!"
echo "Bootstrap extraction completed successfully!"
echo "Output files:"
echo "- Bootstrap: $DATA_DIR/bootstrap.dat (from release $RELEASE_TAG)"
echo ""
echo "Note: Restart the $CHAIN_NAME daemon to begin the import. It renames bootstrap.dat to bootstrap.dat.old when done."
if [[ -n "$HEIGHT" ]]; then
    echo "After the import, block $HEIGHT should have the hash $TERMINAL_HASH"
fi
