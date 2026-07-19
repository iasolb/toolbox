# machine-sync

Peer-to-peer file transfer between the Mac and the PC, installed on both
machines so either side can initiate. Adapted from the work `workbench-sync`
design (tar-over-ssh streaming, ignore filtering, asymmetric safety), rebuilt
for two peers where the remote end is sometimes Windows.

## Commands

On the PC (PowerShell):

```powershell
pull.mac --from <mac path> --to <pc path> [--csv]
push.mac --from <pc path> --to <mac path> [--csv]
pull.mac.claude --from <mac path> [--csv]              # lands in the claude working dir
push.mac.claude <path> --to <mac path> [--csv]         # <path> is relative to the claude working dir
```

On the Mac (zsh/bash):

```bash
pull.pc --from <pc path> --to <mac path> [--csv]
push.pc --from <mac path> --to <pc path> [--csv]
pull.pc.claude --from <pc path> [--csv]                # lands in the claude working dir
push.pc.claude <path> --to <pc path> [--csv]           # <path> is relative to the claude working dir
```

## Path model (hybrid)

Relative paths resolve against configured roots; absolute paths pass through
untouched. Per-machine config lives at `~/.machine-sync.ps1` (PC) or
`~/.machine-sync.env` (Mac), seeded by the installers:

- `PeerRoot` / `PEER_ROOT`: base for relative paths on the other machine
- `LocalRoot` / `LOCAL_ROOT`: base for relative paths on this machine
- `ClaudeDir` / `CLAUDE_DIR`: where the `*.claude` variants land/read

`--to` always names the destination PARENT directory: the transferred item
lands at `<to>/<leaf>`, the same way `cp src dir/` works.

## Behavior

- Directories stream as `tar -czf | ssh | tar -xzf`, filtered against
  `~/.machinesync-ignore` (regenerables excluded, `.git` never excluded, so
  synced repos stay real repos). Single files use scp.
- Pushing onto an existing destination shows its contents and requires an
  explicit y/N confirm. Pulls overwrite silently (matching the reference
  design: pulls land where you pointed them, pushes are the consequential
  direction).
- `--csv` runs every transferred `.csv` through `csv-utf8/ensure_utf8.py`
  after the transfer (locally for pulls, streamed over ssh for pushes).
- Guard-pattern failures everywhere: missing config, missing flags, or a
  missing source path exit early with a message, nothing is guessed.

Setup (ssh aliases both directions, installers, quirks, test checklist):
see `docs/setup.md`.
