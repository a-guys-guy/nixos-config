{
  pkgs,
  inputs,
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
}
