#!/usr/bin/env bash
# Shared helpers for the machine-sync Mac-side commands. The peer is a
# Windows box whose sshd default shell is cmd.exe, so remote probes go
# through "powershell -NoProfile -Command" and remote paths use forward
# slashes (the form bsdtar's -C accepts on Windows).

MS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MS_TOOLBOX_ROOT="$(cd "$MS_SCRIPT_DIR/../.." && pwd)"

die() {
    echo "$1" >&2
    exit 1
}

load_config() {
    local config_path="${MACHINE_SYNC_CONFIG:-$HOME/.machine-sync.env}"
    if [ ! -f "$config_path" ]; then
        die "Missing config: $config_path. Copy machine-sync/config/machine-sync.env.example there and edit it."
    fi
    # shellcheck source=/dev/null
    . "$config_path"
    : "${PEER_HOST:?PEER_HOST must be set in $config_path}"
    : "${PEER_ROOT:?PEER_ROOT must be set in $config_path}"
    : "${LOCAL_ROOT:?LOCAL_ROOT must be set in $config_path}"
    : "${CLAUDE_DIR:?CLAUDE_DIR must be set in $config_path}"
    PEER_ROOT="${PEER_ROOT%/}"
    LOCAL_ROOT="${LOCAL_ROOT%/}"
    CLAUDE_DIR="${CLAUDE_DIR%/}"
}

ignore_path() {
    if [ -n "${MACHINE_SYNC_IGNORE:-}" ]; then
        echo "$MACHINE_SYNC_IGNORE"
        return
    fi
    if [ -f "$HOME/.machinesync-ignore" ]; then
        echo "$HOME/.machinesync-ignore"
        return
    fi
    echo "$MS_SCRIPT_DIR/../config/.machinesync-ignore.example"
}

# Fills EXCLUDE_PATTERNS with the ignore file's patterns, comments stripped.
load_exclude_patterns() {
    EXCLUDE_PATTERNS=()
    local path line
    path="$(ignore_path)"
    [ -f "$path" ] || return 0
    while IFS= read -r line; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [ -n "$line" ] && EXCLUDE_PATTERNS+=("$line")
    done < "$path"
    return 0
}

# Resolves a peer (PC) path: drive-letter paths pass through (backslashes
# normalized), everything else joins onto PEER_ROOT.
resolve_peer_path() {
    local value="$1"
    value="${value//\\//}"
    value="${value%/}"
    case "$value" in
        [A-Za-z]:*) echo "$value" ;;
        .|"") echo "$PEER_ROOT" ;;
        *) echo "$PEER_ROOT/$value" ;;
    esac
}

