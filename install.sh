#!/usr/bin/env bash
set -euo pipefail

# --- auto-elevate ---
if [[ $EUID -ne 0 ]]; then
    echo "[graphite-kp] Root required. Asking for password..."
    exec sudo "$0" "$@"
fi

# --- config ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAYOUT="graphite"
MARKER="# graphite-kp-managed"
CONFIG_NIX="/etc/nixos/configuration.nix"

# --- helpers ---
log()  { echo "[graphite-kp] $*"; }
ok()   { log "OK: $*"; }
skip() { log "SKIP: $*"; }
die()  { log "FAIL: $*"; exit 1; }

backup() {
    local f="$1"
    [[ -f "$f" ]] && cp "$f" "$f.bak.$(date +%s)"
}

usage() {
    cat <<EOF
Usage: $0 [--apply | --check]
  --apply   Install layout (default)
  --check   Dry-run, show what would happen
EOF
    exit 1
}

MODE="apply"
case "${1:-}" in
    --check)  MODE="check" ;;
    --apply)  MODE="apply" ;;
    --help|-h) usage ;;
    "") ;;
    *)  usage ;;
esac

# --- detect nixos ---
is_nixos() { [[ -f /etc/NIXOS ]]; }

# ======================
# NixOS install path
# ======================
install_nixos() {
    local src="$SCRIPT_DIR/symbols/$LAYOUT"
    [[ -f "$src" ]] || die "symbols/$LAYOUT not found in $SCRIPT_DIR"

    log "NixOS detected"

    # Step 1: copy symbols file to /etc/nixos/
    local dst="/etc/nixos/$LAYOUT"
    if [[ -f "$dst" ]] && diff -q "$src" "$dst" >/dev/null 2>&1; then
        skip "$dst up to date"
    elif [[ "$MODE" == "check" ]]; then
        log "WOULD: cp $src $dst"
    else
        cp "$src" "$dst"
        ok "Installed $dst"
    fi

    # Step 2: patch configuration.nix
    if [[ ! -f "$CONFIG_NIX" ]]; then
        die "$CONFIG_NIX not found"
    fi

    if grep -qF "extraLayouts.graphite" "$CONFIG_NIX"; then
        skip "configuration.nix already has extraLayouts.graphite"
        return
    fi

    if [[ "$MODE" == "check" ]]; then
        log "WOULD: patch $CONFIG_NIX"
        return
    fi

    backup "$CONFIG_NIX"

    # Check for old layout = "..." and offer to replace
    local old_layout_line=""
    old_layout_line=$(grep -n 'layout\s*=\s*"' "$CONFIG_NIX" | grep -v 'extraLayouts' | head -1 || true)

    if [[ -n "$old_layout_line" ]]; then
        local old_num old_val
        old_num=$(echo "$old_layout_line" | cut -d: -f1)
        old_val=$(echo "$old_layout_line" | sed 's/.*layout\s*=\s*"\([^"]*\)".*/\1/')
        log "Found existing layout: $old_val (line $old_num)"
        read -rp "Replace with $LAYOUT? [Y/n] " answer
        answer="${answer:-Y}"
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            sed -i "${old_num}s/layout\s*=\s*\"[^\"]*\"/layout = \"$LAYOUT\"/" "$CONFIG_NIX"
            ok "Replaced layout with $LAYOUT"
        else
            log "Keeping existing layout"
        fi
    fi

    # Insert the extraLayouts block before the last }
    local block
    block=$(printf '\n  services.xserver.xkb.extraLayouts.%s = {\n    description = "Graphite";\n    languages = [ "eng" ];\n    symbolsFile = ./%s;\n  };\n' "$LAYOUT" "$LAYOUT")

    # Use a temp file for atomic write
    local tmp
    tmp=$(mktemp)
    cp "$CONFIG_NIX" "$tmp"
    # Insert before the last } in the file
    local last_brace_line
    last_brace_line=$(grep -n "^}" "$tmp" | tail -1 | cut -d: -f1)
    if [[ -n "$last_brace_line" ]]; then
        sed -i "${last_brace_line}i\\${block}" "$tmp"
        cp "$tmp" "$CONFIG_NIX"
        ok "Added extraLayouts.graphite to $CONFIG_NIX"
    else
        rm -f "$tmp"
        die "Could not find closing } in $CONFIG_NIX — add the block manually"
    fi
    rm -f "$tmp"

    log "Run: sudo nixos-rebuild switch"
}

