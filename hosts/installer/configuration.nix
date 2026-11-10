{
  config,
  lib,
  pkgs,
  inputs,
  modulesPath,
  ...
}:

let
  repoUrl = "https://github.com/seloet/config.git";
  bundledConfig = inputs.self.outPath;

  installScript = pkgs.writeShellApplication {
    name = "install-seloet-config";
    runtimeInputs = with pkgs; [
      bash
      coreutils
      util-linux
      gnugrep
      gnused
      gawk
      findutils
      git
      curl
      cryptsetup
      btrfs-progs
      parted
      dosfstools
      e2fsprogs
      networkmanager
      nixos-install-tools
    ];
    text = ''
      set -euo pipefail

      if [[ "''${EUID}" -ne 0 ]]; then
        exec sudo "$0" "$@"
      fi

      REPO_URL="${repoUrl}"
      BUNDLED_CONFIG="${bundledConfig}"

      bold="\033[1m"
      green="\033[1;32m"
      yellow="\033[1;33m"
      red="\033[1;31m"
      reset="\033[0m"

      info() { printf "%b==>%b %b%s%b\n" "$green" "$reset" "$bold" "$*" "$reset"; }
      warn() { printf "%b==> WARNING:%b %s\n" "$yellow" "$reset" "$*"; }
      err()  { printf "%b==> ERROR:%b %s\n" "$red" "$reset" "$*" >&2; }

      partition_path() {
        local disk="$1"
        local part_num="$2"
        if [[ "$disk" =~ [0-9]$ ]]; then
          printf "%sp%s" "$disk" "$part_num"
        else
          printf "%s%s" "$disk" "$part_num"
        fi
      }

      check_network() {
        curl -fsSLI --max-time 5 https://cache.nixos.org >/dev/null 2>&1
      }

      ensure_network() {
        while ! check_network; do
          warn "No internet connection detected."
          printf "  [1] Open NetworkManager TUI (nmtui) to connect Wi-Fi/Ethernet\n"
          printf "  [2] Re-check connection\n"
          printf "  [3] Continue offline (uses bundled flake snapshot)\n"
          read -r -p "Select option [1]: " net_choice
          net_choice="''${net_choice:-1}"
          case "$net_choice" in
            1) nmtui || true ;;
            2) ;;
            3) return 0 ;;
            *) ;;
          esac
        done
        info "Network connectivity verified."
      }

      mount_desktop_existing() {
        local luks_uuid="0b75c7f8-d5bd-4025-b7a5-1a76c24b3f1f"
        local efi_uuid="18AD-C962"
        local luks_dev="/dev/disk/by-uuid/''${luks_uuid}"
        local efi_dev="/dev/disk/by-uuid/''${efi_uuid}"

        if [[ ! -e "$luks_dev" ]]; then
          warn "Default desktop LUKS UUID (''${luks_uuid}) not found."
          lsblk -o NAME,SIZE,FSTYPE,UUID,MOUNTPOINTS
          read -r -p "Enter LUKS partition path (e.g. /dev/sda2): " luks_dev
        fi

        if [[ ! -e "$efi_dev" ]]; then
          warn "Default desktop EFI UUID (''${efi_uuid}) not found."
          lsblk -o NAME,SIZE,FSTYPE,UUID,MOUNTPOINTS
          read -r -p "Enter EFI partition path (e.g. /dev/sda1): " efi_dev
        fi

        if [[ ! -e /dev/mapper/root ]]; then
          info "Unlocking LUKS container ''${luks_dev} as 'root'..."
          cryptsetup open "$luks_dev" root
        else
          info "/dev/mapper/root is already unlocked."
        fi

        info "Mounting btrfs subvolumes (@, @home, @log, @pkg) without formatting..."
        mkdir -p /mnt
        if ! mountpoint -q /mnt; then
          mount -o subvol=@,compress=zstd /dev/mapper/root /mnt
        fi
        mkdir -p /mnt/home /mnt/var/log /mnt/var/cache/pacman/pkg /mnt/boot
        mountpoint -q /mnt/home || mount -o subvol=@home,compress=zstd /dev/mapper/root /mnt/home
        mountpoint -q /mnt/var/log || mount -o subvol=@log,compress=zstd /dev/mapper/root /mnt/var/log
        mountpoint -q /mnt/var/cache/pacman/pkg || mount -o subvol=@pkg,compress=zstd /dev/mapper/root /mnt/var/cache/pacman/pkg
        mountpoint -q /mnt/boot || mount "$efi_dev" /mnt/boot

        # Mount optional desktop storage drives if present so systemd/fstab checks succeed cleanly
        declare -A extra_disks=(
          ["/mnt/mnt/storage-120gb"]="/dev/disk/by-uuid/6d1d90a4-0490-42f7-b592-8ab3fae5eba9"
          ["/mnt/mnt/storage-2tb"]="/dev/disk/by-uuid/eea48b21-40d4-4acd-aeaa-03e2f08673fc"
          ["/mnt/mnt/storage"]="/dev/disk/by-uuid/efbf29df-e907-411f-9743-fecbed8492e7"
        )
        for target_dir in "''${!extra_disks[@]}"; do
          local dev="''${extra_disks[$target_dir]}"
          if [[ -e "$dev" ]]; then
            mkdir -p "$target_dir"
            mountpoint -q "$target_dir" || mount "$dev" "$target_dir"
          fi
        done
      }

      wipe_and_partition_disk() {
        info "Available disks:"
        lsblk -d -o NAME,SIZE,MODEL,TYPE
        echo
        read -r -p "Enter target disk to WIPE (e.g. /dev/nvme0n1 or /dev/sda): " disk
        if [[ ! -b "$disk" ]]; then
          err "Block device ''${disk} does not exist."
          exit 1
        fi

        read -r -p "Swap size in GiB (0 for no swap) [8]: " swap_gib
        swap_gib="''${swap_gib:-8}"

        warn "ALL DATA ON ''${disk} WILL BE PERMANENTLY ERASED!"
        read -r -p "Type 'wipe ''${disk}' to confirm: " confirm
        if [[ "$confirm" != "wipe ''${disk}" ]]; then
          err "Confirmation did not match. Aborting."
          exit 1
        fi

        info "Partitioning ''${disk}..."
        wipefs -a "$disk"
        parted -s "$disk" -- mklabel gpt
        parted -s "$disk" -- mkpart ESP fat32 1MiB 1025MiB
        parted -s "$disk" -- set 1 esp on

        local efi_part=""
        local swap_part=""
        local root_part=""
        efi_part="$(partition_path "$disk" 1)"

        if [[ "$swap_gib" -gt 0 ]]; then
          local swap_end_mib=$(( 1025 + swap_gib * 1024 ))
          parted -s "$disk" -- mkpart swap linux-swap 1025MiB "''${swap_end_mib}MiB"
          parted -s "$disk" -- mkpart root ext4 "''${swap_end_mib}MiB" 100%
          swap_part="$(partition_path "$disk" 2)"
          root_part="$(partition_path "$disk" 3)"
        else
          parted -s "$disk" -- mkpart root ext4 1025MiB 100%
          root_part="$(partition_path "$disk" 2)"
        fi

        udevadm settle

        info "Formatting partitions..."
        mkfs.fat -F 32 -n BOOT "$efi_part"
        if [[ -n "$swap_part" ]]; then
          mkswap -L swap "$swap_part"
          swapon "$swap_part" || true
        fi
        mkfs.ext4 -F -L nixos "$root_part"

        udevadm settle

        info "Mounting ''${root_part} -> /mnt and ''${efi_part} -> /mnt/boot..."
        mkdir -p /mnt
        mount "$root_part" /mnt
        mkdir -p /mnt/boot
        mount -o umask=0077 "$efi_part" /mnt/boot

        UPDATE_HW_CONFIG=1
      }

      mount_custom_partitions() {
        info "Available partitions:"
        lsblk -o NAME,SIZE,FSTYPE,UUID,LABEL,MOUNTPOINTS
        echo
        read -r -p "Enter root partition (e.g. /dev/nvme0n1p2): " root_part
        if [[ ! -b "$root_part" ]]; then
          err "Partition ''${root_part} does not exist."
          exit 1
        fi
        read -r -p "Format ''${root_part} as ext4? [y/N]: " fmt_root
        if [[ "''${fmt_root,,}" == "y" ]]; then
          mkfs.ext4 -F -L nixos "$root_part"
        fi

        read -r -p "Enter EFI boot partition (e.g. /dev/nvme0n1p1): " efi_part
        if [[ ! -b "$efi_part" ]]; then
          err "Partition ''${efi_part} does not exist."
          exit 1
        fi
        read -r -p "Format ''${efi_part} as FAT32? [y/N]: " fmt_efi
        if [[ "''${fmt_efi,,}" == "y" ]]; then
          mkfs.fat -F 32 -n BOOT "$efi_part"
        fi

        read -r -p "Enter swap partition (leave blank for none): " swap_part
        if [[ -n "$swap_part" ]]; then
          swapon "$swap_part" || true
        fi

        mkdir -p /mnt
        mount "$root_part" /mnt
        mkdir -p /mnt/boot
        mount "$efi_part" /mnt/boot

        read -r -p "Regenerate hardware-configuration.nix for these partitions? [Y/n]: " regen_hw
        if [[ "''${regen_hw:-Y}" =~ ^[Yy]$ ]]; then
          UPDATE_HW_CONFIG=1
        fi
      }

      clear
      printf "%b============================================================%b\n" "$bold" "$reset"
      printf "%b        seloet/config - Interactive NixOS Installer         %b\n" "$bold" "$reset"
      printf "%b        Repository: %s%b\n" "$bold" "$REPO_URL" "$reset"
      printf "%b============================================================%b\n\n" "$bold" "$reset"

      info "Detected block devices:"
      lsblk -o NAME,SIZE,TYPE,FSTYPE,UUID,MOUNTPOINTS
      echo

      ensure_network
      echo

      info "Select target host configuration from flake.nix:"
      printf "  [1] desktop  (user: sevi,    layout: us, LUKS + btrfs @/@home + NVIDIA/CUDA)\n"
      printf "  [2] laptop   (user: severin, layout: ch, ext4 + LocalAssistant + Vulkan)\n"
      printf "  [3] surface  (user: severin, layout: sg, Microsoft Surface Pro Intel)\n"
      printf "  [q] Quit to shell\n"
      read -r -p "Host choice [1]: " host_choice
      host_choice="''${host_choice:-1}"

      case "$host_choice" in
        1|desktop)
          TARGET_HOST="desktop"
          TARGET_USER="sevi"
          ;;
        2|laptop)
          TARGET_HOST="laptop"
          TARGET_USER="severin"
          ;;
        3|surface)
          TARGET_HOST="surface"
          TARGET_USER="severin"
          ;;
        q|Q)
          info "Exiting to shell. Run 'sudo install-seloet-config' anytime to restart."
          exit 0
          ;;
        *)
          err "Invalid selection: ''${host_choice}"
          exit 1
          ;;
      esac

      echo
      UPDATE_HW_CONFIG=0
      if [[ "$TARGET_HOST" == "desktop" ]]; then
        info "Select disk setup mode for 'desktop':"
        printf "  [1] Unlock & mount existing desktop LUKS + btrfs subvolumes (@, @home, @log, @pkg) - preserves /home\n"
        printf "  [2] Wipe and partition a disk fresh (GPT: EFI + swap + ext4)\n"
        printf "  [3] Select and mount existing partitions manually\n"
        printf "  [4] Use /mnt as already mounted\n"
        read -r -p "Disk mode [1]: " disk_mode
        disk_mode="''${disk_mode:-1}"
      else
        info "Select disk setup mode for '''''${TARGET_HOST}''':"
        printf "  [1] Wipe and partition a disk fresh (GPT: EFI + swap + ext4)\n"
        printf "  [2] Select and mount existing partitions manually\n"
        printf "  [3] Use /mnt as already mounted\n"
        read -r -p "Disk mode [1]: " disk_mode
        disk_mode="''${disk_mode:-1}"
        disk_mode=$(( disk_mode + 1 ))
      fi

      case "$disk_mode" in
        1) mount_desktop_existing ;;
        2) wipe_and_partition_disk ;;
        3) mount_custom_partitions ;;
        4)
          if ! mountpoint -q /mnt; then
            err "/mnt is not currently mounted."
            exit 1
          fi
          info "Using existing mounts under /mnt."
          ;;
        *)
          err "Invalid disk mode selection."
          exit 1
          ;;
      esac

      echo
      CONFIG_DIR="/mnt/home/''${TARGET_USER}/config"
      mkdir -p "/mnt/home/''${TARGET_USER}"

      if [[ -d "''${CONFIG_DIR}/.git" ]]; then
        info "Found existing repository at ''${CONFIG_DIR}."
        if check_network; then
          read -r -p "Pull latest changes from ''${REPO_URL}? [Y/n]: " pull_choice
          if [[ "''${pull_choice:-Y}" =~ ^[Yy]$ ]]; then
            if ! (git -C "$CONFIG_DIR" fetch origin && git -C "$CONFIG_DIR" pull --ff-only); then
              warn "Could not fast-forward; keeping local checkout state."
            fi
          fi
        fi
      else
        if [[ -e "$CONFIG_DIR" ]]; then
          backup_dir="''${CONFIG_DIR}.bak.$(date +%s)"
          warn "Moving existing non-git ''${CONFIG_DIR} to ''${backup_dir}"
          mv "$CONFIG_DIR" "$backup_dir"
        fi
        if check_network && git clone "$REPO_URL" "$CONFIG_DIR"; then
          info "Cloned ''${REPO_URL} into ''${CONFIG_DIR}."
        else
          warn "Cloning from GitHub failed or offline; copying bundled flake from ISO..."
          cp -a "$BUNDLED_CONFIG" "$CONFIG_DIR"
          chmod -R u+w "$CONFIG_DIR"
          git -C "$CONFIG_DIR" init -b master >/dev/null 2>&1 || true
          git -C "$CONFIG_DIR" remote add origin "$REPO_URL" >/dev/null 2>&1 || true
        fi
      fi

      if [[ "$UPDATE_HW_CONFIG" -eq 1 ]]; then
        hw_file="''${CONFIG_DIR}/hosts/''${TARGET_HOST}/hardware-configuration.nix"
        info "Generating hardware configuration at ''${hw_file}..."
        nixos-generate-config --root /mnt --show-hardware-config > "$hw_file"
      fi

      CPU_BOOTSTRAP=0
      if [[ "$TARGET_HOST" == "desktop" ]]; then
        echo
        info "Desktop LLM backend option:"
        printf "  [1] Full CUDA build (repo default: builds beellama-cuda & mach1-cuda during install)\n"
        printf "  [2] Fast CPU bootstrap (installs with CPU backend first; switch to CUDA after boot)\n"
        read -r -p "LLM backend mode [1]: " llm_choice
        llm_choice="''${llm_choice:-1}"
        if [[ "$llm_choice" == "2" ]]; then
          CPU_BOOTSTRAP=1
          sed -i 's/llmBackend = "cuda";/llmBackend = "cpu";/' "''${CONFIG_DIR}/hosts/desktop/configuration.nix"
          sed -i 's/mach1Backend = "cuda";/mach1Backend = "cpu";/' "''${CONFIG_DIR}/hosts/desktop/configuration.nix"
        fi
      fi

      echo
      info "Installation summary:"
      printf "  Host:        %s\n" "$TARGET_HOST"
      printf "  User:        %s\n" "$TARGET_USER"
      printf "  Flake path:  %s#%s\n" "$CONFIG_DIR" "$TARGET_HOST"
      echo
      lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS
      echo

      read -r -p "Proceed with nixos-install? [Y/n]: " go_install
      if [[ ! "''${go_install:-Y}" =~ ^[Yy]$ ]]; then
        info "Aborted before nixos-install. Mounts remain at /mnt."
        exit 0
      fi

      info "Running nixos-install --flake ''${CONFIG_DIR}#''${TARGET_HOST}..."
      nixos-install --flake "''${CONFIG_DIR}#''${TARGET_HOST}" --no-root-passwd

      if [[ "$CPU_BOOTSTRAP" -eq 1 ]]; then
        info "Restoring llmBackend/mach1Backend = \"cuda\" in ''${CONFIG_DIR}/hosts/desktop/configuration.nix for post-boot rebuild..."
        sed -i 's/llmBackend = "cpu";/llmBackend = "cuda";/' "''${CONFIG_DIR}/hosts/desktop/configuration.nix"
        sed -i 's/mach1Backend = "cpu";/mach1Backend = "cuda";/' "''${CONFIG_DIR}/hosts/desktop/configuration.nix"
      fi

      info "Fixing ownership of /home/''${TARGET_USER}/config..."
      nixos-enter --root /mnt -c "chown -R ''${TARGET_USER}:''${TARGET_USER} /home/''${TARGET_USER}/config" || true

      echo
      read -r -p "Set or update password for user '''''${TARGET_USER}''' now? [Y/n]: " set_pw
      if [[ "''${set_pw:-Y}" =~ ^[Yy]$ ]]; then
        nixos-enter --root /mnt -c "passwd ''${TARGET_USER}" || true
      fi

      echo
      info "Installation of '''''${TARGET_HOST}''' complete!"
      read -r -p "Reboot now? [y/N]: " do_reboot
      if [[ "''${do_reboot,,}" == "y" ]]; then
        reboot
      fi
    '';
  };
