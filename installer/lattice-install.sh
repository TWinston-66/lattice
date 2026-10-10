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

# The Asahi ESP is the one the device tree names. --esp names it instead, for a machine
# without one: the VM scripts/installer-vm.sh runs this in.
esp=""
if [[ "${1:-}" == --esp ]]; then
    esp="${2:?--esp needs a partition}"
else
    esp_id_file=/proc/device-tree/chosen/asahi,efi-system-partition
    [[ -r "$esp_id_file" ]] || die "no Asahi ESP in the device tree; run the Asahi installer from macOS first (docs/install.md)"
    esp="/dev/disk/by-partuuid/$(tr -d '\0' <"$esp_id_file")"
fi
[[ -e "$esp" ]] || die "can't find the ESP ($esp)"
esp="$(readlink -f "$esp")"

# A rerun after a failure finds the last attempt's swapfile, mounts and LUKS mapping still up.
swapoff /mnt/var/tmp/install.swap 2>/dev/null || true
umount -R /mnt 2>/dev/null || true
cryptsetup close "$mapper" 2>/dev/null || true

say "lattice $LATTICE_VERSION installer"

### NETWORK ###
# Everything past here downloads: the repo, and the system from the binary caches. The radio
# can come up blocked or off, which leaves nmtui with no networks to list.
rfkill unblock wifi 2>/dev/null || true
nmcli radio wifi on 2>/dev/null || true
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
# modules/personal is the author's own setup on top of the distro: the account and its
# password, the time zone, tailscale, Home Assistant and the rest, most of it unlocked by
# sops. A machine of theirs takes it, and then the account, time zone and where the flake
# lives are personal's, not questions here.
personal=""
dotfiles=""
if [[ -d "$work/modules/personal" ]]; then
    read -rp "Install the personal setup in modules/personal (secrets, tailscale, Home Assistant)? [Y/n]: " answer
    [[ "${answer,,}" == n* ]] || personal=1
fi

# One "name = value;" out of a Nix file, for the few values the installer needs to know
# before anything evaluates. Empty if the file no longer says it that way.
nix_string() {
    sed -n "s/^ *$1 = \"\\([^\"]*\\)\";/\\1/p" "$2" | head -n 1
}

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

if [[ -n "$personal" ]]; then
    personal_nix="$work/modules/personal/default.nix"
    user="$(nix_string name "$personal_nix")"
    tz="$(nix_string time.timeZone "$personal_nix")"
    flake_dir="$(nix_string programs.nh.flake "$personal_nix")"
    dotfiles="$(nix_string dotfiles "$personal_nix")"
    [[ -n "$user" && -n "$tz" && -n "$flake_dir" ]] ||
        die "modules/personal/default.nix changed shape; can't read the user, time zone and flake path from it"
    echo "The account ($user), its password and the time zone ($tz) come from modules/personal."
fi

while [[ -z "$personal" ]]; do
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

if [[ -z "$personal" ]]; then
    password="$(ask_secret "Password for $user")"
    password_hash="$(mkpasswd --method=yescrypt --stdin <<<"$password")"
    unset password
fi

echo "The disk is encrypted, and asks for its own passphrase at every boot."
passphrase="$(ask_secret "Disk passphrase")"

while [[ -z "$personal" ]]; do
    read -rp "Time zone [America/New_York]: " tz
    tz="${tz:-America/New_York}"
    if [[ -f "/etc/zoneinfo/$tz" ]]; then
        break
    fi
    echo "no such zone; they look like Europe/Berlin (ls /etc/zoneinfo)"
done

if [[ -z "$personal" ]]; then
    read -rp "A git URL for your dotfiles, cloned to ~/.dotfiles (blank for none): " dotfiles
fi

### THE SECRETS KEY ###
# Personal's secrets open with each host's own SSH host key. This one is new, so it has to
# be added to them, and that takes the admin age key (see .sops.yaml): read off a USB stick
# into RAM, used for that one step, and never written to the new disk.
age_key=/tmp/lattice-age-key
age_key_name=sops-age-keys.txt
trap 'rm -f "$age_key"' EXIT

