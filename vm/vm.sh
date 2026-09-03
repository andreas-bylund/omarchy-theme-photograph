#!/usr/bin/env bash
# A throwaway Omarchy VM on QEMU/KVM for photographing themes.
#
#   vm/vm.sh install        boot the Omarchy ISO and install (once)
#   vm/vm.sh start          boot the installed VM
#   vm/vm.sh setup          first time only: SSH key, copy the tool in, fixed
#                           1920x1080 screen, no idle lock, run doctor
#   vm/vm.sh sync           copy this working tree into the VM again
#   vm/vm.sh run ARGS...    run omarchy-theme-photograph inside the VM session,
#                           e.g.  vm/vm.sh run shoot --scenes hero,palette
#                                 vm/vm.sh run batch --stock --skip-existing
#   vm/vm.sh pull           rsync the VM's pictures into ./out
#   vm/vm.sh ssh [CMD...]   shell into the VM
#   vm/vm.sh status         is it running, is SSH up
#   vm/vm.sh stop           ACPI power button (add --force to kill)
#   vm/vm.sh destroy        delete disk and firmware state
#
# Settings, all environment variables:
#   OTP_VM_DIR    disk and firmware state          (default ~/VMs/omarchy-photograph)
#   OTP_VM_ISO    installer image                  (default newest ~/Downloads/omarchy-*.iso)
#   OTP_VM_USER   user you create in the installer (default $USER)
#   OTP_VM_PORT   host port forwarded to guest SSH (default 2222)
#   OTP_VM_KEY    public key to install in the VM  (default first ~/.ssh/id_*.pub)
#   OTP_VM_CPUS / OTP_VM_MEM / OTP_VM_DISK         (default 4 / 8G / 40G)
#   OTP_VM_DISPLAY  QEMU -display option            (default sdl,gl=on; gtk,gl=on
#                   shows only a black window on NVIDIA under Wayland)
#
# Host packages: qemu-desktop edk2-ovmf (and rsync, openssh, python3 — stock).
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$here/.." && pwd)

VM_DIR=${OTP_VM_DIR:-$HOME/VMs/omarchy-photograph}
VM_USER=${OTP_VM_USER:-$USER}
VM_PORT=${OTP_VM_PORT:-2222}
VM_CPUS=${OTP_VM_CPUS:-4}
VM_MEM=${OTP_VM_MEM:-8G}
VM_DISK=${OTP_VM_DISK:-40G}
VM_DISPLAY=${OTP_VM_DISPLAY:-sdl,gl=on}
VM_NAME=omarchy-photograph
OVMF_CODE=/usr/share/edk2/x64/OVMF_CODE.4m.fd
OVMF_VARS=/usr/share/edk2/x64/OVMF_VARS.4m.fd

disk=$VM_DIR/disk.qcow2
vars=$VM_DIR/OVMF_VARS.4m.fd
pidfile=$VM_DIR/qemu.pid
monitor=$VM_DIR/monitor.sock
log=$VM_DIR/qemu.log
known_hosts=$VM_DIR/known_hosts

target="$VM_USER@127.0.0.1"
ssh_opts=(-p "$VM_PORT" -o UserKnownHostsFile="$known_hosts"
          -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR)
# Everything of ours in the guest lives under ~/.local/share, so the Files
# scene, which shows $HOME, looks like an untouched installation.
remote_dir='$HOME/.local/share/omarchy-theme-photograph'
remote_tool="$remote_dir/tool"
remote_out="$remote_dir/out"

