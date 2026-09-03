# Example output

What one theme looks like after `omarchy-theme-photograph shoot`, taken from
a run on a clean Omarchy 4.0.2 VM. The real output has every scene in three
sizes; this folder keeps only enough to show the format.

```
tokyo-night/
├── meta.json          # everything a site needs: name, slug, colours, versions, scene files, wallpapers
├── palette.json       # the colours from colors.toml
└── hero.thumb.webp    # the 640 px thumbnail of the hero scene
```

`index.json`, written by `batch` or `omarchy-theme-photograph index`, is
`{ "generated_at": ..., "count": N, "themes": [ <meta.json>, ... ] }` sorted by name.

Field notes for `meta.json`:

- `slug` is the directory name Omarchy gives the theme, derived from the
  repository URL the way `omarchy-theme-install` does it. It is also the output
  folder name.
- `scenes` maps scene name to its files: `full` (1920 px), `card` (1280 px),
  `thumb` (640 px), `png` when kept, and the pixel size of `full`.
- `resolution` is the virtual screen: logical size and scale factor.
- `notes.lock_monitor` is set when the lock screen was captured from a
  physical screen instead of the virtual one.
- `source` and `wallpapers` describe where the theme came from and which
  wallpapers it ships, when known.
