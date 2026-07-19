# machine-sync setup

Two layers, deliberately separate:

1. **ssh config**: how each machine reaches the other (`ssh mac`, `ssh pc`).
2. **machine-sync config**: what the commands resolve paths against.

## 1. ssh: Mac -> PC (already works)

Windows OpenSSH Server runs on the PC and the Mac's `~/.ssh/id_ed25519` key
is installed in `C:\ProgramData\ssh\administrators_authorized_keys`. Add the
shorthand alias to the Mac's `~/.ssh/config`:

```sshconfig
Host pc
    HostName 10.0.0.186
    User ians0
```

Test: `ssh pc` should drop you into a cmd prompt on the PC.

Note the PC's default sshd shell is cmd.exe. The scripts already account for
that (they wrap remote checks in `powershell -NoProfile -Command`).

## 2. ssh: PC -> Mac (one-time setup)

1. On the Mac: System Settings > General > Sharing > turn on **Remote Login**.
2. On the PC, generate a key if `C:\Users\ians0\.ssh\id_ed25519` does not exist:

   ```powershell
   ssh-keygen -t ed25519
   ```

3. Install the PC's public key on the Mac. Easiest from the Mac, since
   Mac -> PC ssh already works:

   ```bash
   mkdir -p ~/.ssh && chmod 700 ~/.ssh
   ssh pc "type C:/Users/ians0/.ssh/id_ed25519.pub" >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   ```

4. Find the Mac's stable name (survives DHCP lease changes, unlike its
   Wi-Fi IP): run `scutil --get LocalHostName` on the Mac, then use
   `<that-name>.local` below.
5. Add the alias to the PC's `C:\Users\ians0\.ssh\config`:

   ```sshconfig
   Host mac
       HostName <localhostname>.local
       User ian
   ```

Test from the PC: `ssh mac` should drop into a zsh prompt on the Mac.

Both machines are on DHCP. The `.local` mDNS name handles the Mac side; the
PC is wired and has held 10.0.0.186, but a router DHCP reservation for both
machines is the durable fix if either address ever drifts.

## 3. machine-sync config

- PC: `install\install-windows.ps1` seeds `C:\Users\ians0\.machine-sync.ps1`
  and adds the `pull.mac` / `push.mac` / `pull.mac.claude` /
  `push.mac.claude` functions to `$PROFILE`.
- Mac: `install/install-mac.sh` seeds `~/.machine-sync.env` and puts
  `machine-sync/bin` on PATH.

Edit the seeded config on each machine, values are documented inline.
Optional personal ignore list: `~/.machinesync-ignore` (falls back to
`config/.machinesync-ignore.example`).

## Known quirks (bsdtar on Windows, from real transfers)

- NTFS-illegal filename characters are auto-renamed (`::` becomes `__`).
- macOS `Icon\r` files make the extract fail: delete them first, they are
  Finder junk.
- Symlinks arrive as zero-byte files.
- Existing same-name files are overwritten; extra files at the destination
  are never deleted.
- Paths with spaces: fine for tar transfers, avoid for single-file scp to
  the PC (cmd-side quoting is unreliable there).

## End-to-end test checklist

Run after setup, from each machine:

1. `pull.mac --help` (PC) / `pull.pc --help` (Mac): usage prints, no errors.
2. Pull a small directory; confirm it lands at `<to>\<leaf>` and that
   `.venv`-style dirs were filtered.
3. Pull a single file (scp path).
4. Push a directory to a NEW destination: no prompt, lands at `<to>/<leaf>`.
5. Push to the SAME destination again: contents listing plus y/N prompt
   appears; `n` aborts, `y` overwrites.
6. `pull.mac.claude --from <something>`: lands in the claude working dir.
7. `push.mac.claude <that-leaf> --to <somewhere>`: round-trips it back.
8. Pull a directory containing a deliberately latin-1 CSV with `--csv`:
   the report shows `converted (cp1252 -> utf-8)` or similar.
