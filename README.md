# Lynx Bootstrap Tools

Scripts for creating and restoring blockchain bootstrap archives for the 12 chains built from the [Lynx codebase](https://github.com/getlynx/Lynx). A bootstrap archive lets a new node import the chain from a local `bootstrap.dat` file instead of downloading every block from peers.

- [`archive.sh`](archive.sh) creates a bootstrap archive from a running node and writes paste-ready GitHub release notes.
- [`extract.sh`](extract.sh) finds the latest release for a chain, downloads and verifies it, and puts `bootstrap.dat` in the node's data directory.

For more background, see the [Lynx Bootstrap Documentation](https://docs.getlynx.io/lynx-administration/bootstraps).

## Supported chains

Both scripts take the chain ID as their first argument. Chain settings come from `src/kernel/chainparams.cpp` in the Lynx repo.

| Chain ID | Name | RPC port | Network magic |
|---|---|---|---|
| `alioth` | Alioth | 55802 | `ddf4c1db` |
| `borrelly` | Borrelly | 58401 | `d3ae84cc` |
| `cassiopeia` | Cassiopeia | 53054 | `b282e4c4` |
| `delphinus` | Delphinus | 57691 | `c999f9e6` |
| `digitalcoin` | Digitalcoin | 7998 | `fbc0b6db` |
| `enceladus` | Enceladus | 58611 | `9a87b7c8` |
| `fenrir` | Fenrir | 54826 | `efdacfe1` |
| `galatea` | Galatea | 55786 | `bbe789aa` |
| `halley` | Halley | 53837 | `d085c0fe` |
| `indus` | Indus | 54701 | `edfdadeb` |
| `infiniloop` | InfiniLooP | 9459 | `71332100` |
| `lynx` | Lynx | 8332 | `facfb3dc` |

## Restoring a chain from a bootstrap (`extract.sh`)

```bash
wget -O - https://raw.githubusercontent.com/getlynx/LynxBootstrap/master/extract.sh | bash -s -- <chain>
```

For example, `... | bash -s -- alioth`. When it finishes, restart the node. It imports `bootstrap.dat` on startup, renames it to `bootstrap.dat.old`, and then syncs the remaining blocks from peers.

To restore a specific release instead of the latest one, pass its tag as the second argument:

```bash
wget -O - https://raw.githubusercontent.com/getlynx/LynxBootstrap/master/extract.sh | bash -s -- alioth alioth-mainnet-3273000
```

**Requirements:** the chain's node is installed with its data directory at `~/.<chain>`, and `python3`, `wget`, `sha256sum` and `tar` are available.

### How it works

1. **Finds the release.** It asks the GitHub API for this repo's releases and picks the newest published, non-prerelease release whose title starts with `[<chain>-mainnet]`. It then reads the release's hidden metadata block (see [Release format](#release-format)) to get the manifest name, chunk names, chunk count, block height and terminal block hash.
2. **Downloads and verifies.** It downloads the manifest, then each chunk listed in it, and checks every chunk's SHA256 hash. A chunk with the wrong hash is downloaded once more. If it is still wrong, the script stops. Chunks already downloaded with the right hash are reused, so an interrupted run can be resumed.
3. **Extracts.** It joins the chunks in manifest order, decompresses them, confirms the archive holds only `bootstrap.dat`, and extracts that file into `~/.<chain>/`.
4. **Cleans up.** It removes its working directory, `~/<chain>-restore/`.

For Lynx only, if no chain-tagged release exists yet, it falls back to the older `v28.0-mainnet` release.

### Options

| Variable | Default | Purpose |
|---|---|---|
| `DATA_DIR` | `~/.<chain>` | The node's data directory, if it is not in the default location |
| `GITHUB_TOKEN` | not set | A GitHub token to raise the API rate limit (60 requests per hour without one). No permissions are needed. |

Variables go before `bash` when piping, for example `... | DATA_DIR=/srv/alioth bash -s -- alioth`.

## Creating a bootstrap archive (`archive.sh`)

Run this on a machine with a fully synced node for the chain:

```bash
wget -O - https://raw.githubusercontent.com/getlynx/LynxBootstrap/master/archive.sh | bash -s -- <chain>
```

**Requirements:**

- The chain's node is running, with its data directory at `~/.<chain>` and its config file at `~/.<chain>/<chain>.conf`.
- Staking is disabled, to avoid Python socket errors during the export.
- `curl`, `python3` and `wget` are installed.
- There is enough free disk space for about two copies of the uncompressed `bootstrap.dat` plus two copies of the compressed archive. The script keeps temporary tar and gzip files while it splits the archive.

The output goes in `~/<chain>-bootstrap/`, so several chains can be archived on one machine without overwriting each other:

| File | Purpose |
|---|---|
| `<date>-<chain>-bootstrap.tar.gz.aa`, `.ab`, ... | The archive, split into 125MB chunks |
| `<date>-<chain>-manifest.txt` | SHA256 checksum of every chunk |
| `<date>-<chain>-release-notes.md` | The GitHub release description |

At the end, the script prints a suggested release tag, the release title, and the release description between `BEGIN` and `END` markers.

### Publishing the release

1. Create a new release in this repo using the printed tag and title. Keep the title exactly as printed: `extract.sh` finds releases by the `[<chain>-mainnet]` prefix.
2. Paste the printed description, including the hidden `<!-- bootstrap-metadata ... -->` block at the top. Do not edit that block.
3. Upload every chunk and the manifest as release assets. The release notes file itself is not needed as an asset.
4. Publish the release. Do not mark it as a prerelease, or `extract.sh` will skip it. Marking it as a prerelease is a way to stage a release before making it live.

### How it works

1. **Validates the setup.** It checks that the chain ID is one of the 12 supported chains and that the data directory, config file and blocks directory exist. It then reads the first 4 bytes of `blocks/blk00000.dat` and compares them with the chain's network magic. That catches a wrong data directory or a mistyped chain ID before anything is exported.
2. **Connects to the node.** It reads `rpcuser` and `rpcpassword` from the config file (with or without a `main.` prefix), or falls back to the node's `.cookie` file. All node calls go over JSON-RPC to `127.0.0.1` on the chain's RPC port, so no chain-specific CLI binary is needed.
3. **Chooses the height.** It reads the genesis block hash and current block count from the node and rounds the height down to the nearest thousand.
4. **Exports the blocks.** It downloads the export scripts from [`linearize/`](linearize/) in this repo. `linearize-hashes.py` asks the node for every block hash from genesis to the chosen height. `linearize-data.py` then reads the raw block files and writes those blocks, in order, to `bootstrap.dat`.
5. **Compresses and splits.** It compresses `bootstrap.dat` with tar and gzip, splits it into 125MB chunks, and writes the SHA256 manifest.
6. **Verifies the result.** It takes the height and terminal block hash from the list of exported hashes and checks both against the node. It stops if they don't match, so the release notes always describe what is really in the archive.
7. **Writes the release notes.** The notes include the chain, the block range, the genesis and terminal block hashes, the terminal block time, the node version, sizes, usage instructions and the chunk checksums.

### Changes to the linearize scripts

The scripts in [`linearize/`](linearize/) are copied from [`contrib/linearize`](https://github.com/getlynx/Lynx/tree/master/contrib/linearize) in the Lynx repo, with one change. `linearize-data.py` normally identifies blocks by their SHA256d header hash, but InfiniLooP identifies blocks of version 6 and below by their scrypt hash. The new `scrypt_hash_max_version` setting makes `linearize-data.py` hash those blocks with scrypt. `archive.sh` sets it to 6 for InfiniLooP only. Without it, the export writes no blocks for InfiniLooP and gives no error.

## Release format

Each release created with `archive.sh` has:

- **Tag:** `<chain>-mainnet-<height>`, for example `lynx-mainnet-3273000`.
- **Title:** `[<chain>-mainnet] <Name> Bootstrap Archive - Block Height <height>`.
- **A hidden metadata block** at the top of the description, which `extract.sh` reads:

```
<!-- bootstrap-metadata
chain=lynx
network=mainnet
height=3273000
terminal_hash=<hash of the last block in the archive>
genesis_hash=<hash of block 0>
date=2026-10-27
manifest=2026-10-27-lynx-manifest.txt
chunk_prefix=2026-10-27-lynx-bootstrap.tar.gz.
chunks=27
-->
```

## Manual restore

Without `extract.sh`, put all chunks and the manifest from a release in one directory, then:

```bash
sha256sum -c <date>-<chain>-manifest.txt                          # every line should end in "OK"
cat <date>-<chain>-bootstrap.tar.gz.* | tar -xzf - -C ~/.<chain>/  # writes ~/.<chain>/bootstrap.dat
```

Then restart the node.
