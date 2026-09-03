# omarchy-theme-photograph

Take the same set of screenshots of every [Omarchy](https://omarchy.org) theme,
so themes can be compared side by side instead of through whatever preview
image each author happened to upload.

It runs inside a live Omarchy session. It creates a **virtual screen** (a
headless Hyprland output) next to your real ones, opens a fixed set of scenes
on it and photographs each scene with `grim`. Your own screens keep working
while it runs; the only thing you notice is the theme switch itself.

The output is a folder per theme with WebP images, a palette sheet and a
`meta.json`, plus an `index.json` across all themes. That is everything a
static website or a CDN bucket needs.

## What gets photographed

| Scene          | What you see                                                     |
| -------------- | ---------------------------------------------------------------- |
| `desktop`      | Empty workspace: wallpaper and the Omarchy bar                    |
| `hero`         | The classic Omarchy preview: Neovim, terminal, btop and Files tiled 2x2 |
| `terminal`     | A scripted shell session showing all 16 ANSI colours, a git log and a diff |
| `editor`       | Neovim (LazyVim) with a sample Ruby file                          |
| `btop`         | The btop system monitor                                          |
| `about`        | The floating "About" window (fastfetch with the Omarchy logo)     |
| `menu`         | The Omarchy menu (Super + Space)                                 |
| `apps`         | The app launcher                                                 |
| `notification` | A desktop notification                                           |
| `lock`         | The lock screen (shell preview mode, no real locking)            |
| `palette`      | A generated swatch sheet of every colour in `colors.toml`        |
| `colors`       | *(not default)* Omarchy's own palette preview TUI                |
| `files`        | *(not default)* The Files app on its own                         |

Every scene uses the same content for every theme (the sample files live in
`assets/`), the same 1920x1080 logical resolution and the same timing.

## Requirements

- Omarchy 4 (Hyprland with the Lua API, the Quickshell-based shell)
- `grim`, `jq`, `magick` (ImageMagick) — all part of a stock Omarchy install
- For the default scenes: `nvim`, `btop`, `nautilus` (stock as well)

Check with:

```bash
bin/omarchy-theme-photograph doctor
```

## Usage

Photograph the theme you are using right now:

```bash
bin/omarchy-theme-photograph shoot
```

Photograph a specific theme and switch back afterwards:

```bash
bin/omarchy-theme-photograph shoot --theme tokyo-night
```

Only some scenes, keep the lossless PNGs, different output folder:

```bash
bin/omarchy-theme-photograph shoot --scenes hero,terminal,palette --keep-png --out ~/shots
```

Photograph every theme in `themes.json` (installs community themes with
`omarchy theme install`, switches through them one by one, restores your
original theme at the end and writes `index.json`):

```bash
bin/omarchy-theme-photograph batch                 # everything
bin/omarchy-theme-photograph batch --stock         # only the built-in themes
bin/omarchy-theme-photograph batch --community --remove-after
bin/omarchy-theme-photograph batch --only dracula,nord --skip-existing
```

Rebuild the index after manual changes:

```bash
bin/omarchy-theme-photograph index --out ./out
```

Run `bin/omarchy-theme-photograph --help` for all options. Every option is
also an environment variable (`OTP_OUT`, `OTP_SCENES`, `OTP_WIDTH`, ...).

## Output layout

```
out/
├── index.json                 # all meta.json files merged, sorted by name
└── tokyo-night/
    ├── meta.json              # name, slug, repo, mode, colours, versions, scene files
    ├── palette.json           # the colours from colors.toml
    ├── hero.webp              # 1920 px wide
    ├── hero.thumb.webp        # 640 px wide
    ├── hero.png               # only with --keep-png (3840x2160)
    ├── desktop.webp ...
    └── palette.webp
```

`meta.json` looks like this:

```json
{
  "name": "Tokyo Night",
  "slug": "tokyo-night",
  "repo": null,
  "stock": true,
  "mode": "dark",
  "colors": { "background": "#1a1b26", "accent": "#7aa2f7", "...": "..." },
  "background": "1-scenery-pink-lakeside-sunset-lake-landscape-scenic-panorama-7680x3215-144.png",
  "omarchy_version": "4.0.2-1",
  "hyprland_version": "v0.56.2",
  "captured_at": "2026-09-03T12:00:00Z",
  "resolution": { "width": 1920, "height": 1080, "scale": 2 },
  "scenes": { "hero": { "full": "hero.webp", "thumb": "hero.thumb.webp", "width": 1920, "height": 1080 } },
  "notes": {}
}
```

## The theme list

`themes.json` is generated from the community list on
[omarchy.org/themes](https://omarchy.org/themes) plus the stock themes of the
machine it was generated on. Regenerate it with:

```bash
scripts/fetch-theme-list.py
```

Each entry has the display `name`, the site `slug`, the git `repo`, and
`install_name`, which is the directory name Omarchy gives the theme when it
installs it (`omarchy-foo-theme` becomes `foo`). Output folders use the
install name.

## Getting consistent pictures

The virtual screen guarantees the same resolution and the same window layout,
but the shell still shows *your* bar layout, plugins, fonts and clock. For a
public gallery, run the batch in a fresh Omarchy VM with an untouched
configuration. See [`vm/README.md`](vm/README.md).

Things worth knowing:

- The lock screen preview is a single shell layer that always lands on the
  first real screen. In a single-screen VM that is fine. On a multi-monitor
  desktop the `lock` scene is captured from your real screen and `meta.json`
  records which one under `notes.lock_monitor`.
- `hero` and `files` show `$HOME` in the file manager. Set `OTP_FILES_DIR` to
  show another folder.
- Animations are turned off and the cursor is hidden while photographing;
  both settings are restored afterwards.
- Switching themes rotates the wallpaper the way `omarchy theme set` always
  does, so after a batch your wallpaper may be a different one from the same
  theme.

## Running in a VM over SSH

The tool needs the environment of the running Hyprland session. Over SSH,
wrap it in `scripts/run-in-session.sh`:

```bash
ssh omarchy-vm '~/omarchy-theme-photograph/scripts/run-in-session.sh \
  ~/omarchy-theme-photograph/bin/omarchy-theme-photograph batch --out ~/out'
rsync -a omarchy-vm:out/ ./out/
```

## Publishing to Cloudflare R2

```bash
scripts/upload-r2.sh ./out r2:omarchy-themes/v1
```

The script uses `rclone`, skips PNGs, gives images a one-year cache lifetime
and `index.json` a five-minute one. Point a website at
`https://<your-r2-domain>/v1/index.json` and render the gallery from that.

## Photographing your own theme

Theme authors can use this to produce the standard set of pictures for a
theme they are working on:

```bash
omarchy theme set my-theme
bin/omarchy-theme-photograph shoot --out ./shots --keep-png
```

`shots/my-theme/hero.png` is a good candidate for the `preview.png` a theme
ships with.

## How it works

1. `hyprctl output create headless` adds a virtual screen, configured with
   `hl.monitor` to 1920x1080 at 2x scale (so the images are 3840x2160).
2. A spare workspace is placed on it and focused.
3. Windows are started through `hl.exec_cmd` with a workspace rule, and the
   tool waits until Hyprland reports them mapped on that workspace.
4. Shell surfaces (menu, launcher, notification, lock preview) are opened via
   `omarchy-menu` / `omarchy-shell` IPC and the tool waits for their layer to
   appear on the virtual screen.
5. `grim -o <output>` captures the frame; ImageMagick writes the WebP files.
6. Everything is closed, the virtual screen is removed and your focus,
   animation and cursor settings are put back.

## License

MIT, see [LICENSE](LICENSE).
