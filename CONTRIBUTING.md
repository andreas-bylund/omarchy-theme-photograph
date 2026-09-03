# Contributing

Thanks for looking. The tool is a few hundred lines of Bash, so most changes
are small and quick to review.

## Setup

```bash
git clone https://github.com/andreas-bylund/omarchy-theme-photograph
cd omarchy-theme-photograph
bin/omarchy-theme-photograph doctor
```

You need an Omarchy 4 desktop to run it for real. The tests do not.

## Running the tests

```bash
test/run.sh
```

They cover the pure parts: naming a theme from its repository URL, shell
quoting, Lua string quoting, parsing the theme list, reading `colors.toml`,
and rendering the palette sheet. They run in CI on every push together with
`shellcheck` and `bash -n`. Install `shellcheck` locally to see the same
warnings before you push.

## Trying a change without wrecking your desktop

The tool switches themes and opens windows on a virtual screen, then puts
everything back. While developing, keep the runs short and the output out of
the way:

```bash
bin/omarchy-theme-photograph shoot --scenes desktop,terminal --out /tmp/otp-test --keep-png
```

If something goes wrong halfway, the cleanup still runs on exit. If it does
not (say the shell was killed), `hyprctl output remove OTP` removes the
virtual screen by hand.

For anything that runs `batch`, use the VM in `vm/`. It installs community
themes, which means cloning strangers' repositories.

## Adding a scene

A scene is one function in `lib/scenes.sh`, named `scene_<name>`. It arranges
something on the virtual screen and calls `otp_capture <name>`. Cleanup is
automatic: every window on the virtual workspace is closed and shell overlays
are hidden after each scene.

```bash
scene_lazygit() {
  otp_have lazygit || { warn "lazygit not installed"; return 1; }
  otp_launch_tui TUI.photo-lazygit lazygit -p "$OTP_SHOWCASE_DIR" >/dev/null || return 1
  otp_settle 3
  otp_capture lazygit
}
```

Then:

1. Add the name to `OTP_ALL_SCENES` in `lib/common.sh`, and to
   `OTP_DEFAULT_SCENES` only if every theme should get it by default.
2. Add a row to the scene table in `README.md`, and to the labels in
   `scripts/readme-images.sh`. Run that script against a photograph run to
   regenerate the two pictures in the README.
3. Think about what keeps the picture identical across themes. The content
   comes from `assets/`; the terminal session is `assets/terminal-showcase.sh`.
   A scene that shows your home folder or the current time is not comparable.

Helpers you will use:

- `otp_launch_tui CLASS CMD ARGS...` opens the default terminal running a
  command and waits for its window. Use a class starting with `TUI.` so
  Omarchy's own window rules for `org.omarchy.*` do not apply.
- `otp_launch CLASS CMD ARGS...` does the same for a GUI app.
- `hypr_wait_layer NAMESPACE MONITOR` waits for a shell surface such as the
  menu to appear on the virtual screen.
- `otp_settle SECONDS` waits for animations and first paints.
- `otp_note KEY VALUE` records something in `meta.json` under `notes`.

## Style

- `set -euo pipefail` at the top of every script, functions prefixed by their
  file (`hypr_`, `theme_`, `render_`, `otp_`), no global state that is not
  an `OTP_*` variable.
- Everything the user can tune is an `OTP_*` environment variable with a
  default in `lib/common.sh` and, where it matters, a command line flag.
- Prefer a sentence in a comment over a clever line of code.
- Output for humans goes through `log`, `info`, `warn` and `die`.

## Pull requests

One change per pull request, with a sentence on why. Run `test/run.sh` and,
if you changed a scene, attach one picture of the result.
