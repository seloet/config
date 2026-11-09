# NixOS configuration

Shared NixOS and Home Manager configuration for `desktop`, `laptop`, and `surface`,
with Hyprland and Stylix. Hosts extend `baseSystem` in `flake.nix`; hardware
settings live in `hosts/<host>/`. `installer` is a separate minimal ISO.

## Validate and deploy

New files must be tracked by Git before a Git-backed flake can evaluate them.

```sh
nix flake check --no-build
nixos-rebuild dry-build --flake .#desktop
sudo nixos-rebuild boot --flake .#desktop
```

Use the configuration matching the target machine (`desktop`, `laptop`, or
`surface`), then reboot. Evaluation and dry builds do not prove packages build.
The desktop includes resource-intensive CUDA/source builds.

- Replace the Surface's placeholder filesystem and swap UUIDs before deployment.
- Keep a previous boot generation. If login fails, use Ctrl+Alt+F3 or boot it.
- Test boot, encrypted-root unlock, login, and resume on the actual hardware.
- Preserve the desktop's non-COW, uncompressed Btrfs swapfile. Hibernation is not
  configured by the shared memory policy.

## Maintenance

- Update inputs with `nix flake update`, then validate. Do not bump
  `system.stateVersion` or `home.stateVersion` for routine updates.
- Helium is pinned separately in `users/sevi/browser.nix`; update its version and
  SHA-256 together from [upstream releases](https://github.com/imputnet/helium-linux/releases).
  Helium disables built-in password saving and passkeys.
  Colab compatibility pins are also independent of `flake.lock`.
- The Anki override in `users/sevi/apps.nix` supplies missing offline build
  dependencies. Remove it once nixpkgs supplies them.
- Recheck the VT2 overrides in `modules/core/boot-choreography.nix` after nixpkgs
  updates: greetd's TTY, getty dependencies, and autovt masking must agree.
- `modules/core/memory-and-swap.nix` limits nix-daemon memory; large builds can be
  throttled or killed. Zram is preferred over disk swap, not a guarantee against
  disk I/O or application stalls.
