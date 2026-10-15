# graphite-kp: Linux

1. Copy `graphite` to `/etc/nixos/graphite`.
2. In `configuration.nix`:
```nix
services.xserver.xkb = {
  layout = "graphite";
  variant = "";
  extraLayouts.graphite = {
    description = "Graphite";
    languages = [ "eng" ];
    symbolsFile = ./graphite;
  };
};
console.useXkbConfig = true;
```
3. GNOME Wayland ignores the X server layout, pin it via dconf:
```nix
programs.dconf.profiles.user.databases = [{
  settings."org/gnome/desktop/input-sources".sources =
    [ (lib.gvariant.mkTuple [ "xkb" "graphite" ]) ];
}];
```
4. `nixos-rebuild switch`, re-login, select graphite as input source.

## Rules

- The symbols block MUST be `xkb_symbols "basic"` (the default variant).
  Any other name builds fine but GNOME/IBus fails with
  "Cannot find engine xkb:graphite::eng" and falls back to US.
- Verify: `localectl status` shows `X11 Layout: graphite`;
  `gsettings get org.gnome.desktop.input-sources sources` lists graphite;
  `journalctl -b | grep -i xkb` shows no engine errors.
