{ lib, pkgs, ... }:

{
  imports =
    [
      ./dogebox.nix
    ]
    ++ lib.optionals (builtins.pathExists "/etc/nixos/hardware-configuration.nix") [
      /etc/nixos/hardware-configuration.nix
    ];

  nix.settings = {
    auto-optimise-store = false;
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    require-sigs = true;
    sandbox = true;
    sandbox-fallback = false;
    substituters = [
      "https://cache.nixos.org/"
      "https://dbx.nix.dogecoin.org"
    ];
    system-features = [
      "nixos-test"
      "benchmark"
      "big-parallel"
      "kvm"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "dbx.nix.dogecoin.org:ODXaHC+9DNqXQ8ZTijaCT4JpieqmOatZeZBbdN51Obc="
    ];
    trusted-users = [
      "root"
      "nixos"
    ];
  };

  # Set your time zone.
  time.timeZone = lib.mkDefault "Australia/Brisbane";

  environment.systemPackages = with pkgs; [
    # Install a few utility packages
    git
    vim
    wget
    wirelesstools
  ];


  # DO NOT CHANGE THIS. EVER. EVEN WHEN UPDATING YOUR SYSTEM PAST 25.05.
  system.stateVersion = "25.05";
}