# ======================
# Standard Linux install
# ======================
install_standard() {
    local src="$SCRIPT_DIR/symbols/$LAYOUT"
    [[ -f "$src" ]] || die "symbols/$LAYOUT not found in $SCRIPT_DIR"

    # Find xkb symbols directory
    local symbols_dir=""
    for d in /usr/share/X11/xkb/symbols /usr/share/xkeyboard-config-2/symbols; do
        [[ -d "$d" ]] && { symbols_dir="$d"; break; }
    done
    [[ -n "$symbols_dir" ]] || die "No xkb symbols directory found"

    # Find evdev files
    local evdev_xml="" evdev_lst=""
    for d in /usr/share/X11/xkb/rules /usr/share/xkeyboard-config-2/rules; do
        [[ -z "$evdev_xml" && -f "$d/evdev.xml" ]] && evdev_xml="$d/evdev.xml"
        [[ -z "$evdev_lst" && -f "$d/evdev.lst" ]] && evdev_lst="$d/evdev.lst"
    done

    log "Symbols dir: $symbols_dir"
    [[ -n "$evdev_xml" ]] && log "evdev.xml: $evdev_xml" || log "evdev.xml: not found (will skip)"
    [[ -n "$evdev_lst" ]] && log "evdev.lst: $evdev_lst" || log "evdev.lst: not found (will skip)"

    # 1. Install symbols file
    local dst="$symbols_dir/$LAYOUT"
    if [[ -f "$dst" ]] && diff -q "$src" "$dst" >/dev/null 2>&1; then
        skip "$dst up to date"
    elif [[ "$MODE" == "check" ]]; then
        log "WOULD: cp $src $dst"
    else
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        ok "Installed $dst"
    fi

    # 2. evdev.xml
    if [[ -n "$evdev_xml" ]]; then
        if grep -qF "$MARKER" "$evdev_xml" 2>/dev/null; then
            skip "evdev.xml already has $LAYOUT"
        elif [[ "$MODE" == "check" ]]; then
            log "WOULD: insert layout into $evdev_xml"
        elif grep -q "</layoutList>" "$evdev_xml"; then
            backup "$evdev_xml"
            local tmp
            tmp=$(mktemp)
            cat > "$tmp" <<ENTRY
    <!-- $MARKER start -->
    <layout>
      <configItem>
        <name>$LAYOUT</name>
        <shortDescription>$LAYOUT</shortDescription>
        <description>Graphite</description>
        <languageList>
          <iso639Id>eng</iso639Id>
        </languageList>
      </configItem>
      <variantList/>
    </layout>
    <!-- $MARKER end -->
ENTRY
            sed -i "/<\/layoutList>/r $tmp" "$evdev_xml"
            rm -f "$tmp"
            ok "Added layout to $evdev_xml"
        else
            log "WARN: $evdev_xml missing </layoutList>, skipping"
        fi
    fi

    # 3. evdev.lst
    if [[ -n "$evdev_lst" ]]; then
        if grep -qF "$MARKER" "$evdev_lst" 2>/dev/null; then
            skip "evdev.lst already has $LAYOUT"
        elif [[ "$MODE" == "check" ]]; then
            log "WOULD: insert line into $evdev_lst"
        elif grep -q "^! layout" "$evdev_lst"; then
            backup "$evdev_lst"
            local line="  $LAYOUT        Graphite  $MARKER"
            sed -i "/^! layout$/a\\${line}" "$evdev_lst"
            ok "Added layout to $evdev_lst"
        else
            log "WARN: $evdev.lst missing ! layout section, skipping"
        fi
    fi

    log "Done. Activate with: setxkbmap $LAYOUT"
}

# ======================
# main
# ======================
main() {
    log "Mode: $MODE"
    if is_nixos; then
        install_nixos
    else
        install_standard
    fi
}

main