in
{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  networking.hostName = "seloet-installer";
  networking.wireless.enable = lib.mkForce false;

  image.baseName = lib.mkForce "nixos-seloet-installer";
  isoImage.squashfsCompression = "zstd -Xcompression-level 6";

  nix.settings = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  environment.etc."seloet-config".source = bundledConfig;

  # Include flake inputs in the ISO Nix store so flake evaluation works without re-fetching inputs.
  system.extraDependencies = [
    bundledConfig
    inputs.nixpkgs.outPath
    inputs.nixpkgs-kernel.outPath
    inputs.home-manager.outPath
    inputs.noctalia.outPath
    inputs.stylix.outPath
    inputs.herdr.outPath
    inputs.llm-agents.outPath
    inputs.beellama.outPath
    inputs.llama-mach1.outPath
    inputs.nixos-hardware.outPath
  ];

  environment.systemPackages = with pkgs; [
    installScript
    git
    cryptsetup
    btrfs-progs
    parted
    gptfdisk
    dosfstools
    e2fsprogs
    nvme-cli
    pciutils
    usbutils
    curl
    jq
    neovim
  ];

  services.getty.helpLine = lib.mkAfter ''

    Run `sudo install-seloet-config` to launch the interactive seloet/config installer.
  '';

  programs.bash.loginShellInit = ''
    if [[ "$(tty)" == "/dev/tty1" && ! -f /tmp/seloet-installer-autoran ]]; then
      touch /tmp/seloet-installer-autoran
      sudo install-seloet-config || true
    fi
  '';
}
