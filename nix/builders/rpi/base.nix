{ lib, dbxRelease, arch, ... }:

{
  hardware.enableRedistributableFirmware = lib.mkForce true;
  boot.initrd.availableKernelModules = [ "xhci_pci" "usbhid" ];

  fileSystems."/" =
    { device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "ext4";
      options = [ "noatime" ];
    };

  # Need to use extlinux for rpi bootloader.
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;
}
