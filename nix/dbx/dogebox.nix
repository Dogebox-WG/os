{ lib, pkgs, devMode, ... }:

let
  remoteRebuildTarget = builtins.getEnv "REMOTE_REBUILD_DOGEBOX_DIRECTORY";
in
{
  imports =
    [
      ./dkm.nix
      ./dogeboxd.nix
    ]
    ++ lib.optionals (builtins.pathExists "/opt/dogebox/nix/dogebox.nix") [
      /opt/dogebox/nix/dogebox.nix
    ]
    ++ lib.optionals (remoteRebuildTarget != "") [
      "${remoteRebuildTarget}/dogebox.nix"
    ];

  users.groups.dogebox = { };

  # Only enable the shibe user if we're not in dev mode.
  users.users = lib.mkIf (!devMode) {
    shibe = {
      isNormalUser = true;
      extraGroups = [ "wheel" "dogebox" ];

      # Temporary, we force the user to change their password on first login.
      password = "suchpass";
    };
  };

  systemd.services.force-password-change = {
    enable = !devMode;
    description = "Force password change for shibe on first boot";
    wantedBy = [ "multi-user.target" ];
    before = [ "getty@tty1.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = let
        script = pkgs.writeScript "force-passwd-change" ''
          #!${pkgs.runtimeShell}
          [ ! -f "/opt/passwd-changed" ] && /run/current-system/sw/bin/chage -d 0 shibe && touch /opt/passwd-changed
          exit 0
          '';
        in "${script}";
    };
  };

  # Disable password auth by default for remote (ssh) connections, this won't effect local logins.
  services.openssh.settings.PasswordAuthentication = false;

  security.sudo.wheelNeedsPassword = false;

  # These will be overridden by the included dogebox.nix file above, but set defaults.

  networking.firewall.enable = true;

  # These are all needed for the oneshot boot process above.
  environment.systemPackages = [
    pkgs.bash
    pkgs.nix
    pkgs.nixos-rebuild
    pkgs.git
    pkgs.wirelesstools
  ];
}
