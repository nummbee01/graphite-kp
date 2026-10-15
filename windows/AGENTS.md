# graphite-kp: Windows

1. Run `scripts/Install.cmd` as administrator.
2. Sign out and back in.
3. Switch with `Win`+`Space`, the layout is listed as "Graphite KP".

## Rules

- `source/graphite-kp.klc` makes Ctrl shortcuts follow the typed letter, like
  Linux. `source/graphite-kp-qwerty-shortcuts.klc` keeps them on the physical
  QWERTY key. `Install.cmd` builds the former.
- `kbdutool` reads only UTF-16LE and crashes (`0xC0000409`) on UTF-8, so
  `build.ps1` re-encodes the UTF-8 `.klc` into a temp copy before building.
- Verify: `Get-WinUserLanguageList` lists `0409:a0020409`.
