# graphite-kp

## Install

### Linux

1. Copy `linux/graphite` to `/etc/nixos/graphite`.
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
3. `nixos-rebuild switch`, re-login, select graphite.

### Windows

1. Run `windows\scripts\Install.cmd` as administrator.
2. Sign out and back in.

Details: `linux/AGENTS.md`, `windows/AGENTS.md`.
