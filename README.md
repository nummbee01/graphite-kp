# graphite-kp

Custom XKB keyboard layout. A Colemak-DH variant optimized for my use.

## Files

- `symbols/graphite` — key mapping (install to `/usr/share/X11/xkb/symbols/`)
- `rules/evdev.xml` — XML layout entry (add to `evdev.xml` `<layoutList>`)
- `rules/evdev.lst` — layout list entry (add to `evdev.lst` `! layout` section)

## Install

1. Copy `symbols/graphite` to `/usr/share/X11/xkb/symbols/graphite`
2. Add the `<layout>` block from `rules/evdev.xml` to `/usr/share/X11/xkb/rules/evdev.xml`
3. Add the line from `rules/evdev.lst` to `/usr/share/X11/xkb/rules/evdev.lst`
4. Set layout in your compositor/DE:
   - **niri**: `layout "graphite"` in `input.keyboard.xkb`
   - **X11**: `setxkbmap graphite`
   - **SDDM**: `XkbLayout=graphite` in `/etc/sddm.conf`
   - **console**: `XKBLAYOUT=graphite` in `/etc/vconsole.conf`
