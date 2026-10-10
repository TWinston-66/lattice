#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Runs the installer ISO in a KVM virtual machine, against a disk laid out the way the Asahi
# installer leaves a Mac: an ESP with Apple's firmware on it, and free space after. Everything
# lattice-install does can be tried here -- partitioning, LUKS, the firmware hash, the host
# folder, the whole nixos-install -- except what only a Mac has: the Asahi boot chain, Wi-Fi.
#
#   scripts/installer-vm.sh          a fresh disk, booted from the ISO
#                                    (then: sudo lattice-install --esp /dev/vda1)
#   scripts/installer-vm.sh --boot   the disk alone, to see whether what it installed boots
#   scripts/installer-vm.sh --clean  delete the disk
#
# Anything after -- goes to QEMU as it is: a monitor or serial socket to drive the VM from a
# script, or another drive.
#
# The ISO is built from this checkout. Committed and pushed, it installs that commit; with
# uncommitted changes, it installs the tree as it is.

export NIX_CONFIG="experimental-features = nix-command flakes"
dir="${XDG_CACHE_HOME:-$HOME/.cache}/lattice-vm"
disk="$dir/disk.img"
vars="$dir/efi-vars.fd"
firmware=/var/lib/lattice/vendorfw

argv=("$@")
mode=install
case "${1:-}" in
"" | --) ;;
--boot) mode=boot ;;
--clean)
    rm -rf "$dir"
    echo "removed $dir"
    exit 0
    ;;
*)
    echo "usage: $0 [--boot | --clean] [-- qemu args]" >&2
    exit 2
    ;;
esac
[[ "${1:-}" == --boot ]] && shift
[[ "${1:-}" == -- ]] && shift
extra=("$@")

if [[ -z "${LATTICE_VM_SHELL:-}" ]]; then
    LATTICE_VM_SHELL=1 exec nix shell --inputs-from . \
        nixpkgs#qemu nixpkgs#gptfdisk nixpkgs#dosfstools nixpkgs#mtools \
        -c "$0" "${argv[@]}"
fi

# QEMU locks the disk it runs on, but a fresh disk is a new file, and the lock stays on the
# deleted one: a second run would install into the image under the first.
if pgrep -f "qemu-system-aarch64 .*file=$disk" >/dev/null; then
    echo "a VM is already running on $disk" >&2
    exit 1
fi

aavmf="$(nix build --no-link --print-out-paths --inputs-from . nixpkgs#OVMF.fd)/FV"
mkdir -p "$dir"

if [[ "$mode" == boot && ! -f "$disk" ]]; then
    echo "no disk yet; run $0 first" >&2
    exit 1
fi

if [[ "$mode" == install ]]; then
    [[ -d "$firmware" ]] || {
        echo "no $firmware to put on the ESP; this runs on a lattice Mac" >&2
        exit 1
    }

    # A fresh disk every time, as a Mac fresh out of the Asahi installer would be: GPT, a 500
    # MiB ESP holding vendorfw, and the rest free. Sparse, so only what the install writes
    # takes space.
    rm -f "$disk" "$vars"
    truncate -s 64G "$disk"
    sgdisk -n 1:2048:+500M -t 1:ef00 -c 1:"EFI - LATTI" "$disk" >/dev/null
    esp="$dir/esp.img"
    rm -f "$esp"
    truncate -s 500M "$esp"
    mkfs.vfat -n "EFI - LATTI" "$esp" >/dev/null
    MTOOLS_SKIP_CHECK=1 mcopy -s -i "$esp" "$firmware" ::/vendorfw
    dd if="$esp" of="$disk" bs=1M seek=1 conv=notrunc,sparse status=none
    rm "$esp"

    iso="$(nix build --no-link --print-out-paths .#installer)/iso"
    iso="$(echo "$iso"/*.iso)"
    echo "booting $(basename "$iso") with a fresh disk"
    echo "in the VM: sudo lattice-install --esp /dev/vda1"
fi

[[ -f "$vars" ]] || install -m 0644 "$aavmf/AAVMF_VARS.fd" "$vars"

args=(
    -machine virt -accel kvm -cpu host -smp 4 -m 8G
    -drive "if=pflash,format=raw,readonly=on,file=$aavmf/AAVMF_CODE.fd"
    -drive "if=pflash,format=raw,file=$vars"
    -drive "if=virtio,format=raw,file=$disk"
    -nic "user,model=virtio-net-pci"
    -device virtio-gpu-pci -display gtk
    -device qemu-xhci -device usb-kbd -device usb-tablet
)
if [[ "$mode" == install ]]; then
    args+=(-drive "if=virtio,format=raw,readonly=on,file=$iso")
fi

exec qemu-system-aarch64 "${args[@]}" "${extra[@]}"
