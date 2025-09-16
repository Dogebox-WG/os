{
  config,
  lib,
  pkgs,
  dogeboxd,
  devMode,
  ...
}:

{
  environment.systemPackages = [
    pkgs.systemd
    pkgs.nixos-rebuild
    pkgs.parted
    pkgs.util-linux
    pkgs.e2fsprogs
    pkgs.dosfstools
    pkgs.nixos-install-tools
    pkgs.nix
    pkgs.git
    pkgs.libxkbcommon
    pkgs.wirelesstools
    pkgs.wpa_supplicant
  ];

  users.motd = ''
    +===================================================+
    |                                                   |
    |      ____   ___   ____ _____ ____   _____  __     |
    |     |  _ \ / _ \ / ___| ____| __ ) / _ \ \/ /     |
    |     | | | | | | | |  _|  _| |  _ \| | | \  /      |
    |     | |_| | |_| | |_| | |___| |_) | |_| /  \      |
    |     |____/ \___/ \____|_____|____/ \___/_/\_\     |
    |                                                   |
    +===================================================+
  '';

  users.users.dogeboxd = {
    isSystemUser = true;
    group = "dogebox";
    extraGroups = [ ];
  };

  systemd.tmpfiles.rules = [
    "d /opt/dogebox 0700 dogeboxd dogebox -"

    # Create a dev folder, and give both the shibe user and dogebox group write perms.
    "d /opt/dev 0770 shibe dogebox -"
  ];

  systemd.services.dogeboxd = {
    enable = !devMode;
    after = [ "systemd-networkd-wait-online.service" ];
    wants = [ "systemd-networkd-wait-online.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStart = "/run/wrappers/bin/dogeboxd --addr 0.0.0.0 --data /opt/dogebox --nix /opt/dogebox/nix --containerlogdir /opt/dogebox/logs --port 3000 --uiport 8080 --uidir ${dogeboxd}/dpanel/src";
      Restart = "always";
      User = "dogeboxd";
      Group = "dogebox";
      Environment = "PATH=/run/wrappers/bin:${pkgs.wpa_supplicant}/bin:${pkgs.wirelesstools}/bin:${pkgs.libxkbcommon}/bin:${pkgs.git}/bin:${pkgs.nix}/bin:${pkgs.nixos-install-tools}/bin:${pkgs.dosfstools}/bin:${pkgs.e2fsprogs}/bin:${pkgs.parted}/bin:${pkgs.util-linux}/bin:${pkgs.systemd}/bin:${pkgs.nixos-rebuild}/bin:${pkgs.coreutils}/bin:${pkgs.bash}/bin:$PATH";
    };
  };

  networking.firewall.allowedTCPPorts = [
    3000
    8080
  ];

  security.wrappers._dbxroot = {
    source = "${dogeboxd}/dogeboxd/bin/_dbxroot";
    owner = "root";
    group = "root";
    setuid = true;
  };

  # This wrapper is to ensure dogeboxd can listen on port :80
  # for it's internal router. This is never exposed outside the host.
  security.wrappers.dogeboxd = {
    source = "${dogeboxd}/dogeboxd/bin/dogeboxd";
    owner = "dogeboxd";
    group = "dogebox";
    capabilities = "cap_net_bind_service=+ep";
  };

  # This wrapper grants no special powers, but makes the binary
  # available system-wide, so that it can be used by systemd init
  # for checking if containers should start at boot (when not in recovery mode)
  security.wrappers.dbx = {
    source = "${dogeboxd}/dogeboxd/bin/dbx";
    owner = "dogeboxd";
    group = "dogebox";
  };

  # TEMPORARY. Remove this when we can figure out how to point it to _just_ the wrappers?
  security.sudo.extraRules = [
    {
      users = [ "dogeboxd" ];
      commands = [
        {
          command = "${dogeboxd}/bin/_dbxroot";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/run/wrappers/bin/_dbxroot";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];
}
