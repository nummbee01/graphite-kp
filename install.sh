#!/usr/bin/env bash
set -euo pipefail

# Auto-elevate: re-exec with sudo if not root
if [[ $EUID -ne 0 ]]; then
    echo "[graphite-kp] Root required. Asking for password..."
    exec sudo "$0" "$@"
fi

XKB_SYMBOLS="/usr/share/X11/xkb/symbols"
EDEV_XML="/usr/share/X11/xkb/rules/evdev.xml"
EDEV_LST="/usr/share/X11/xkb/rules/evdev.lst"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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

LAYOUT_MARKER="# graphite-kp-managed"
LAYOUT_NAME="graphite"
LAYOUT_DESC="Graphite"
LAYOUT_SHORT="graphite"

log()  { echo "[graphite-kp] $*"; }
ok()   { log "OK: $*"; }
skip() { log "SKIP: $*"; }
fail() { log "FAIL: $*"; exit 1; }

# --- symbols/graphite ---

install_symbols() {
    local src="$SCRIPT_DIR/symbols/graphite"
    local dst="$XKB_SYMBOLS/$LAYOUT_NAME"

    [[ -f "$src" ]] || fail "symbols/graphite not found in $SCRIPT_DIR"

    if [[ -f "$dst" ]] && diff -q "$src" "$dst" >/dev/null 2>&1; then
        skip "$dst already up to date"
        return
    fi

    if [[ "$MODE" == "check" ]]; then
        log "WOULD: cp $src $dst"
        return
    fi

    cp "$src" "$dst"
    ok "Installed $dst"
}

# --- evdev.xml ---

install_evdev_xml() {
    local marker_line="$LAYOUT_MARKER"

    if grep -q "$marker_line" "$EDEV_XML" 2>/dev/null; then
        skip "evdev.xml already has graphite entry"
        return
    fi

    local block
    block=$(cat <<ENTRY
    <!-- $marker_line start -->
    <layout>
      <configItem>
        <name>$LAYOUT_NAME</name>
        <shortDescription>$LAYOUT_SHORT</shortDescription>
        <description>$LAYOUT_DESC</description>
        <languageList>
          <iso639Id>eng</iso639Id>
        </languageList>
      </configItem>
      <variantList/>
    </layout>
    <!-- $marker_line end -->
ENTRY
)

    if [[ "$MODE" == "check" ]]; then
        log "WOULD: insert layout block into $EDEV_XML"
        return
    fi

    # Insert before </layoutList>
    if grep -q "</layoutList>" "$EDEV_XML"; then
        sed -i "/<\/layoutList>/i\\$block" "$EDEV_XML"
        ok "Added layout entry to $EDEV_XML"
    else
        fail "$EDEV_XML missing </layoutList> tag"
    fi
}

# --- evdev.lst ---

install_evdev_lst() {
    local marker_line="$LAYOUT_MARKER"

    if grep -q "$marker_line" "$EDEV_LST" 2>/dev/null; then
        skip "evdev.lst already has graphite entry"
        return
    fi

    if [[ "$MODE" == "check" ]]; then
        log "WOULD: insert layout line into $EDEV_LST"
        return
    fi

    # Find the ! layout section and insert alphabetically
    if grep -q "^! layout" "$EDEV_LST"; then
        # Insert after the first "graphite" or alphabetically between entries
        sed -i "/^! layout$/a\\  $LAYOUT_NAME        $LAYOUT_DESC  $marker_line" "$EDEV_LST"
        ok "Added layout entry to $EDEV_LST"
    else
        fail "$EDEV_LST missing ! layout section"
    fi
}

# --- main ---

main() {
    log "Mode: $MODE"
    install_symbols
    install_evdev_xml
    install_evdev_lst
    log "Done. Set layout with: setxkbmap $LAYOUT_NAME"
}

main
