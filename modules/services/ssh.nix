{
  lib,
  config,
  ...
}: {
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      # Keyboard-interactive (PAM) auth must also be off: with the NixOS default
      # `KbdInteractiveAuthentication yes`, sshd still offers the PAM password path
      # (~4.3k failed attempts/7d from brute-force noise; all accepted logins were
      # publickey-only, but the surface should not exist on a key-only host).
      KbdInteractiveAuthentication = false;
      X11Forwarding = false; # headless server; forwarding is unused attack surface
    };
  };

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  networking.firewall.allowedTCPPorts = [22];
}