# Installs lattice from the installer ISO: docs/install.md steps 3-7 in one run. Everything
# it needs is asked first, and nothing is written to the disk until the summary is confirmed;
# after that it runs unattended. Safe to run again after a failure: it starts over.
#
# Environment, set by installer/default.nix: LATTICE_VERSION, LATTICE_REPO, and either
# LATTICE_REV (the commit to clone) or LATTICE_TREE (a copy of an uncommitted tree). Being
# set from outside, they look like misspellings of each other to shellcheck.
# shellcheck disable=SC2153

min_gib=40
mapper=system
log=/tmp/lattice-install.log

say() { printf '\n\e[1m%s\e[0m\n' "$*"; }
die() {
    printf '\n\e[31m%s\e[0m\n' "$*" >&2
    exit 1
}

((EUID == 0)) || die "run it as root: sudo lattice-install"
esp_id_file=/proc/device-tree/chosen/asahi,efi-system-partition
[[ -r "$esp_id_file" ]] || die "no Asahi ESP in the device tree; run the Asahi installer from macOS first (docs/install.md)"

# A rerun after a failure finds the last attempt's mounts and LUKS mapping still up.
umount -R /mnt 2>/dev/null || true
cryptsetup close "$mapper" 2>/dev/null || true

say "lattice $LATTICE_VERSION installer"

### NETWORK ###
# Everything past here downloads: the repo, and the system from the binary caches.
until nm-online -q -t 5; do
    echo "No network yet. Opening nmtui: pick \"Activate a connection\", join a network, then quit."
    read -rp "Press Enter to continue."
    nmtui || true
done

### THE REPO ###
# Cloned now, into tmpfs, so the host name can be checked against it; it moves to the new
# disk once there is one.
work=/tmp/lattice
rm -rf "$work"
if [[ -n "${LATTICE_REV:-}" ]]; then
    say "Fetching lattice at ${LATTICE_REV:0:7}"
    git clone --quiet "$LATTICE_REPO" "$work"
    git -C "$work" reset --quiet --hard "$LATTICE_REV"
else
    say "This ISO was built from an uncommitted tree; installing that tree, without history"
    cp -rT "$LATTICE_TREE" "$work"
    chmod -R u+w "$work"
    git -C "$work" init --quiet -b main
    git -C "$work" add -A
fi

### QUESTIONS ###
while :; do
    read -rp "Name for this machine [lattice]: " host
    host="${host:-lattice}"
    if [[ ! "$host" =~ ^[a-z][a-z0-9-]{0,62}$ ]]; then
        echo "lowercase letters, digits and dashes, starting with a letter"
    elif [[ -e "$work/hosts/$host" ]]; then
        echo "hosts/$host already exists in lattice; pick another"
    else
        break
    fi
done