# Looks for the key at the top of every filesystem not on the Mac's own disk.
find_age_key() {
    local own dev dir found=1
    own="$(lsblk -no PKNAME "$esp")"
    dir="$(mktemp -d)"
    while read -r dev fstype parent; do
        [[ -n "$fstype" && "$fstype" != crypto_LUKS && "$parent" != "$own" ]] || continue
        mount -o ro "/dev/$dev" "$dir" 2>/dev/null || continue
        if [[ -f "$dir/$age_key_name" ]]; then
            install -m 0600 "$dir/$age_key_name" "$age_key"
            found=0
        fi
        umount "$dir"
        ((found)) || break
    done < <(lsblk -rno NAME,FSTYPE,PKNAME)
    rmdir "$dir"
    return "$found"
}

if [[ -n "$personal" ]]; then
    while :; do
        if ! find_age_key; then
            echo "Plug in the drive with $age_key_name at its top and press Enter, or type the key file's path:"
            read -r path
            [[ -z "$path" ]] && continue
            [[ -f "$path" ]] || {
                echo "no such file"
                continue
            }
            install -m 0600 "$path" "$age_key"
        fi
        if SOPS_AGE_KEY_FILE="$age_key" sops decrypt "$work/secrets/common.yaml" >/dev/null 2>&1; then
            echo "Found the admin key; it opens the secrets."
            break
        fi
        rm -f "$age_key"
        echo "That key doesn't open secrets/common.yaml. Is it the admin key from .sops.yaml?"
        read -rp "Press Enter to look again." _
    done
fi

### WHERE ###
# The disk is the one holding the ESP the Asahi installer made. lattice goes into the free
# space it left, or replaces a Linux partition from an earlier install. Apple's partitions,
# the ESP and the GPT itself are never touched: damaging those can leave the Mac unbootable.
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
  personal   $([[ -n "$personal" ]] && echo "yes, the host added to the secrets" || echo no)
  dotfiles   ${dotfiles:-none}
  disk       $disk
  into       ${labels[$((choice - 1))]}
  boot       $esp (the Asahi ESP, kept as it is)

$( [[ "$target" == free ]] || echo "Everything on $target will be lost. ")Nothing has been written yet.
EOF
read -rp "Type yes to install: " answer
[[ "$answer" == yes ]] || die "stopped; nothing was changed"

# /tmp is gone after a reboot, so a failed run also leaves its log on the ESP: FAT, so
# another machine or macOS can read it off the disk too.
save_log() {
    local dir=/mnt/boot
    mountpoint -q "$dir" || {
        dir="$(mktemp -d)"
        mount "$esp" "$dir" || return
    }
    cp "$log" "$dir/lattice-install.log" && sync && echo "A copy is on the ESP ($esp) as lattice-install.log." >&2
    [[ "$dir" == /mnt/boot ]] || { umount "$dir" && rmdir "$dir"; }
}
exec > >(tee -a "$log") 2>&1
trap 'echo; echo "lattice-install failed; the log is $log. Running it again starts over." >&2; save_log' ERR

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
# 4 KiB blocks, so the disk mounts on any kernel, the 4 KiB-page ones a rescue might boot
# included; the 16 KiB-page Asahi kernel handles them too. mkfs confirms that from
# /sys/fs/btrfs, which only exists once the module is in, and warns that the size may not
# mount until then.
modprobe btrfs
mkfs.btrfs -q -f -L lattice --sectorsize 4096 "/dev/mapper/$mapper"
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
# Where programs.nh.flake will say it is: personal names its own place, the distro ~/lattice.
flake_dir="${flake_dir:-/home/$user/lattice}"
repo="/mnt$flake_dir"
mkdir -p "$(dirname "$repo")"
cp -a "$work" "$repo"

