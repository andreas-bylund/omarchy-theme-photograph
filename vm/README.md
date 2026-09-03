# Photographing in a clean VM

For a public gallery every picture should come from the same, untouched
Omarchy configuration: stock bar layout, stock fonts, no extra plugins, the
same clock format. The easiest way to get that is a virtual machine that is
used for nothing else.

## 1. Create the VM

Any hypervisor with a virtio GPU works; libvirt/virt-manager or plain QEMU on
the host is the usual choice. Recommended settings:

- 4 CPUs, 8 GB RAM, 40 GB disk
- Display: virtio with 3D acceleration on (QEMU: `-device virtio-vga-gl -display gtk,gl=on`)
- One screen, 1920x1080

Install Omarchy from the ISO at <https://omarchy.org> and let it boot into
the desktop. Omarchy logs the user in automatically, which is what we want:
the batch needs a running Hyprland session.

## 2. Prepare the guest

Inside the VM:

```bash
sudo systemctl enable --now sshd
git clone https://github.com/andreas-bylund/omarchy-theme-photograph ~/omarchy-theme-photograph
~/omarchy-theme-photograph/bin/omarchy-theme-photograph doctor
```

Do not customise anything else in the VM. If you do change something (for
example the clock format), change it once and keep it for every batch.

Optional but useful:

- Turn off the idle lock so the session never locks in the middle of a batch:
  set `idle.lock` to `0` in `~/.config/omarchy/shell.json`.
- Set the VM screen to exactly 1920x1080 so the `lock` scene, which is
  captured from the real screen, matches the other pictures.

## 3. Run the batch from the host

```bash
ssh omarchy-vm '~/omarchy-theme-photograph/scripts/run-in-session.sh \
  ~/omarchy-theme-photograph/bin/omarchy-theme-photograph batch \
    --out ~/out --skip-existing --remove-after'
rsync -a omarchy-vm:out/ ./out/
```

`run-in-session.sh` copies the Wayland and Hyprland variables of the logged-in
session into the SSH shell. `--remove-after` keeps `~/.config/omarchy/themes`
from filling up with 150 clones; `--skip-existing` lets you re-run after an
interruption.

A full batch of about 170 themes takes roughly 1.5 to 2 hours, most of it the
theme switches themselves.

## 4. Publish

```bash
./bin/omarchy-theme-photograph index --out ./out
./scripts/upload-r2.sh ./out r2:omarchy-themes/v1
```

## Keeping the gallery fresh

Re-run the batch whenever `themes.json` changes or Omarchy updates its shell
look. `scripts/fetch-theme-list.py` regenerates the list from omarchy.org,
and `--skip-existing` makes the batch only photograph the newcomers. Delete a
theme's folder under `out/` to force a new set of pictures for it.
