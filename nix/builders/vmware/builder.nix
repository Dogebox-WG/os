{ pkgs, arch, dbxRelease, ... }:

let
  vmwareFile = pkgs.writeTextFile {
    name = "vmware.nix";
    text = builtins.readFile ./base.nix;
  };

  baseFile = pkgs.writeTextFile {
    name = "base.nix";
    text = builtins.readFile ../../dbx/base.nix;
  };

  dogeboxFile = pkgs.writeTextFile {
    name = "dogebox.nix";
    text = builtins.readFile ../../dbx/dogebox.nix;
  };

  dogeboxdFile = pkgs.writeTextFile {
    name = "dogeboxd.nix";
    text = builtins.readFile ../../dbx/dogeboxd.nix;
  };

  dkmFile = pkgs.writeTextFile {
    name = "dkm.nix";
    text = builtins.readFile ../../dbx/dkm.nix;
  };
in
{
  imports = [ ./base.nix ];

  #vmware.memorySize = 4096;
  vmware.vmDerivationName = "dogebox";
  #vmware.vmName = "Dogebox";
  vmware.vmFileName = "dogebox-${dbxRelease}-${arch}.vmdk";

  system.activationScripts.copyFiles = ''
    mkdir /opt
    echo "vmware" > /opt/build-type
    cp ${vmwareFile} /etc/nixos/configuration.nix
    cp ${baseFile} /etc/nixos/base.nix
    cp ${dogeboxFile} /etc/nixos/dogebox.nix
    cp ${dogeboxdFile} /etc/nixos/dogeboxd.nix
    cp ${dkmFile} /etc/nixos/dkm.nix
  '';
}
