{
  config,
  pkgs,
  lib,
  nanopc-t6-rk3588-firmware,
  ...
}:

{
  nixpkgs.overlays = lib.mkAfter [
    (import ./arm-trusted-firmware/overlay.nix)
    (import ./optee/overlay.nix)

    (final: super: {
      makeModulesClosure = x: super.makeModulesClosure (x // { allowMissing = true; });

      optee-os-rockchip-rk3588 = final.buildOptee {
        platform = "rockchip-rk3588";
        version = "4.6.0";
        src = final.fetchFromGitHub {
          owner = "OP-TEE";
          repo = "optee_os";
          rev = "4.6.0";
          hash = "sha256-4z706DNfZE+CAPOa362CNSFhAN1KaNyKcI9C7+MRccs=";
        };
        extraMakeFlags = [
          "CFG_TEE_CORE_LOG_LEVEL=0"
          "CFG_ATTESTATION_PTA=y"
          "CFG_ATTESTATION_PTA_KEY_SIZE=1024"
          "CFG_WITH_USER_TA=y"
          "CFG_WITH_SOFTWARE_PRNG=n"
        ];
      };

      optee-client = super.optee-client.overrideAttrs (old: {
        version = "4.6.0";
        src = final.fetchFromGitHub {
          owner = "OP-TEE";
          repo = "optee_client";
          rev = "4.6.0";
          hash = "sha256-hHEIn0WU4XfqwZbOdg9kwSDxDcvK7Tvxtelamfc3IRM=";
        };
      });

      armTrustedFirmwareRK3588 = super.armTrustedFirmwareRK3588.overrideAttrs (old: {
        prePatch = ''
          sed -i 's/#define FDT_BUFFER_SIZE 0x20000/#define FDT_BUFFER_SIZE 0x60000/g' \
            plat/rockchip/common/params_setup.c
        '';
        makeFlags = old.makeFlags ++ [
          "SPD=opteed"
          "LOG_LEVEL=40"
          "bl31"
        ];
      });

      ubootNanoPCT6 = super.buildUBoot {
        defconfig = "nanopc-t6-rk3588_defconfig";
        extraMeta.platforms = [ "aarch64-linux" ];
        extraMakeFlags = [
          "BL31=${pkgs.armTrustedFirmwareRK3588}/bl31.elf"
          "ROCKCHIP_TPL=${pkgs.rkbin.TPL_RK3588}"
          "TEE=${final.optee-os-rockchip-rk3588}/tee.bin"
        ];
        filesToInstall = [
          "u-boot.itb"
          "idbloader.img"
          "u-boot-rockchip.bin"
          "u-boot-rockchip-spi.bin"
        ];
      };
    })
  ];

  # Show everything in the tty console instead of serial.
  boot.kernelParams = [ "console=tty1" ];

  # Use the extlinux boot loader. (NixOS wants to enable GRUB by default)
  boot.loader.grub.enable = false;
  # Enables the generation of /boot/extlinux/extlinux.conf
  boot.loader.generic-extlinux-compatible.enable = true;
  boot.loader.timeout = 1;

  boot.kernelPackages = pkgs.linuxPackagesFor (
    pkgs.linux_6_17.override {
      argsOverride = rec {
        configfile = ./nanopc-T6_linux_defconfig;
      };
    }
  );
  # boot.kernelPackages =
  #   let
  #     linux_rk3588_pkg =
  #       {
  #         fetchFromGitHub,
  #         linuxManualConfig,
  #         ubootTools,
  #         ...
  #       }:
  #       (linuxManualConfig rec {
  #         modDirVersion = "6.1.57";
  #         version = modDirVersion;

  #         src = fetchFromGitHub {
  #           owner = "friendlyarm";
  #           repo = "kernel-rockchip";
  #           rev = "85d0764ec61ebfab6b0d9f6c65f2290068a46fa1";
  #           hash = "sha256-oGMx0EYfPQb8XxzObs8CXgXS/Q9pE1O5/fP7/ehRUDA=";
  #         };

  #         configfile = ./nanopc-T6_linux_defconfig;
  #         allowImportFromDerivation = true;
  #       }).overrideAttrs
  #         (old: {
  #           nativeBuildInputs = old.nativeBuildInputs ++ [ ubootTools ];
  #           prePatch = ''
  #             patch -p1 < ${./rk3588-nanopi6-common.dtsi.patch}
  #             cp arch/arm64/boot/dts/rockchip/rk3588-nanopi6-rev01.dts arch/arm64/boot/dts/rockchip/rk3588-nanopc-t6.dts
  #             cp arch/arm64/boot/dts/rockchip/rk3588-nanopi6-rev07.dts arch/arm64/boot/dts/rockchip/rk3588-nanopc-t6-lts.dts
  #             sed -i "s/rk3588-nanopi6-rev0a.dtb/rk3588-nanopi6-rev0a.dtb\ rk3588-nanopc-t6.dtb\ rk3588-nanopc-t6-lts.dtb/" arch/arm64/boot/dts/rockchip/Makefile
  #           '';
  #         });
  #     linux_rk3588 = pkgs.callPackage linux_rk3588_pkg { };
  #   in
  #   pkgs.recurseIntoAttrs (pkgs.linuxPackagesFor linux_rk3588);
  boot.kernelPatches = [
    {
      name = "rk3588-nanopc-t6.dtsi.patch";
      patch = ./rk3588-nanopc-t6.dtsi.patch;
    }
  ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "usbhid"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [
    "rtw88_8822ce"
    "rtw88_pci"
    "rtw88_core"
  ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  environment.systemPackages = with pkgs; [
    avahi
    cloud-utils
    parted
    screen
    wpa_supplicant
    ubootNanoPCT6
  ];

  environment.etc."uboot".source = pkgs.ubootNanoPCT6;

  # Initial hostName for the box to respond to dogebox.local for first boot and installation steps.
  # Will be replaced by dogeboxd configuration
  networking.hostName = lib.mkDefault ("dogebox");
  services.avahi = {
    nssmdns4 = true;
    nssmdns6 = true;

    enable = true;
    reflector = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
      userServices = true;
    };
  };

  # Setup a Wi-Fi Access Point for initial configuration.
  # This allows a user to configure the dogebox by only plugging in power
  # Caveat: Upon configuring the OS with a proper Wi-Fi network, the user will
  # have to reconnect to that network and manually reload the dpanel page.
  networking.wireless.enable = true;

  services.create_ap = {
    enable = true;
    settings = {
      INTERNET_IFACE = "lo";
      WIFI_IFACE = "wlP3p49s0";
      SSID = "Dogebox";
      PASSPHRASE = "SuchPass";
    };
  };

  networking.wireless.interfaces = [ "wlP3p49s0" ];

  systemd.services.resizerootfs = {
    description = "Expands root filesystem of boot device on first boot";
    unitConfig = {
      type = "oneshot";
      after = [ "sysinit.target" ];
    };
    script = ''
      if [ ! -e /etc/fs.resized ];
        then
          echo "Expanding root filesystem . . ."
          PATH=$PATH:/run/current-system/sw/bin/
          ROOT_PART=$(basename "$(findmnt -c -n -o SOURCE /)")
          ROOT_PART_NUMBER=$(cat /sys/class/block/$ROOT_PART/partition)
          ROOT_DISK=$(basename "$(readlink -f "/sys/class/block/$ROOT_PART/..")")
          growpart /dev/"$ROOT_DISK" "$ROOT_PART_NUMBER" || if [ $? == 2 ]; then echo "Error with growpart"; exit 2; fi
          partprobe
          resize2fs /dev/"$ROOT_PART"
          touch /etc/fs.resized
        fi
    '';
    wantedBy = [
      "basic.target"
      "runOnceOnFirstBoot.service"
    ];
  };

  services.pcscd.enable = true;
  services.udev.packages = [ pkgs.yubikey-personalization ];
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", GROUP="69", MODE="0660"
    ACTION=="add", KERNEL=="hidraw*", GROUP="69", MODE="0660"
  '';

  system.activationScripts.rk3588-firmware = ''
    mkdir -p /etc/firmware
    mkdir -p /lib/firmware
    mkdir -p /system

    for i in /etc/firmware /lib/firmware /system;
    do
      [ -L $i ] && echo "Removing old symlink $i" && rm $i
      [ -e $i ] && echo "Moving $i out of the way" && mv $i $i.`date -I`
    done
    echo "Adding new firmware symlinks"
    ln -sf ${nanopc-t6-rk3588-firmware}/etc/firmware/ /etc/firmware
    ln -sf ${nanopc-t6-rk3588-firmware}/lib/firmware/ /lib/firmware
    ln -sf ${nanopc-t6-rk3588-firmware}/system/ /system
  '';
}