hostdir="$repo/hosts/$host"
mkdir "$hostdir"
nixos-generate-config --root /mnt --show-hardware-config >"$hostdir/hardware-configuration.nix"
# With personal, the account and time zone are its own, and saying them here as well would
# be two definitions of one option, so those lines go and the import comes in instead.
if [[ -n "$personal" ]]; then
    edits=(
        -e '/time.timeZone = /d'
        -e '/# No hashedPasswordFile/,/lattice.user.name = /d'
        -e 's|^\( *\)\.\./\.\./modules/nixos$|&\n\1../../modules/personal|'
    )
    wants=("\"$host\"" "\"$firmware_hash\"" "../../modules/personal")
else
    edits=(
        -e "s|time.timeZone = \".*\";|time.timeZone = \"$tz\";|"
        -e "s|lattice.user.name = \".*\";|lattice.user.name = \"$user\";|"
    )
    wants=("\"$host\"" "\"$tz\"" "\"$user\"" "\"$firmware_hash\"")
fi
{
    echo "# $host, installed by lattice-install $LATTICE_VERSION on $(date +%F)."
    sed -e '1,3d' \
        -e "s|networking.hostName = \".*\";|networking.hostName = \"$host\";|" \
        -e "s|lattice.asahi.firmwareHash = \".*\";|lattice.asahi.firmwareHash = \"$firmware_hash\";|" \
        "${edits[@]}" \
        "$repo/hosts/macbook/default.nix" | cat -s
} >"$hostdir/default.nix"
for want in "${wants[@]}"; do
    grep -qF "$want" "$hostdir/default.nix" || die "hosts/macbook/default.nix changed shape; $want did not make it into hosts/$host"
done
# A flake sees only what git tracks.
git -C "$repo" add "hosts/$host"

# The new host key, made now rather than at first boot so the secrets can be opened to it
# before the install needs them: the account's password is one. Added to .sops.yaml under
# the host's name, then every secret re-encrypted to the new set of keys.
if [[ -n "$personal" ]]; then
    say "Adding $host to the secrets"
    install -d -m 0755 /mnt/etc/ssh
    ssh-keygen -q -t ed25519 -N "" -C "root@$host" -f /mnt/etc/ssh/ssh_host_ed25519_key
    recipient="$(ssh-to-age </mnt/etc/ssh/ssh_host_ed25519_key.pub)"
    anchor="host_${host//-/_}"
    # After the last key, and after the last key named in a rule, matching its indent.
    awk -v anchor="$anchor" -v recipient="$recipient" '
        NR == FNR {
            if ($0 ~ /^  - &/) k = FNR
            if ($0 ~ /^ *- \*/) { r = FNR; indent = $0; sub(/-.*/, "", indent) }
            next
        }
        { print }
        FNR == k { print "  - &" anchor " " recipient }
        FNR == r { print indent "- *" anchor }
    ' "$repo/.sops.yaml" "$repo/.sops.yaml" >"$repo/.sops.yaml.new"
    mv "$repo/.sops.yaml.new" "$repo/.sops.yaml"
    grep -qF "$recipient" "$repo/.sops.yaml" || die ".sops.yaml changed shape; couldn't add $host to it"
    (cd "$repo" && SOPS_AGE_KEY_FILE="$age_key" sops updatekeys --yes secrets/common.yaml)
    rm -f "$age_key"
    git -C "$repo" add .sops.yaml secrets/common.yaml
fi

### INSTALL ###
# Kernel builds and the like go to the new disk, not to the live system's RAM-backed /tmp.
say "Installing. Most of it downloads; anything not in the caches is built here, which can take a while."
mkdir -p /mnt/var/tmp
# The live system has no swap, and the kernel build below can want more than a small Mac
# has. A swapfile on the new disk for the length of the install; the installed system does
# without one, as hosts/macbook says.
swapfile=/mnt/var/tmp/install.swap
btrfs -q filesystem mkswapfile --size 8g "$swapfile"
swapon "$swapfile"

