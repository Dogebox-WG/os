{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.05";
    flake-utils = {
      url = "github:numtide/flake-utils";
    };
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dpanel = {
      url = "github:dogebox-wg/dpanel";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    dogeboxd = {
      url = "github:dogebox-wg/dogeboxd";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.dpanel-src.follows = "dpanel";
    };

    dkm = {
      url = "github:dogebox-wg/dkm";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    dogebox-nur-packages = {
      url = "github:dogebox-wg/dogebox-nur-packages";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    {
      self,
      nixpkgs,
      nixos-generators,
      flake-utils,
      ...
    }@inputs:
    let
      dbxRelease = "v0.8.0";

      builderBases = {
        iso = ./nix/builders/iso/base.nix;
        qemu = ./nix/builders/qemu/base.nix;
        nanopc-t6 = ./nix/builders/nanopc-t6/base.nix;
        dev = ./nix/builders/dev/base.nix;
      };

      # This is used to determine if we're in developer mode, which will,
      # among other things, prevent services from automatically starting.
      # This is a fallback for when the nix devMode flag is not set.
      isOSDeveloperMode = builtins.pathExists "/etc/nixos-dev";

      getCopyFlakeScript =
        system: self:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        ''
          mkdir -p /etc/nixos
          ${pkgs.rsync}/bin/rsync -a --delete --exclude='.git' "${self}/" "/etc/nixos/"
        '';

      getSetOptScript =
        builderType: isBaseBuilder:
        ''
          mkdir -p /opt
          echo '${builderType}' > /opt/build-type

          if [ -f /opt/dbx-installed ]; then
            rm -f /opt/ro-media
            touch /opt/rw-media
          else
            rm -f /opt/rw-media
            touch /opt/ro-media
          fi
        '';

      versionScript =
        let
          flakeLock = ./flake.lock;
          flakeLockContent = builtins.readFile flakeLock;
          flakeLockJson = builtins.fromJSON flakeLockContent;

          # We read these from the lock so that we only need to specify the flake
          # name, rather than the full flake URL, which has to contain versioning info.
          dbxdFlake = builtins.getFlake (
            "github:dogebox-wg/dogeboxd/" + flakeLockJson.nodes.dogeboxd.locked.rev
          );
          dpanelFlake = builtins.getFlake (
            "github:dogebox-wg/dpanel/" + flakeLockJson.nodes.dpanel.locked.rev
          );
          dkmFlake = builtins.getFlake ("github:dogebox-wg/dkm/" + flakeLockJson.nodes.dkm.locked.rev);
        in
        ''
          mkdir -p /opt/versioning

          # Write out our pretty release version.
          echo '${dbxRelease}' > /opt/versioning/dbx

          # Dump the entire flake.lock file into the versioning directory.
          echo '${flakeLockContent}' > /opt/versioning/flake.lock

          # Write out info about our flake inputs for easy access.
          mkdir -p /opt/versioning/dogeboxd
          echo '${dbxdFlake.rev}' > /opt/versioning/dogeboxd/rev
          echo '${dbxdFlake.narHash}' > /opt/versioning/dogeboxd/hash

          mkdir -p /opt/versioning/dkm
          echo '${dkmFlake.rev}' > /opt/versioning/dkm/rev
          echo '${dkmFlake.narHash}' > /opt/versioning/dkm/hash

          mkdir -p /opt/versioning/dpanel
          echo '${dpanelFlake.rev}' > /opt/versioning/dpanel/rev
          echo '${dpanelFlake.narHash}' > /opt/versioning/dpanel/hash
        '';

      dbxEntryModule = ./nix/dbx/base.nix;
      commonModule = ./nix/os/common.nix;

      mkConfigModules =
        {
          system,
          builderType,
          isBaseBuilder,
        }:
        [
          (builderBases.${builderType} or (throw "Unsupported builderType: ${builderType}"))
          commonModule
          dbxEntryModule
          (
            { ... }:
            {
              system.activationScripts.copyFlake = getCopyFlakeScript system self;
              system.activationScripts.setOpt = getSetOptScript builderType isBaseBuilder;
              system.activationScripts.versioning = versionScript;
            }
          )
        ];

      getSpecialArgs = arch: system: builderType: devMode: devBootloader: {
        inherit
          inputs
          dbxRelease
          builderType
          arch
          devMode
          devBootloader
          ;

        # These are the built packages, rather than the raw sources.
        dkm = inputs.dkm.packages.${system}.default;
        dogeboxd = inputs.dogeboxd.packages.${system}.default;

        # Explicitly only pass the rk3588 firmware for the nanopc-t6 builder.
        nanopc-t6-rk3588-firmware = inputs.dogebox-nur-packages.legacyPackages.${system}.rk3588-firmware;
      };

      # This is exported as a library function, that is consumed by our
      # dogebox-wg/dev flake to allow easier development. There's things here
      # that are passed-in/available that our normal production flake doesn't use.
      mkNixosSystem =
        { 
          system,
          builderType,
          devMode ? isOSDeveloperMode,
          devBootloader ? false
        }:
        let
          arch = nixpkgs.lib.strings.removeSuffix "-linux" system;
          isBaseBuilder = false;
        in
        nixpkgs.lib.nixosSystem {
          inherit system;
          modules = mkConfigModules { inherit system builderType isBaseBuilder; };
          specialArgs = getSpecialArgs arch system builderType devMode devBootloader;
        };

      base =
        arch: builderType: builderSpecificModule: format:
        let
          system = arch + "-linux";
          isBaseBuilder = false;
          devMode = isOSDeveloperMode;
          devBootloader = false;
        in
        nixos-generators.nixosGenerate {
          inherit system format;
          modules = [
            builderSpecificModule
          ] ++ (mkConfigModules { inherit system builderType isBaseBuilder; });
          specialArgs = getSpecialArgs arch system builderType devMode devBootloader;
        };

      ## Development Scripts & tools below this point.

      mkDevShell =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        pkgs.mkShell {
          buildInputs = [
            pkgs.gnumake
            pkgs.nixos-generators
            pkgs.swig
            pkgs.git
            pkgs.parted
            pkgs.btrfs-progs
            pkgs.e2fsprogs
            pkgs.rsync
            pkgs.wget
            pkgs.simg2img
            pkgs.exfat
            pkgs.exfatprogs
          ];
        };

      qemu-aarch64 = base "aarch64" "qemu" ./nix/builders/qemu/builder.nix "qcow";

      getLaunchAArch64Script =
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        pkgs.writeShellApplication {
          name = "launch";
          text = ''
            temp_qcow2=$(mktemp -d)/nixos.qcow2

            cp ${qemu-aarch64}/nixos.qcow2 "''${temp_qcow2}"
            chmod 777 "''${temp_qcow2}"

            ${pkgs.qemu}/bin/qemu-system-aarch64 \
              -machine virt,highmem=off \
              -cpu cortex-a72 \
              -m 2048 \
              -bios /opt/homebrew/share/qemu/edk2-aarch64-code.fd \
              -drive if=none,file="''${temp_qcow2}",format=qcow2,id=hd \
              -device virtio-blk-device,drive=hd \
              -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::3000-:3000,hostfwd=tcp::8080-:8080 \
              -device virtio-net-device,netdev=net0 \
              -device virtio-serial-device \
              -chardev vc,id=virtcon \
              -device virtconsole,chardev=virtcon

            rm "''${temp_qcow2}"
          '';
        };

      getBuildWithDevOverridesScript =
        system: target:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        pkgs.writeShellApplication {
          name = "build-with-dev-overrides";
          text = ''
            nix build .#packages.${system}.${target} \
              -L \
              --print-out-paths \
              --override-input dogeboxd "path:$(realpath ../dogeboxd)" \
              --override-input dpanel "path:$(realpath ../dpanel)" \
              --override-input dkm "path:$(realpath ../dkm)"

            # This overrides the current OS lockfile, so explicitly git revert that.
            ${pkgs.git}/bin/git checkout -- flake.lock
          '';
        };

      getSwitchRemoteHostScript = system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          target = builtins.getEnv "TARGET";
        in
        pkgs.writeShellApplication {
          name = "switch-remote-host";
          text = ''
            # shellcheck disable=SC2050
            if [ "${target}" == "" ]; then
              echo "TARGET is not set, or '--impure' was not passed to 'nix run'"
              exit 1
            fi

            # Get the stuff we need to be able to build the flake.
            TYPE=$(ssh shibe@${target} 'cat /opt/build-type')
            ARCH=$(ssh shibe@${target} 'uname -m')
            FLAKE="$TYPE-$ARCH"

            echo "Determined flake target: $FLAKE"

            # This is consumed by dogebox.nix to include the remote
            # dogebox.nix file locally during evaluation.
            REMOTE_REBUILD_DOGEBOX_DIRECTORY=$(mktemp -d)
            export REMOTE_REBUILD_DOGEBOX_DIRECTORY

            # Copy the target dogebox/nix directory to our tmpdir, so it can be included in our flake.
            scp -r shibe@${target}:/opt/dogebox/nix/* "''${REMOTE_REBUILD_DOGEBOX_DIRECTORY}"
            echo "Copied target dogebox/nix directory to: $REMOTE_REBUILD_DOGEBOX_DIRECTORY"

            nixos-rebuild switch \
              --flake .#dogeboxos-"$FLAKE" \
              --target-host shibe@${target} \
              --build-host shibe@${target} \
              --use-remote-sudo \
              --fast \
              --impure \
              --override-input dpanel "path:$(realpath ../dpanel)" \
              --override-input dkm "path:$(realpath ../dkm)" \
              --override-input dogeboxd "path:$(realpath ../dogeboxd)"
          '';
        };

      devSupportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      devForAllSystems = nixpkgs.lib.genAttrs devSupportedSystems;
    in
    {
      lib = {
        inherit mkNixosSystem;
      };

      packages = {
        aarch64-linux = {
          t6 = base "aarch64" "nanopc-t6" ./nix/builders/nanopc-t6/builder.nix "raw";
          iso = base "aarch64" "iso" ./nix/builders/iso/builder.nix "iso";
          qemu = qemu-aarch64;
        };
        x86_64-linux = {
          iso = base "x86_64" "iso" ./nix/builders/iso/builder.nix "iso";
          qemu = base "x86_64" "qemu" ./nix/builders/qemu/builder.nix "qcow";
        };
      };

      nixosConfigurations = {
        dogeboxos-iso-x86_64 = mkNixosSystem {
          system = "x86_64-linux";
          builderType = "iso";
        };
        dogeboxos-iso-aarch64 = mkNixosSystem {
          system = "aarch64-linux";
          builderType = "iso";
        };
        dogeboxos-qemu-x86_64 = mkNixosSystem {
          system = "x86_64-linux";
          builderType = "qemu";
        };
        dogeboxos-qemu-aarch64 = mkNixosSystem {
          system = "aarch64-linux";
          builderType = "qemu";
        };
        dogeboxos-nanopc-t6-aarch64 = mkNixosSystem {
          system = "aarch64-linux";
          builderType = "nanopc-t6";
        };

        dogeboxos-dev-aarch64 = mkNixosSystem {
          system = "aarch64-linux";
          builderType = "dev";
        };

        dogeboxos-dev-x86_64 = mkNixosSystem {
          system = "x86_64-linux";
          builderType = "dev";
        };

      };

      devShells = devForAllSystems (system: {
        default = mkDevShell system;
      });

      apps = {
        aarch64-linux = {
          launch = {
            type = "app";
            program = "${getLaunchAArch64Script "aarch64-linux"}/bin/launch";
          };

          "dev-iso" = {
            type = "app";
            program = "${getBuildWithDevOverridesScript "aarch64-linux" "iso"}/bin/build-with-dev-overrides";
          };

          "dev-t6" = {
            type = "app";
            program = "${getBuildWithDevOverridesScript "aarch64-linux" "t6"}/bin/build-with-dev-overrides";
          };

          "dev-qemu" = {
            type = "app";
            program = "${getBuildWithDevOverridesScript "aarch64-linux" "qemu"}/bin/build-with-dev-overrides";
          };

          "switch-remote-host" = {
            type = "app";
            program = "${getSwitchRemoteHostScript "aarch64-linux"}/bin/switch-remote-host";
          };
        };
      };

      formatter = devForAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt-rfc-style);

      checks = devForAllSystems (system: {
        pre-commit-check = inputs.pre-commit-hooks.lib.${system}.run {
          src = ./.;
          hooks = {
            nixfmt-rfc-style.enable = true;
          };
        };
      });
    };
}
