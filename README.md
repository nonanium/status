# Nonanium Status

Live availability and incident reporting for Nonanium and Tensamin services. The Rust backend checks configured URLs every five minutes, verifies HTTP/3 where requested, persists incident history, and pushes updates to the React status page over WebSockets.

Each browser tab shares one connection. It receives a full snapshot once, then only changed service fields and incident additions, updates, or deletions. Logos and unchanged metadata are not repeated. A reconnect receives a fresh snapshot, and slow clients skip intermediate states without losing the latest changes. Empty WebSocket ping/pong frames keep idle connections alive.

## Development

```sh
nix develop
pnpm install
pnpm check
pnpm dev
```

`pnpm dev` starts Vite and the backend. Vite proxies `/api/status` to the public backend on `127.0.0.1:8080`. The incident editor is available at `http://127.0.0.1:8091/edit` after the frontend has been built once.

For a manual backend configuration, copy `config.example.toml`, build the frontend, and run:

```sh
pnpm build
cargo run --manifest-path apps/backend/Cargo.toml -- ./config.toml
```

The browser uses `/api/status` on the page's own origin. Outside development, terminate TLS at the reverse proxy and forward WebSocket upgrades to the public backend. Do not proxy the separate admin listener to the public internet.

## Configuration

The backend accepts TOML or JSON. Categories contain a local logo and a list of services. Service names and URLs are not editable through the incident UI.

```toml
[[categories]]
id = "example"
name = "Example"
logo = "/path/to/example.svg"

[[categories.services]]
id = "example-home"
name = "Homepage"
url = "https://example.com"
check_http3 = true
```

HTTP 200 through 399 is operational. DNS, connection, and TLS failures are reported as offline; timeouts, HTTP error responses, and HTTP/3 failures have distinct labels. Every non-operational service state uses red on the public page.

Tensamin checks use IDs `tensamin-<channel>-omega`, `tensamin-<channel>-app`, and `tensamin-<channel>-omikron-<id>`, where the channel is `dev`, `stable`, or `canary`. Add more Omikron entries to the configuration to include them in the expandable group and its online count. Unknown checks do not count as online. Checks report endpoint availability, not a complete messaging or call test.

Weekly maintenance is Sunday 18:00 through Monday 00:00 in `Europe/Berlin`. UTC is 16:00 through 22:00 during CEST and 17:00 through 23:00 during CET.

The admin page is available at `/edit` on the separately configured admin address and port. It has intentionally no authentication, so the backend requires the admin address to be loopback. The NixOS module binds it to `127.0.0.1:8081` and does not open its firewall port by default. For remote use, prefer an SSH tunnel:

```sh
ssh -L 8081:127.0.0.1:8081 status-host
```

## NixOS

The included module serves the SPA over HTTPS with nginx and an ACME certificate. It forwards only `/api/status` to the public HTTP/WebSocket listener, which defaults to loopback port 8080. The admin API remains on its separate loopback listener. It no longer needs MTP, WebAssembly builds, or an inbound UDP port.

```nix
{
  inputs.methanium-status.url =
    "github:nonanium/status";

  outputs = { nixpkgs, methanium-status, ... }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        methanium-status.nixosModules.default
        {
          security.acme.acceptTerms = true;
          security.acme.defaults.email = "admin@example.com";

          services.methanium-status = {
            enable = true;
            hostName = "status.example.com";
            openFirewall = true;

            categories = [{
              id = "example";
              name = "Example";
              logo = ./example.svg;
              services = [{
                id = "example-home";
                name = "Homepage";
                url = "https://example.com";
                checkHttp3 = false;
              }];
            }];
          };
        }
      ];
    };
  };
}
```

Use `acmeHost` to share an already configured NixOS ACME certificate. The service options also expose the check interval, timeout, public listener, admin listener, state directory, packages, firewall behavior, categories, logo paths, and services.

Contact: [contact@nonanium.net](mailto:contact@nonanium.net)

Security: [security@nonanium.net](mailto:security@nonanium.net)
