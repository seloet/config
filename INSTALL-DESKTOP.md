# Desktop — NixOS reinstall guide

Adapted from https://github.com/seloet/config for this machine
(i7-10700KF, RTX 2060, DP-1 VG279QM @240 Hz + HDMI-A-1 ASUS VS247 rotated,
LUKS/btrfs on sda, 3 ext4 data disks).

Verified before handoff: the flake fully evaluates for host `desktop`
(`system.build.toplevel` derivation resolves cleanly, Nix 2.35.2).
The full closure was NOT built here — first `nixos-install` substitutes
from cache and builds whatever is missing.

## What was changed vs upstream seloet/config

| Change | Why |
|---|---|
| Username `severin` → `sevi`, `/home/severin` → `/home/sevi` | Matches this machine's existing `/home/sevi` so all data stays owned |
| `kb_layout ch` → `us`, console keymap `sg` → `us` | Matches current input setup |
| HDMI-A-1 `transform 1` → `3` | Matches the working rotation on this monitor |
| Made LocalAssistant host-selectable and vendored its build source | Keeps it enabled on the laptop without requiring `/home/severin/LocalAssistant` on the desktop |
| Wrote real `hosts/desktop/hardware-configuration.nix` (was non-deployable template) | LUKS UUID, btrfs subvols @/@home/@log/@pkg, EFI UUID, 3 ext4 data disks, Intel microcode, NVIDIA driver |
| Added `users/sevi/nas-mount.nix` | Synology DS214 rclone FUSE mount mirroring `gdrive.nix`; enabled only on the desktop |
| Tailscale | Already enabled upstream (`modules/core/services.nix`) — nothing to add |

1. **Backups** — /home survives (no formatting), but verify:
   `ls /home/sevi` sanity check; sync irreplaceable stuff to NAS/cloud anyway.
2. Confirm SSH keys exist: `ls ~/.ssh`
3. Note your LUKS passphrase — needed at boot AND during install.
4. `~/config` lives on `/home` → survives automatically.

## Install

Boot any recent **NixOS ISO** (USB stick), then:

```bash
# network (eth0 should just work; wifi: use wpa_cli or iwd)

sudo -i

# unlock existing disk — DO NOT FORMAT ANYTHING
cryptsetup open /dev/sda2 root        # enter LUKS passphrase
mount -o subvol=@,compress=zstd /dev/mapper/root /mnt
mount -o subvol=@home,compress=zstd /dev/mapper/root /mnt/home
mkdir -p /mnt/var/{log,cache/pacman/pkg}
mount -o subvol=@log,compress=zstd /dev/mapper/root /mnt/var/log
mount -o subvol=@pkg,compress=zstd /dev/mapper/root /mnt/var/cache/pacman/pkg
mount /dev/sda1 /mnt/boot             # EFI partition (UUID 18AD-C962)

# config is already on /home
cd /mnt/home/sevi/config
git status   # confirm adaptations present

nixos-install --flake /mnt/home/sevi/config#desktop
reboot
```

Note: `llmBackend = "cuda"` builds `beellama-cuda` locally (RTX 2060).
First install downloads tens of GB and may compile for a long time.
For faster bring-up set `llmBackend = "cpu"` in
`hosts/desktop/configuration.nix`, install, then flip back and run:

```bash
sudo nixos-rebuild switch --flake ~/config#desktop
```

## After first boot

```bash
sudo passwd root            # if skipped during install
passwd                      # set your password
sudo tailscale up           # login to tailnet (service already enabled)
rclone config               # remote name "Org" -> Google Drive (gdrive mount)
rclone config               # remote name "nas" -> smb/nfs to DiskStation share
                            #   then: systemctl --user start nas-mount
systemctl --user status gdrive-mount nas-mount
```

- `~/gdrive` and `~/nas` appear once rclone remotes exist (units no-op until
  `~/.config/rclone/rclone.conf` is present).
- Old Omarchy dotfiles in `~/.config` are inert leftovers; delete whenever.
- Git identity include (`~/.config/git/private`) survives on @home.
- LocalAssistant is intentionally disabled for `desktop`; it remains enabled for
  `laptop` through the host-selectable workstation profile.

## Rollback safety

NixOS generations: pick previous generation at the boot menu, or
`nixos-rebuild switch --rollback`.