resolve_local_path() {
    local base="$1" value="$2"
    case "$value" in
        /*) echo "${value%/}" ;;
        "~/"*) echo "$HOME/${value#\~/}" ;;
        .|"") echo "$base" ;;
        *) echo "$base/${value%/}" ;;
    esac
}

peer_is_dir() {
    ssh "$PEER_HOST" "powershell -NoProfile -Command \"exit [int](-not (Test-Path -LiteralPath '$1' -PathType Container))\"" >/dev/null 2>&1
}

peer_exists() {
    ssh "$PEER_HOST" "powershell -NoProfile -Command \"exit [int](-not (Test-Path -LiteralPath '$1'))\"" >/dev/null 2>&1
}

peer_listing() {
    ssh "$PEER_HOST" "powershell -NoProfile -Command \"Get-ChildItem -Force -LiteralPath '$1'\""
}

peer_mkdir() {
    ssh "$PEER_HOST" "powershell -NoProfile -Command \"[void](New-Item -ItemType Directory -Force -Path '$1')\"" >/dev/null
}

confirm_push_destination() {
    local target="$1" reply
    peer_exists "$target" || return 0
    echo "Destination already exists: $PEER_HOST:$target"
    echo 'Current contents there:'
    peer_listing "$target"
    echo ''
    echo 'This push will overwrite any file with a matching name.'
    echo 'Anything already there that is NOT part of this push is left as-is (not deleted).'
    echo ''
    printf 'Continue with push? [y/N] '
    read -r reply
    case "$reply" in
        y|Y|yes|Yes|YES) ;;
        *) die 'Aborted, nothing was pushed.' ;;
    esac
}

# tar_pull <remote_parent> <remote_leaf> <local_dest>
# The remote shell is cmd.exe: single quotes are literal there, so remote
# exclude patterns must be double-quoted.
tar_pull() {
    local parent="$1" leaf="$2" dest="$3" flags="" p
    mkdir -p "$dest"
    if [ "${#EXCLUDE_PATTERNS[@]}" -gt 0 ]; then
        for p in "${EXCLUDE_PATTERNS[@]}"; do
            flags="$flags --exclude=\"$p\""
        done
    fi
    ssh "$PEER_HOST" "tar -czf -$flags -C \"$parent\" \"$leaf\"" | tar -xzf - -C "$dest"
}

# tar_push <local_parent> <local_leaf> <remote_dest>
tar_push() {
    local parent="$1" leaf="$2" dest="$3" p
    local args=(-czf -)
    if [ "${#EXCLUDE_PATTERNS[@]}" -gt 0 ]; then
        for p in "${EXCLUDE_PATTERNS[@]}"; do
            args+=(--exclude="$p")
        done
    fi
    args+=(-C "$parent" "$leaf")
    # COPYFILE_DISABLE keeps AppleDouble ._* junk out of the stream
    COPYFILE_DISABLE=1 tar "${args[@]}" | ssh "$PEER_HOST" "tar -xzf - -C \"$dest\""
}

csv_ensure_local() {
    local target="$1" script="$MS_TOOLBOX_ROOT/csv-utf8/ensure_utf8.py"
    if [ ! -f "$script" ]; then
        echo "csv-utf8: missing $script, skipping conversion" >&2
        return 0
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        echo 'csv-utf8: no python3 on this machine, skipping conversion' >&2
        return 0
    fi
    python3 "$script" "$target"
}

csv_ensure_on_peer() {
    local target="$1" script="$MS_TOOLBOX_ROOT/csv-utf8/ensure_utf8.py"
    if [ ! -f "$script" ]; then
        echo "csv-utf8: missing $script, skipping conversion" >&2
        return 0
    fi
    # the Store stub on a bare Windows box fails this probe, a real python passes
    if ! ssh "$PEER_HOST" "python --version" >/dev/null 2>&1; then
        echo "csv-utf8: no working python on $PEER_HOST, skipping conversion" >&2
        return 0
    fi
    # stream the script over ssh so the peer needs python but not this repo
    ssh "$PEER_HOST" "python - \"$target\"" < "$script"
}

# machine_sync_pull <command_name> <from_value> <dest_dir> <csv_flag>
machine_sync_pull() {
    local cmd="$1" from="$2" dest="$3" csv="$4"
    local remote_full parent leaf landing
    remote_full="$(resolve_peer_path "$from")"
    parent="$(dirname "$remote_full")"
    leaf="$(basename "$remote_full")"
    mkdir -p "$dest"
    landing="$dest/$leaf"
    echo "$cmd $from -> $landing"
    load_exclude_patterns
    if peer_is_dir "$remote_full"; then
        tar_pull "$parent" "$leaf" "$dest"
    else
        scp "$PEER_HOST:$remote_full" "$dest/"
    fi
    if [ "$csv" = "1" ]; then
        csv_ensure_local "$landing"
    fi
}

# machine_sync_push <command_name> <local_base> <from_value> <to_value> <csv_flag>
machine_sync_push() {
    local cmd="$1" base="$2" from="$3" to="$4" csv="$5"
    local local_full remote_dest leaf target
    local_full="$(resolve_local_path "$base" "$from")"
    [ -e "$local_full" ] || die "Missing local path: $local_full"
    remote_dest="$(resolve_peer_path "$to")"
    leaf="$(basename "$local_full")"
    target="$remote_dest/$leaf"
    confirm_push_destination "$target"
    peer_mkdir "$remote_dest"
    load_exclude_patterns
    if [ -d "$local_full" ]; then
        echo "$cmd $from -> $PEER_HOST:$target"
        tar_push "$(dirname "$local_full")" "$leaf" "$remote_dest"
    else
        echo "$cmd $from -> $PEER_HOST:$remote_dest/"
        scp "$local_full" "$PEER_HOST:$remote_dest/"
    fi
    if [ "$csv" = "1" ]; then
        csv_ensure_on_peer "$target"
    fi
}
