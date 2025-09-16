{ lib, devBootloader ? false, ... }:

{
  fileSystems = lib.mkDefault {
    "/" = {
      device = "/dev/disk/by-label/nixos";
      autoResize = true;
      fsType = "ext4";
    };
  };

  boot.loader.grub.enable = lib.mkDefault devBootloader;

  # If we have an existing configuration.nix file, we include that
  # so that any existing machine-specific settings are preserved.
  # These are preserved into /etc/nixos-dev/* so they're not clobbered on rebuild.
  imports = lib.optional (builtins.pathExists "/etc/nixos-dev/configuration.nix") /etc/nixos-dev/configuration.nix;
}
