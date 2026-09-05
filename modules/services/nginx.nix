{
  lib,
  config,
  ...
}: {
  services.nginx.enable = true;

  security.acme = {
    acceptTerms = true;
    defaults.email = "jonas@jonbyr.com";
  };

  # Catch-all: the default server for the tailnet HTTP port. Anything that
  # does not hit server_name below (the bare noether.headscale.local name,
  # unknown hosts, missing Host) is dropped here — never leaked to hermes.
  "tailnet-reserved" = {
    listen = [
      {
        addr = config.sys.bindAddress;
        port = 80;
        ssl = false;
      }
    ];
    default = true; # this vhost is the default_server for 100.64.0.5:80
    serverName = "noether.headscale.local"; # reserved — drop, don't serve hermes
    locations."/" = {
      return = "444";
    };
    # no access log: unknown hosts are just dropped
    extraConfig = ''
      error_log /var/log/nginx/hermes_reserved_error.log;
    '';
  };

  networking.firewall.allowedTCPPorts = [80 443];

  nixpkgs.config.allowUnfreePredicate = pkg: true;
}
