{
  lib,
  arch,
  self,
  builderType,
  dbxRelease,
  ...
}:

let
  targetToplevel =
    self.nixosConfigurations."dogeboxos-${builderType}-${arch}".config.system.build.toplevel;
in
{
  image.baseName = lib.mkForce "dogebox-${dbxRelease}-${arch}";
  isoImage.prependToMenuLabel = "DogeboxOS (";
  isoImage.appendToMenuLabel = ")";

  # Bake the target system closure into the ISO for offline installs.
  isoImage.storeContents = [ targetToplevel ];

  # Override /run/current-system to point to the target toplevel so the
  # installer's readlink -f /run/current-system resolves to the correct
  # system closure instead of the live ISO's.
  systemd.services.set-target-system = {
    description = "Point /run/current-system at target toplevel";
    wantedBy = [ "multi-user.target" ];
    before = [ "dogeboxd.service" ];
    serviceConfig.Type = "oneshot";
    script = "ln -sfn ${targetToplevel} /run/current-system";
  };
}
