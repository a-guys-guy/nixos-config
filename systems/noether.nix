{
  pkgs,
  inputs,
  lib,
  ...
}: {
  imports = [
    ../modules/core.nix
    ../modules/main-user.nix
    ../modules/guy-user.nix
    ../modules/services/ssh.nix
    ../modules/services/tailscale.nix
    ../modules/services/headscale.nix
    ../modules/services/nginx.nix
    ../modules/services/dufs.nix
    ../modules/services/git-server.nix
    ../modules/services/matrix.nix
    ../modules/services/storage-box.nix
    ../modules/services/home-manager.nix
    ../modules/services/hermes-tunnel.nix
    ./noether-hardware.nix
  ];

  main-user.enable = true;
  main-user.userName = "jonas";
  guy-user.enable = true;

  sys = {
    hostName = "noether";
    legacyBios = true;
    bindAddress = "100.64.0.5";
    tailscaleLoginServer = "https://headscale.jonbyr.com";
    autoUpgradeFlake = "/home/jonas/nixos-config/systems/noether";
  };

  hm.profile = ../home/profiles/noether.nix;

  # Allow root's `nixos-upgrade.service` to READ jonas's user-owned git repo (the local flake
  # at /home/jonas/nixos-config). Without this, root's `nix build` on the local-path flake is
  # refused by libgit2's ownership check (safe.directory). Root is only whitelisted for READ:
  # the nightly upgrade no longer updates the lock (see modules/core.nix, flags), so root never
  # writes files owned by jonas here.
  system.activationScripts.gitSafeDir = lib.mkAfter ''
    mkdir -p /root
    ${pkgs.git}/bin/git config --file /root/.gitconfig --list >/dev/null 2>&1 || true
    if ! ${pkgs.git}/bin/git config --file /root/.gitconfig --get-all safe.directory 2>/dev/null | ${pkgs.gnugrep}/bin/grep -qxF "/home/jonas/nixos-config"; then
      ${pkgs.git}/bin/git config --file /root/.gitconfig --add safe.directory /home/jonas/nixos-config
    fi
  '';

  # Two-step nightly upgrade — Step 1: bump the flake lock AS jonas (repo owner) before root
  # switches. `runuser` runs `nix flake update` as jonas, writing flake.lock into his repo and
  # leaving it unstaged (exactly his manual workflow). Step 2 is the autoUpgrade switch as root
  # (see modules/core.nix). The gitSafeDir activation above lets root READ the repo for step 2.
  # Syntax note: nix >= 2.19 removed the legacy `nix flake update <flake-url> <inputs...>`
  # positional form — with it, the path was parsed as an INPUT NAME and nix fell back to cwd
  # ("/"), failing with "path \"/\" does not contain a 'flake.nix'". The flake must be passed
  # via --flake, input names remain positional after it.
  systemd.services.nixos-upgrade.serviceConfig.ExecStartPre = [
    (lib.concatStrings [
      "${pkgs.util-linux}/bin/runuser -u jonas -- "
      "${pkgs.nix}/bin/nix --extra-experimental-features 'nix-command flakes' "
      "flake update --flake /home/jonas/nixos-config/systems/noether "
      "nixpkgs-stable home-manager-stable"
    ])
  ];
}