# Downloaded in batches first, each by a nix that exits after it. Substituting into another
# root's store (--store /mnt, which is what nixos-install does) costs nix 2.34 about 2 MiB
# that it never gives back for every path: the ~8000 of a lattice system came to over 15
# GiB, and the OOM killer ended the install in an 8 GiB VM even with the swap above. Measured
# the same on the Mac with http2 off, so it is the chroot store, not the network.
system="$repo#nixosConfigurations.$host.config.system.build.toplevel"
mapfile -t fetch < <(
    nix build --store /mnt --dry-run "$system" 2>&1 |
        awk '/will be fetched/ { f = 1; next } /will be built/ { f = 0 } f && $1 ~ /^\/nix\/store\// { print $1 }'
)
batch=300
for ((i = 0; i < ${#fetch[@]}; i += batch)); do
    echo "downloading $((i + 1))-$((i + batch < ${#fetch[@]} ? i + batch : ${#fetch[@]})) of ${#fetch[@]}"
    nix build --store /mnt --no-link "${fetch[@]:i:batch}"
done

TMPDIR=/mnt/var/tmp nixos-install --root /mnt --flake "$repo#$host" --no-root-passwd --no-channel-copy
swapoff "$swapfile"
rm "$swapfile"

# The network joined above, so the first login is online: the Flatpaks and the rest of what
# a session fetches at start need it. NetworkManager keeps its profiles as keyfiles whatever
# the Wi-Fi backend, so the live system's iwd and the installed one's wpa_supplicant read
# the same files.
# A glob rather than compgen, which the non-interactive bash of writeShellApplication lacks.
connections=(/etc/NetworkManager/system-connections/*)
if [[ -e "${connections[0]}" ]]; then
    say "Keeping the network connection"
    install -d -m 0700 /mnt/etc/NetworkManager/system-connections
    cp -a /etc/NetworkManager/system-connections/. /mnt/etc/NetworkManager/system-connections/
fi

say "Setting up $user"
# With personal, the password is in the secrets and the install has already set it.
if [[ -z "$personal" ]]; then
    printf '%s:%s\n' "$user" "$password_hash" | nixos-enter --root /mnt -c "chpasswd -e"
fi
# Cloned from here rather than at first login, which may be offline. Their dotfiles.sh runs
# against the new home; Stow makes relative links, so they resolve the same after the
# reboot. A failure here leaves the install standing: it is one clone to redo by hand.
if [[ -n "${dotfiles:-}" ]]; then
    say "Setting up the dotfiles"
    home="/mnt/home/$user"
    if git clone -q "$dotfiles" "$home/.dotfiles"; then
        # Stow links a whole directory when nothing else is in it yet, and in an empty home
        # that made ~/.local itself a link into the repo, so every app's state landed in it.
        # Made first, the directories stay real and only the files are linked.
        mkdir -p "$home/.config" "$home/.local/share/applications" "$home/.local/state"
        if [[ -x "$home/.dotfiles/dotfiles.sh" ]]; then
            HOME="$home" "$home/.dotfiles/dotfiles.sh" ||
                echo "dotfiles.sh failed; run ~/.dotfiles/dotfiles.sh after logging in"
        fi
    else
        echo "couldn't clone $dotfiles; clone it to ~/.dotfiles after logging in"
    fi
fi
# Everything in the new home is the installer's doing, the flake's parent folders included.
nixos-enter --root /mnt -c "chown -R $user: /home/$user"

cp "$log" /mnt/var/log/lattice-install.log
say "lattice is installed"
cat <<EOF
Take out the stick and reboot. If macOS comes up instead, hold the power button at startup
and pick lattice. The disk passphrase comes first, then the login.

The flake is in ${flake_dir/#\/home\/$user/\~}, with $(
    [[ -n "$personal" ]] && echo "hosts/$host, .sops.yaml and secrets/common.yaml" || echo "hosts/$host"
) staged but not committed: commit and push them, and from then on \`lattice rebuild\` applies
changes.
EOF
