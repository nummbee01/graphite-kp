#!/usr/bin/env bash
set -euo pipefail

# Auto-elevate: re-exec with sudo if not root
if [[ $EUID -ne 0 ]]; then
    echo "[graphite-kp] Root required. Asking for password..."
    exec sudo "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAYOUT_NAME="graphite"
LAYOUT_MARKER="# graphite-kp-managed"

# --- path detection ---

find_file() {
    # $1 = filename, $2+ = search dirs
    for dir in "${@:2}"; do
        [[ -f "$dir/$1" ]] && { echo "$dir/$1"; return 0; }
    done
    return 1
}

XKB_SYMBOLS_DIR=""
for d in /usr/share/X11/xkb/symbols /usr/share/xkeyboard-config-2/symbols /run/current-system/sw/share/X11/xkb/symbols; do
    [[ -d "$d" ]] && { XKB_SYMBOLS_DIR="$d"; break; }
done
[[ -n "$XKB_SYMBOLS_DIR" ]] || { echo "[graphite-kp] FAIL: no xkb symbols directory found"; exit 1; }

EDEV_XML=""
EDEV_LST=""
for d in /usr/share/X11/xkb/rules /usr/share/xkeyboard-config-2/rules /run/current-system/sw/share/X11/xkb/rules; do
    [[ -z "$EDEV_XML" && -f "$d/evdev.xml" ]] && EDEV_XML="$d/evdev.xml"
    [[ -z "$EDEV_LST" && -f "$d/evdev.lst" ]] && EDEV_LST="$d/evdev.lst"
done

# --- arg parsing ---

usage() {
    echo "Usage: $0 [--apply | --check]"
    echo "  --apply   Install graphite layout (default)"
    echo "  --check   Show what would be done without making changes"
    exit 1
}

MODE="apply"
[[ "${1:-}" == "--check" ]] && MODE="check"
[[ "${1:-}" == "--apply" || $# -eq 0 ]] && MODE="apply"
[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && usage

log()  { echo "[graphite-kp] $*"; }
ok()   { log "OK: $*"; }
skip() { log "SKIP: $*"; }

# --- install symbols ---

install_symbols() {
    local src="$SCRIPT_DIR/symbols/$LAYOUT_NAME"
    local dst="$XKB_SYMBOLS_DIR/$LAYOUT_NAME"

    [[ -f "$src" ]] || { log "FAIL: symbols/$LAYOUT_NAME not found in $SCRIPT_DIR"; exit 1; }

    if [[ -f "$dst" ]] && diff -q "$src" "$dst" >/dev/null 2>&1; then
        skip "$dst already up to date"
        return
    fi

    if [[ "$MODE" == "check" ]]; then
        log "WOULD: cp $src $dst"
        return
    fi

    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    ok "Installed $dst"
}

# --- install evdev.xml ---

install_evdev_xml() {
    if [[ -z "$EDEV_XML" ]]; then
        skip "evdev.xml not found, skipping XML registration"
        return
    fi

    if grep -q "$LAYOUT_MARKER" "$EDEV_XML" 2>/dev/null; then
        skip "evdev.xml already has graphite entry"
        return
    fi

    local block
    block=$(cat <<ENTRY
    <!-- $LAYOUT_MARKER start -->
    <layout>
      <configItem>
        <name>$LAYOUT_NAME</name>
        <shortDescription>$LAYOUT_NAME</shortDescription>
        <description>Graphite</description>
        <languageList>
          <iso639Id>eng</iso639Id>
        </languageList>
      </configItem>
      <variantList/>
    </layout>
    <!-- $LAYOUT_MARKER end -->
ENTRY
)

    if [[ "$MODE" == "check" ]]; then
        log "WOULD: insert layout block into $EDEV_XML"
        return
    fi

    if grep -q "</layoutList>" "$EDEV_XML"; then
        sed -i "/<\/layoutList>/i\\$block" "$EDEV_XML"
        ok "Added layout entry to $EDEV_XML"
    else
        log "WARN: $EDEV_XML missing </layoutList> tag, skipping"
    fi
}

# --- install evdev.lst ---

install_evdev_lst() {
    if [[ -z "$EDEV_LST" ]]; then
        skip "evdev.lst not found, skipping list registration"
        return
    fi

    if grep -q "$LAYOUT_MARKER" "$EDEV_LST" 2>/dev/null; then
        skip "evdev.lst already has graphite entry"
        return
    fi

    if [[ "$MODE" == "check" ]]; then
        log "WOULD: insert layout line into $EDEV_LST"
        return
    fi

    if grep -q "^! layout" "$EDEV_LST"; then
        sed -i "/^! layout$/a\\  $LAYOUT_NAME        Graphite  $LAYOUT_MARKER" "$EDEV_LST"
        ok "Added layout entry to $EDEV_LST"
    else
        log "WARN: $EDEV_LST missing ! layout section, skipping"
    fi
}

# --- main ---

main() {
    log "Mode: $MODE"
    log "Symbols dir: $XKB_SYMBOLS_DIR"
    [[ -n "$EDEV_XML" ]] && log "evdev.xml: $EDEV_XML" || log "evdev.xml: not found"
    [[ -n "$EDEV_LST" ]] && log "evdev.lst: $EDEV_LST" || log "evdev.lst: not found"
    install_symbols
    install_evdev_xml
    install_evdev_lst
    log "Done. Set layout with: setxkbmap $LAYOUT_NAME"
}

main
