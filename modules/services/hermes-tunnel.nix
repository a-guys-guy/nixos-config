{
  lib,
  pkgs,
  config,
  ...
}: let
  # The Hermes instance lives on a separate Ubuntu VPS (guy's hst). Its two
  # HTTP servers — the `serve` backend (JSON-RPC/WebSocket, the desktop app
  # connects here) and the `dashboard` web admin UI — bind 127.0.0.1 there.
  targetHost = "46.225.139.112"; # public IP of the Ubuntu VPS hosting Hermes
  targetUser = "guy"; # account on that VPS
  sshKey = "/home/jonas/.ssh/id_ed25519"; # private key, provisioned out-of-band (0600)

  bind = config.sys.bindAddress; # noether's tailnet address (100.64.0.5)
  fqdn = "hermes.noether.headscale.local"; # MagicDNS name served by this reverse proxy

  # nginx selects a server block by (listen address, port, Host header). Both
  # `serve` and `dashboard` live under the same name but different tailnet
  # ports, so each gets its own virtualHost with its own listen port and its
  # own upstream.

  # Hermes validates the incoming Host header against the hostname it was
  # started with (127.0.0.1, since we keep it loopback-bound there). Browsers
  # on the tailnet send Host: ${fqdn}, so nginx must rewrite the header to a
  # loopback name or the rebinding guard rejects the request with 400. The
  # proxiedHost keeps the upstream's port so the match is exact.
  mkVhost = {
    tailnetPort,
    localPort,
    name,
  }: {
    listen = [
      {
        addr = bind;
        port = tailnetPort;
        ssl = false;
      }
    ];
    serverName = fqdn;
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString localPort}";
      proxyWebsockets = true; # serve is WebSocket; dashboard uses WS too
      extraConfig = ''
        proxy_set_header Host 127.0.0.1:${toString localPort};
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      '';
    };
    extraConfig = ''
      access_log /var/log/nginx/hermes_${name}_access.log;
      error_log /var/log/nginx/hermes_${name}_error.log;
    '';
  };
in {
  # Tunnel: noether (reverse-proxy endpoint) -> Ubuntu VPS (loopback). Local
  # side binds 127.0.0.1 on noether so the forwards never expose anything on
  # the public interface; tailnet reachability is provided by nginx binding
  # the vhosts on the tailnet address instead.
  systemd.services.hermes-tunnel = let
    mkForward = port: "-L 127.0.0.1:${toString port}:127.0.0.1:${toString port}";
  in {
    description = "Loopback SSH tunnel exposing the Hermes VPS's serve/dashboard ports on noether";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target" "tailscaled.service"];
    wants = ["network-online.target" "tailscaled.service"];
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "5";
    };
    script = ''
      exec ${pkgs.openssh}/bin/ssh -NT \
        -o ExitOnForwardFailure=yes \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        -o StrictHostKeyChecking=accept-new \
        -i ${sshKey} \
        ${mkForward 9119} \
        ${mkForward 9120} \
        ${targetUser}@${targetHost}
    '';
  };

  # Reverse proxy on the tailnet interface. Because the hermes vhosts bind a
  # specific address (bind), nginx would otherwise make the first of them the
  # *default* server for that socket and silently serve any Host that reaches
  # the tailnet address — including the reserved bare noether.headscale.local
  # name and unknown names. To keep hermes strictly name-routed and reserve
  # the bare name for a future tailnet-wide overview server, add a catch-all
  # default_server on that port that closes any unmatched request with 444.
  services.nginx.virtualHosts = {
    # Dashboard (web admin UI) on the tailnet's default HTTP port: 80.
    "hermes-dashboard" = mkVhost {
      tailnetPort = 80;
      localPort = 9120;
      name = "dashboard";
    };
    # Backend (`serve`, used by the desktop app) on its own tailnet port. The
    # desktop app connects to http://hermes.noether.headscale.local:9119.
    "hermes-serve" = mkVhost {
      tailnetPort = 9119;
      localPort = 9119;
      name = "serve";
    };
  };

  # MagicDNS name for the reverse proxy. Tailscale/Headscale auto-resolves
  # node hostnames (noether.headscale.local) but not arbitrary subdomains
  # under them, so register the service subdomain explicitly. Under base_domain
  # (headscale.local) the A record propagates to all tailnet clients. The bare
  # noether.headscale.local node name is left untouched, reserving it for a
  # future tailnet-wide overview server on this host.
  services.headscale.settings.dns.extra_records = [
    {
      name = fqdn;
      type = "A";
      value = bind;
    }
  ];
}
