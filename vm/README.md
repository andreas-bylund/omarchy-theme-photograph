# Photographing in a clean VM

For a public gallery every picture should come from the same, untouched
Omarchy configuration: stock bar layout, stock fonts, no extra plugins, the
same clock format. The easiest way to get that is a virtual machine that is
used for nothing else.

`vm/vm.sh` runs such a machine with plain QEMU/KVM on the host. No libvirt,
no daemon: a qcow2 disk and the UEFI variables in `~/VMs/omarchy-photograph`,
a virtio GPU with 3D acceleration, one 1920x1080 screen, and the guest's SSH
port forwarded to `localhost:2222`.

## 1. Host packages

```bash
sudo pacman -S --needed qemu-desktop edk2-ovmf
```

`qemu-desktop` brings QEMU with the SDL and GTK displays and the
virtio-gpu-gl device, `edk2-ovmf` the UEFI firmware. KVM needs `/dev/kvm` to be writable
for you; on Omarchy it is.

## 2. Install Omarchy

Download the ISO from <https://omarchy.org> into `~/Downloads`, then:

```bash
vm/vm.sh install
```

This creates a 40 GB disk, boots the ISO and prints what to answer in the
installer: pick your host user name as the VM user (or set `OTP_VM_USER`),
choose the virtio disk, keep the defaults otherwise. The installer reboots
into the desktop and logs the user in automatically, which is what we want:
the batch needs a running Hyprland session.

Inside the VM, open a terminal (Super+Return) and turn on SSH:

```bash
sudo systemctl enable --now sshd
sudo ufw allow 22/tcp
```

Omarchy ships a firewall that denies all incoming connections, so the
second line is needed even though the VM is only reachable from the host.
That is the only thing to type in the VM window.

## 3. Prepare the guest from the host

```bash
vm/vm.sh setup
```

`setup` copies your SSH key in (asks for the VM password once), rsyncs this
working tree to `~/.local/share/omarchy-theme-photograph/tool` in the VM, and
makes two changes to the guest configuration:

- `~/.config/omarchy/shell.json`: idle lock and screensaver at 24 hours, so a
  two hour batch never runs into the lock screen. (The "stay awake" toggle
  would work too, but it shows an indicator in the bar, which would end up in
  every picture.)
- `~/.config/hypr/monitors.lua`: the VM screen fixed to 1920x1080 at scale 1,
  so the `lock` scene, which is captured from the real screen, has the same
  geometry as the virtual one.

It ends by running `omarchy-theme-photograph doctor` in the VM session.

Do not customise anything else in the VM. If you do change something (for
example the clock format), change it once and keep it for every batch.

## 4. Photograph

```bash
vm/vm.sh run shoot --scenes hero,palette     # quick test with the current theme
vm/vm.sh pull                                # rsync the VM's pictures into ./out

vm/vm.sh run batch --stock                   # all built-in themes
vm/vm.sh run batch --skip-existing --remove-after   # everything in themes.json
vm/vm.sh pull
```

`run` passes its arguments straight to `bin/omarchy-theme-photograph` inside
the VM, wrapped in `scripts/run-in-session.sh` so the tool sees the Wayland
and Hyprland variables of the logged-in session. Output goes to
`~/.local/share/omarchy-theme-photograph/out` in the VM; the tool and its
pictures stay out of `$HOME` on purpose, because the `hero` and `files`
scenes show the home folder. `--remove-after` keeps `~/.config/omarchy/themes` from filling up
with 150 clones; `--skip-existing` lets you re-run after an interruption.

After changing the tool on the host, `vm/vm.sh sync` copies it in again.

A full batch of about 170 themes takes roughly 1.5 to 2 hours, most of it the
theme switches themselves.

## 5. Publish

```bash
./bin/omarchy-theme-photograph index --out ./out
./scripts/upload-r2.sh ./out r2:omarchy-themes/v1
```

## Day to day

```bash
vm/vm.sh start          # boot the installed VM
vm/vm.sh status         # running? SSH reachable?
vm/vm.sh ssh            # a shell in the VM (or: vm/vm.sh ssh some command)
vm/vm.sh stop           # ACPI power button; --force kills QEMU
vm/vm.sh destroy        # delete the disk to start over
```

The QEMU window is a normal Hyprland window on the host. It stretches the
guest screen to whatever size it gets, so float it (Super+V) if you want the
right aspect ratio while you work in it. Closing the window is the same as
pulling the plug, use `stop` instead.

The script uses QEMU's SDL display with OpenGL. The GTK display, QEMU's
default, shows only a black window with the NVIDIA driver under Wayland;
`OTP_VM_DISPLAY` overrides the choice.

Every setting is an environment variable, see `vm/vm.sh help`: where the disk
lives, which ISO, the VM user, the SSH port, CPUs, memory, disk size.

## Keeping the gallery fresh

Re-run the batch whenever `themes.json` changes or Omarchy updates its shell
look. `scripts/fetch-theme-list.py` regenerates the list from omarchy.org,
and `--skip-existing` makes the batch only photograph the newcomers. Delete a
theme's folder under `out/` to force a new set of pictures for it. To move
to a new Omarchy release, `vm/vm.sh install` with the new ISO wipes the disk
and starts from a clean installation.
