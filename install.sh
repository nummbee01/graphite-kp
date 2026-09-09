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
CONFIG_NIX="/etc/nixos/configuration.nix"
NIXOS_XKB="/etc/nixos/xkb"
SYMBOLS_CPIO="$SCRIPT_DIR/symbols/graphite"

log()  { echo "[graphite-kp] $*"; }
ok()   { log "OK: $*"; }
skip() { log "SKIP: $*"; }
fail() { log "FAIL: $*"; exit 1; }

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

# --- detect NixOS ---

is_nixos() {
    [[ -f /etc/NIXOS ]] || command -v nixos-rebuild &>/dev/null
}

# --- NixOS install ---

install_nixos() {
    local src="$SCRIPT_DIR/symbols/$LAYOUT_NAME"
    [[ -f "$src" ]] || fail "symbols/$LAYOUT_NAME not found in $SCRIPT_DIR"

    log "Detected NixOS"

    # 1. Copy symbols to /etc/nixos/graphite (next to configuration.nix)
    local symbols_dst="/etc/nixos/graphite"
    if [[ -f "$symbols_dst" ]] && diff -q "$src" "$symbols_dst" >/dev/null 2>&1; then
        skip "$symbols_dst already up to date"
    else
        if [[ "$MODE" == "check" ]]; then
            log "WOULD: cp $src $symbols_dst"
        else
            cp "$src" "$symbols_dst"
            ok "Installed $symbols_dst"
        fi
    fi

    # 2. Patch configuration.nix with extraLayouts
    if [[ -f "$CONFIG_NIX" ]]; then
        if grep -q "extraLayouts" "$CONFIG_NIX" 2>/dev/null; then
            skip "configuration.nix already has extraLayouts"
        else
            if [[ "$MODE" == "check" ]]; then
                log "WOULD: add extraLayouts block to $CONFIG_NIX"
            else
                local block
                block=$(cat <<'NBLOCK'
    services.xserver.xkb.extraLayouts.graphite = {
      description = "Graphite";
      languages = [ "eng" ];
      symbolsFile = ./graphite;
    };
NBLOCK
)
                # Insert before the last }
                local last_brace=$(grep -n "^}" "$CONFIG_NIX" | tail -1 | cut -d: -f1)
                if [[ -n "$last_brace" ]]; then
                    sed -i "${last_brace}i\\
${block}" "$CONFIG_NIX"
                    ok "Added extraLayouts to $CONFIG_NIX"
                else
                    log "WARN: Could not find closing } in $CONFIG_NIX, appending"
                    echo "" >> "$CONFIG_NIX"
                    echo "$block" >> "$CONFIG_NIX"
                    ok "Appended extraLayouts to $CONFIG_NIX"
                fi
            fi
        fi
    else
        log "WARN: $CONFIG_NIX not found"
        log "  Manually add to configuration.nix:"
        log "    services.xserver.xkb.extraLayouts.graphite = {"
        log "      description = \"Graphite\";"
        log "      languages = [ \"eng\" ];"
        log "      symbolsFile = ./graphite;"
        log "    };"
    fi

    log "Run: sudo nixos-rebuild switch"
}

# --- standard Linux install ---

install_standard() {
    local src="$SCRIPT_DIR/symbols/$LAYOUT_NAME"

    # Find symbols dir
    local symbols_dir=""
    for d in /usr/share/X11/xkb/symbols /usr/share/xkeyboard-config-2/symbols; do
        [[ -d "$d" ]] && { symbols_dir="$d"; break; }
    done
    [[ -n "$symbols_dir" ]] || fail "No xkb symbols directory found"

    # Find evdev files
    local evdev_xml="" evdev_lst=""
    for d in /usr/share/X11/xkb/rules /usr/share/xkeyboard-config-2/rules; do
        [[ -z "$evdev_xml" && -f "$d/evdev.xml" ]] && evdev_xml="$d/evdev.xml"
        [[ -z "$evdev_lst" && -f "$d/evdev.lst" ]] && evdev_lst="$d/evdev.lst"
    done

    log "Symbols dir: $symbols_dir"
    [[ -n "$evdev_xml" ]] && log "evdev.xml: $evdev_xml" || log "evdev.xml: not found"
    [[ -n "$evdev_lst" ]] && log "evdev.lst: $evdev_lst" || log "evdev.lst: not found"

    # Install symbols file
    [[ -f "$src" ]] || fail "symbols/$LAYOUT_NAME not found in $SCRIPT_DIR"
    local dst="$symbols_dir/$LAYOUT_NAME"

    if [[ -f "$dst" ]] && diff -q "$src" "$dst" >/dev/null 2>&1; then
        skip "$dst already up to date"
    else
        if [[ "$MODE" == "check" ]]; then
            log "WOULD: cp $src $dst"
        else
            mkdir -p "$(dirname "$dst")"
            cp "$src" "$dst"
            ok "Installed $dst"
        fi
    fi

    # Install evdev.xml entry
    if [[ -n "$evdev_xml" ]]; then
        if grep -q "$LAYOUT_MARKER" "$evdev_xml" 2>/dev/null; then
            skip "evdev.xml already has graphite entry"
        else
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
                log "WOULD: insert layout block into $evdev_xml"
            elif grep -q "</layoutList>" "$evdev_xml"; then
                sed -i "/<\/layoutList>/i\\$block" "$evdev_xml"
                ok "Added layout entry to $evdev_xml"
            else
                log "WARN: $evdev_xml missing </layoutList> tag, skipping"
            fi
        fi
    fi

    # Install evdev.lst entry
    if [[ -n "$evdev_lst" ]]; then
        if grep -q "$LAYOUT_MARKER" "$evdev_lst" 2>/dev/null; then
            skip "evdev.lst already has graphite entry"
        else
            if [[ "$MODE" == "check" ]]; then
                log "WOULD: insert layout line into $evdev_lst"
            elif grep -q "^! layout" "$evdev_lst"; then
                sed -i "/^! layout$/a\\  $LAYOUT_NAME        Graphite  $LAYOUT_MARKER" "$evdev_lst"
                ok "Added layout entry to $evdev_lst"
            else
                log "WARN: $evdev_lst missing ! layout section, skipping"
            fi
        fi
    fi

    log "Done. Set layout with: setxkbmap $LAYOUT_NAME"
}

# --- main ---

main() {
    log "Mode: $MODE"
    if is_nixos; then
        install_nixos
    else
        install_standard
    fi
}

main