while :; do
    read -rp "Your user name: " user
    if [[ ! "$user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
        echo "lowercase letters, digits, dashes and underscores, starting with a letter"
    elif [[ "$user" == root || "$user" == nixos ]]; then
        echo "$user is taken"
    else
        break
    fi
done

# Read twice, hidden, until both match, and printed: everything else goes to stderr.
ask_secret() {
    local secret again
    while :; do
        read -rsp "$1: " secret
        echo >&2
        read -rsp "Again: " again
        echo >&2
        if [[ -z "$secret" ]]; then
            echo "it can't be empty" >&2
        elif [[ "$secret" != "$again" ]]; then
            echo "they don't match" >&2
        else
            printf '%s' "$secret"
            return
        fi
    done
}

password="$(ask_secret "Password for $user")"
password_hash="$(mkpasswd --method=yescrypt --stdin <<<"$password")"
unset password

echo "The disk is encrypted, and asks for its own passphrase at every boot."
passphrase="$(ask_secret "Disk passphrase")"

while :; do
    read -rp "Time zone [America/New_York]: " tz
    tz="${tz:-America/New_York}"
    if [[ -f "/etc/zoneinfo/$tz" ]]; then
        break
    fi
    echo "no such zone; they look like Europe/Berlin (ls /etc/zoneinfo)"
done

### WHERE ###
# The disk is the one holding the ESP the Asahi installer made. lattice goes into the free
# space it left, or replaces a Linux partition from an earlier install. Apple's partitions,
# the ESP and the GPT itself are never touched: damaging those can leave the Mac unbootable.
esp="/dev/disk/by-partuuid/$(tr -d '\0' <"$esp_id_file")"
[[ -e "$esp" ]] || die "can't find the ESP ($esp)"
esp="$(readlink -f "$esp")"
disk="/dev/$(lsblk -no PKNAME "$esp")"
sector="$(blockdev --getss "$disk")"

targets=() labels=()
first="$(sgdisk -F "$disk")"
last="$(sgdisk -E "$disk")"
if ((last > first)); then
    free_gib=$(((last - first + 1) * sector / 1024 ** 3))
    if ((free_gib >= min_gib)); then
        targets+=("free")
        labels+=("the free space (${free_gib} GiB) -- a new partition")
    fi
fi
linux_types="0fc63daf-8483-4772-8e79-3d69d8477de4|ca7d7ccb-63ed-4c53-861c-1742536059cc"
while read -r name type size fstype label; do
    if [[ "$type" =~ ^($linux_types)$ ]]; then
        targets+=("/dev/$name")
        labels+=("/dev/$name ($size ${fstype:-empty}${label:+ \"$label\"}) -- ERASES it")
    fi
done < <(lsblk -rno NAME,PARTTYPE,SIZE,FSTYPE,LABEL "$disk" | tail -n +2)

if ((${#targets[@]} == 0)); then
    die "no room: there is less than $min_gib GiB of free space and no Linux partition to replace. Rerun the Asahi installer from macOS and resize (r) to make some."
fi

say "Where should lattice go?"
for i in "${!labels[@]}"; do
    echo "  $((i + 1)). ${labels[$i]}"
done
while :; do
    read -rp "Choice [1]: " choice
    choice="${choice:-1}"
    if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#targets[@]})); then
        target="${targets[$((choice - 1))]}"
        break
    fi
done

### CONFIRM ###
say "Ready to install"
cat <<EOF
  machine    $host
  user       $user
  time zone  $tz
  disk       $disk
  into       ${labels[$((choice - 1))]}
  boot       $esp (the Asahi ESP, kept as it is)

$( [[ "$target" == free ]] || echo "Everything on $target will be lost. ")Nothing has been written yet.
EOF
read -rp "Type yes to install: " answer
[[ "$answer" == yes ]] || die "stopped; nothing was changed"

exec > >(tee -a "$log") 2>&1
trap 'echo; echo "lattice-install failed; the log is $log. Running it again starts over." >&2' ERR

### PARTITION ###
if [[ "$target" == free ]]; then
    say "Creating the partition"
    before="$(lsblk -rno PARTUUID "$disk" | sort)"
    # Partition 0 means the first unused number, and -s sorts the table afterwards, as the
    # nixos-apple-silicon guide does. Sorting renumbers, so the new one is found by its UUID.
    sgdisk "$disk" -n "0:$first:$last" -t 0:8309 -c 0:lattice -s >/dev/null
    udevadm settle
    uuid="$(comm -13 <(echo "$before") <(lsblk -rno PARTUUID "$disk" | sort) | head -n 1)"
    [[ -n "$uuid" ]] || die "sgdisk made no partition"
    part="$(readlink -f "/dev/disk/by-partuuid/$uuid")"
else
    part="$target"
    say "Erasing $part"
    wipefs -aq "$part"
    number="$(cat "/sys/class/block/$(basename "$part")/partition")"
    sgdisk "$disk" -t "$number:8309" -c "$number:lattice" >/dev/null
    udevadm settle
fi

### ENCRYPT, FORMAT, MOUNT ###
say "Encrypting $part"
printf '%s' "$passphrase" | cryptsetup luksFormat --type luks2 --batch-mode --key-file=- "$part"
printf '%s' "$passphrase" | cryptsetup open --key-file=- "$part" "$mapper"
unset passphrase

# The layout hosts/macbook's stand-in hardware config describes: the top level is /, with
# home and nix in their own subvolumes.
say "Formatting"
mkfs.btrfs -q -f -L lattice "/dev/mapper/$mapper"
mount "/dev/mapper/$mapper" /mnt
btrfs -q subvolume create /mnt/home
btrfs -q subvolume create /mnt/nix
umount /mnt
mount "/dev/mapper/$mapper" /mnt
mkdir -p /mnt/home /mnt/nix /mnt/boot
mount -o subvol=home "/dev/mapper/$mapper" /mnt/home
mount -o subvol=nix "/dev/mapper/$mapper" /mnt/nix
# With the masks the installed system uses, so the generated config carries them.
mount -o fmask=0077,dmask=0077 "$esp" /mnt/boot

### FIRMWARE ###
# Apple's Wi-Fi, Bluetooth and camera firmware, which the Asahi installer left on the ESP.
# The flake reads it from /var/lib/lattice/vendorfw, pinned by hash (see
# lattice.asahi.firmwareHash), and the install evaluates the flake here, on the live
# system -- so the copy goes both here and onto the new disk.
say "Copying the firmware"
[[ -d /mnt/boot/vendorfw ]] || die "no vendorfw on the ESP; was the Asahi installer run with \"UEFI environment only\"?"
for root in / /mnt/; do
    rm -rf "${root}var/lib/lattice/vendorfw"
    install -d -m 0755 "${root}var/lib/lattice"
    cp -rT /mnt/boot/vendorfw "${root}var/lib/lattice/vendorfw"
    chmod -R a+rX "${root}var/lib/lattice/vendorfw"
done
firmware_hash="$(nix hash path /var/lib/lattice/vendorfw)"

### THE HOST ###
say "Writing hosts/$host"
repo="/mnt/home/$user/lattice"
mkdir -p "/mnt/home/$user"
cp -a "$work" "$repo"

hostdir="$repo/hosts/$host"
mkdir "$hostdir"
nixos-generate-config --root /mnt --show-hardware-config >"$hostdir/hardware-configuration.nix"
{
    echo "# $host, installed by lattice-install $LATTICE_VERSION on $(date +%F)."
    sed -e '1,3d' \
        -e "s|networking.hostName = \".*\";|networking.hostName = \"$host\";|" \
        -e "s|time.timeZone = \".*\";|time.timeZone = \"$tz\";|" \
        -e "s|lattice.user.name = \".*\";|lattice.user.name = \"$user\";|" \
        -e "s|lattice.asahi.firmwareHash = \".*\";|lattice.asahi.firmwareHash = \"$firmware_hash\";|" \
        "$repo/hosts/macbook/default.nix"
} >"$hostdir/default.nix"
for want in "\"$host\"" "\"$tz\"" "\"$user\"" "\"$firmware_hash\""; do
    grep -qF "$want" "$hostdir/default.nix" || die "hosts/macbook/default.nix changed shape; $want did not make it into hosts/$host"
done
# A flake sees only what git tracks.
git -C "$repo" add "hosts/$host"

### INSTALL ###
# Kernel builds and the like go to the new disk, not to the live system's RAM-backed /tmp.
say "Installing. Most of it downloads; anything not in the caches is built here, which can take a while."
mkdir -p /mnt/var/tmp
TMPDIR=/mnt/var/tmp nixos-install --root /mnt --flake "$repo#$host" --no-root-passwd --no-channel-copy

say "Setting up $user"
printf '%s:%s\n' "$user" "$password_hash" | nixos-enter --root /mnt -c "chpasswd -e"
nixos-enter --root /mnt -c "chown $user: /home/$user && chown -R $user: /home/$user/lattice"

cp "$log" /mnt/var/log/lattice-install.log
say "lattice is installed"
cat <<EOF
Take out the stick and reboot. If macOS comes up instead, hold the power button at startup
and pick lattice. The disk passphrase comes first, then the login.

The flake is in ~/lattice, with hosts/$host staged but not committed: commit it, and from
then on \`lattice rebuild\` applies changes.
EOF
