# graphite-kp

Custom XKB keyboard layout. A Colemak-DH variant optimized for my use.

## Files

- `symbols/graphite` — key mapping
- `rules/evdev.xml` — XML layout entry to add to `evdev.xml`
- `rules/evdev.lst` — layout list entry to add to `evdev.lst`
- `install.sh` — automated installer

## Install

```bash
./install.sh
```

Prompts for your password when needed. Idempotent — safe to run multiple times.

Preview without changes:
```bash
./install.sh --check
```

Then activate:
- **X11**: `setxkbmap graphite`
- **Wayland/niri**: `layout "graphite"` in `input.keyboard.xkb`
- **SDDM**: `XkbLayout=graphite` in `/etc/sddm.conf`
- **console**: `XKBLAYOUT=graphite` in `/etc/vconsole.conf`