die()  { echo "vm.sh: $*" >&2; exit 1; }
info() { echo "vm.sh: $*" >&2; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 not found. Install it with: sudo pacman -S --needed $2"; }

running() { [[ -f $pidfile ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; }

find_iso() {
  if [[ -n ${OTP_VM_ISO:-} ]]; then echo "$OTP_VM_ISO"; return; fi
  ls -t "$HOME"/Downloads/omarchy-*.iso 2>/dev/null | head -1 || true
}

find_key() {
  if [[ -n ${OTP_VM_KEY:-} ]]; then echo "$OTP_VM_KEY"; return; fi
  ls "$HOME"/.ssh/id_*.pub 2>/dev/null | head -1 || true
}

create() {
  need qemu-img qemu-desktop
  [[ -f $OVMF_CODE ]] || die "$OVMF_CODE missing. Install it with: sudo pacman -S --needed edk2-ovmf"
  mkdir -p "$VM_DIR"
  if [[ ! -f $disk ]]; then
    info "creating $disk ($VM_DISK)"
    qemu-img create -q -f qcow2 "$disk" "$VM_DISK"
  fi
  [[ -f $vars ]] || cp "$OVMF_VARS" "$vars"
}

# boot [ISO]: start QEMU detached. With an ISO attached the (empty) disk is
# still first in the boot order, so the ISO is only used until Omarchy is
# installed; after the installer's reboot the VM comes up from disk.
boot() {
  need qemu-system-x86_64 qemu-desktop
  running && die "already running (pid $(cat "$pidfile"))"
  [[ -w /dev/kvm ]] || die "/dev/kvm is not writable; is KVM enabled and are you in the kvm group?"
  create
  local iso=${1:-}
  local args=(
    -name "$VM_NAME"
    -machine q35,accel=kvm
    -cpu host -smp "$VM_CPUS" -m "$VM_MEM"
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE"
    -drive if=pflash,format=raw,file="$vars"
    -drive file="$disk",if=none,id=hd0,format=qcow2,discard=unmap
    -device virtio-blk-pci,drive=hd0,bootindex=0
    -device virtio-vga-gl,xres=1920,yres=1080
    -display "$VM_DISPLAY"
    -device qemu-xhci -device usb-tablet
    -netdev user,id=net0,hostfwd=tcp:127.0.0.1:"$VM_PORT"-:22
    -device virtio-net-pci,netdev=net0,romfile=
    -device virtio-rng-pci
    -monitor unix:"$monitor",server,nowait
    -pidfile "$pidfile"
  )
  if [[ -n $iso ]]; then
    [[ -f $iso ]] || die "ISO not found: $iso"
    args+=(-drive file="$iso",media=cdrom,if=none,id=cd0,format=raw,readonly=on
           -device ide-cd,drive=cd0,bootindex=1)
  fi
  rm -f "$pidfile"
  setsid -f qemu-system-x86_64 "${args[@]}" >"$log" 2>&1
  local i
  for i in $(seq 1 20); do
    running && break
    sleep 0.5
  done
  if ! running; then
    echo "QEMU did not start. Log ($log):" >&2
    tail -20 "$log" >&2
    exit 1
  fi
  info "$VM_NAME running (pid $(cat "$pidfile")), SSH on 127.0.0.1:$VM_PORT, log in $log"
}

cmd_install() {
  local iso; iso=$(find_iso)
  [[ -n $iso ]] || die "no Omarchy ISO found; download it from https://omarchy.org or set OTP_VM_ISO"
  if [[ -f $disk ]]; then
    read -r -p "vm.sh: $disk exists. Wipe it and reinstall? [y/N] " a
    [[ $a == [yY]* ]] || exit 1
    rm -f "$disk" "$vars" "$known_hosts"
  fi
  boot "$iso"
  cat <<EOF

The Omarchy installer is now up in the QEMU window. In it:

  - user name:  $VM_USER   (or set OTP_VM_USER to whatever you choose)
  - disk:       the 40 GB virtio disk
  - keep everything else at the defaults

When it has rebooted into the desktop, open a terminal there (Super+Return) and run:

  sudo systemctl enable --now sshd
  sudo ufw allow 22/tcp          # Omarchy's firewall denies incoming by default

Then, back on the host:

  $here/vm.sh setup
EOF
}

cmd_start() {
  [[ -f $disk ]] || die "no VM yet; run: $here/vm.sh install"
  boot
}

# Keep probes rare and cheap: OpenSSH penalises a source address for
# connections that end without a login (PerSourcePenalties), and every
# connection from the host arrives from the same SLIRP address. Polling the
# port every few seconds gets the host blocked for a while.
ssh_ok()   { ssh "${ssh_opts[@]}" -o BatchMode=yes -o ConnectTimeout=5 "$target" true 2>/dev/null; }
sshd_up()  { ssh-keyscan -t ed25519 -p "$VM_PORT" -T 5 127.0.0.1 2>/dev/null | grep -q .; }

cmd_ssh() {
  ssh "${ssh_opts[@]}" "$target" "$@"
}

cmd_sync() {
  need rsync rsync
  ssh_ok || die "cannot SSH into the VM; is it running and did you run setup?"
  cmd_ssh "mkdir -p $remote_tool $remote_out"
  rsync -a --delete --exclude .git --exclude out --exclude __pycache__ \
    -e "ssh $(printf '%q ' "${ssh_opts[@]}")" \
    "$repo/" "$target:.local/share/omarchy-theme-photograph/tool/"
  info "tool synced to $target:$remote_tool"
}

cmd_setup() {
  running || die "the VM is not running; start it first"
  sshd_up || die "no SSH server reachable in the VM. Inside the VM run:  sudo systemctl enable --now sshd && sudo ufw allow 22/tcp"

  if ! ssh_ok; then
    local key; key=$(find_key)
    [[ -n $key ]] || die "no SSH public key found; create one with ssh-keygen or set OTP_VM_KEY"
    info "installing $key in the VM (you will be asked for $VM_USER's password once)"
    ssh-copy-id -i "$key" "${ssh_opts[@]}" "$target" >/dev/null
    ssh_ok || die "still cannot log in as $VM_USER; check OTP_VM_USER"
  fi

  cmd_sync

  info "configuring the guest: fixed 1920x1080 screen, idle lock off"
  cmd_ssh bash -s <<'EOF'
set -euo pipefail
omarchy=${OMARCHY_PATH:-/usr/share/omarchy}

# Idle lock / screensaver: a day instead of five minutes, so a two hour batch
# never runs into the lock screen. (Stay-awake mode would do it too, but it
# shows an indicator in the bar, which would end up in every picture.)
mkdir -p ~/.config/omarchy
[[ -f ~/.config/omarchy/shell.json ]] || cp "$omarchy/config/omarchy/shell.json" ~/.config/omarchy/shell.json
tmp=$(mktemp)
jq '.idle.screensaver = 86400 | .idle.lock = 86400' ~/.config/omarchy/shell.json >"$tmp" && mv "$tmp" ~/.config/omarchy/shell.json

# The VM screen: exactly 1920x1080 at scale 1, so the lock scene (captured
# from the real screen) has the same geometry as the virtual one.
mon=~/.config/hypr/monitors.lua
if [[ -f $mon ]] && ! grep -q 'omarchy-theme-photograph' "$mon"; then
  sed -i 's/^local omarchy_gdk_scale = 2$/local omarchy_gdk_scale = 1/' "$mon"
  cat >>"$mon" <<'LUA'

-- omarchy-theme-photograph: the VM screen, always 1920x1080 at 1x
hl.monitor({ output = "Virtual-1", mode = "1920x1080", position = "auto", scale = 1 })
LUA
fi
EOF

  # Hyprland and the shell both watch their config files; a reload makes the
  # monitor change immediate. (Not omarchy-refresh-shell: that resets shell.json.)
  local rs="$remote_tool/scripts/run-in-session.sh"
  cmd_ssh "$rs hyprctl reload >/dev/null"
  sleep 3
  cmd_ssh "$rs $remote_tool/bin/omarchy-theme-photograph doctor"
  info "done. Try:  $here/vm.sh run shoot --scenes hero,palette && $here/vm.sh pull"
}

cmd_run() {
  (( $# )) || die "usage: vm.sh run ARGS...   (e.g. run shoot --scenes hero)"
  ssh_ok || die "cannot SSH into the VM; is it running and did you run setup?"
  local q; q=$(printf ' %q' "$@")
  cmd_ssh "OTP_OUT=$remote_out $remote_tool/scripts/run-in-session.sh $remote_tool/bin/omarchy-theme-photograph$q"
}

cmd_pull() {
  need rsync rsync
  ssh_ok || die "cannot SSH into the VM; is it running and did you run setup?"
  mkdir -p "$repo/out"
  rsync -a -e "ssh $(printf '%q ' "${ssh_opts[@]}")" "$target:.local/share/omarchy-theme-photograph/out/" "$repo/out/"
  info "pictures are in $repo/out"
}

cmd_status() {
  if running; then
    echo "running: pid $(cat "$pidfile"), disk $disk"
    if ssh_ok; then echo "ssh:     ok ($target port $VM_PORT)"
    elif sshd_up; then echo "ssh:     sshd is up but key login fails; run setup"
    else echo "ssh:     not reachable (no sshd yet, or still booting)"; fi
  else
    echo "not running"
    [[ -f $disk ]] && echo "disk:    $disk" || echo "disk:    none (run install)"
  fi
}

monitor_cmd() {
  python3 - "$monitor" "$1" <<'EOF'
import socket, sys
s = socket.socket(socket.AF_UNIX)
s.settimeout(5)
s.connect(sys.argv[1])
s.recv(4096)
s.sendall((sys.argv[2] + "\n").encode())
s.recv(4096)
EOF
}

cmd_stop() {
  running || { echo "not running"; return 0; }
  local pid; pid=$(cat "$pidfile")
  if [[ ${1:-} == --force ]]; then
    kill "$pid"
  else
    monitor_cmd system_powerdown
  fi
  local i
  for i in $(seq 1 60); do
    kill -0 "$pid" 2>/dev/null || { info "stopped"; rm -f "$pidfile"; return 0; }
    sleep 1
  done
  die "still running after 60 s; try: vm.sh stop --force"
}

cmd_destroy() {
  running && die "stop the VM first"
  [[ -d $VM_DIR ]] || { echo "nothing to delete"; return 0; }
  read -r -p "vm.sh: delete $VM_DIR (disk, firmware state, known_hosts)? [y/N] " a
  [[ $a == [yY]* ]] || exit 1
  rm -rf "$VM_DIR"
  info "deleted"
}

cmd=${1:-help}
shift || true
case $cmd in
  install) cmd_install "$@" ;;
  start)   cmd_start "$@" ;;
  setup)   cmd_setup "$@" ;;
  sync)    cmd_sync "$@" ;;
  run)     cmd_run "$@" ;;
  pull)    cmd_pull "$@" ;;
  ssh)     cmd_ssh "$@" ;;
  status)  cmd_status "$@" ;;
  stop)    cmd_stop "$@" ;;
  destroy) cmd_destroy "$@" ;;
  help|-h|--help) sed -n '2,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//p}' "$0" ;;
  *) die "unknown command: $cmd (try: vm.sh help)" ;;
esac
