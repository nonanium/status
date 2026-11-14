{
  description = "Nonanium Status";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs =
    {
      self,
      nixpkgs,
      rust-overlay,
      ...
    }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          root = toString ./.;
          source = pkgs.lib.cleanSourceWith {
            src = ./.;
            filter =
              path: _type:
              let
                relative = pkgs.lib.removePrefix "${root}/" (toString path);
              in
              !(pkgs.lib.hasPrefix ".git/" relative)
              && !(pkgs.lib.hasInfix "node_modules" relative)
              && !(pkgs.lib.hasInfix "target/" relative)
              && !(pkgs.lib.hasInfix "apps/frontend/dist/" relative)
              && relative != "result";
          };
          frontendNativeBuildInputs = [
            pkgs.cacert
            pkgs.git
            pkgs.nodejs
            pkgs.pnpm
          ];
          frontendDeps = pkgs.fetchPnpmDeps {
            pname = "methanium-status-frontend-deps";
            version = "0.1.0";
            src = source;
            pnpm = pkgs.pnpm;
            fetcherVersion = 4;
            hash = "sha256-Up0Kiv+W0BwsLWLX34pbzRFxQtQ1GZAlQYYenmVHauY=";
          };
          frontend = pkgs.stdenvNoCC.mkDerivation {
            pname = "methanium-status-frontend";
            version = "0.1.0";
            src = source;
            nativeBuildInputs = frontendNativeBuildInputs ++ [ pkgs.pnpmConfigHook ];
            pnpmDeps = frontendDeps;

            buildPhase = ''
              runHook preBuild
              export HOME="$TMPDIR/home"
              pnpm build
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              cp -r apps/frontend/dist "$out"
              runHook postInstall
            '';
          };
          backend = pkgs.rustPlatform.buildRustPackage {
            pname = "methanium-status";
            version = "0.1.0";
            src = source;
            cargoRoot = "apps/backend";
            buildAndTestSubdir = "apps/backend";
            cargoLock = {
              lockFile = ./apps/backend/Cargo.lock;
            };
          };
        in
        {
          default = frontend;
          inherit backend frontend;
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
          rustToolchain = pkgs.rust-bin.stable.latest.default.override {
            extensions = [
              "clippy"
              "rust-src"
              "rustfmt"
            ];
          };
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.curl
              pkgs.nodejs
              pkgs.pnpm
              rustToolchain
            ];
          };
        }
      );

      checks = forAllSystems (system: {
        inherit (self.packages.${system}) backend frontend;
      });

      nixosModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.services.methanium-status;
          acmeHost = if cfg.acmeHost == null then cfg.hostName else cfg.acmeHost;
          serviceType = lib.types.submodule {
            options = {
              id = lib.mkOption {
                type = lib.types.str;
                description = "Stable service identifier.";
              };
              name = lib.mkOption {
                type = lib.types.str;
                description = "Service display name.";
              };
              url = lib.mkOption {
                type = lib.types.str;
                description = "HTTP or HTTPS URL to check.";
              };
              checkHttp3 = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = "Whether this service must also pass an HTTP/3-only check.";
              };
            };
          };
          categoryType = lib.types.submodule {
            options = {
              id = lib.mkOption {
                type = lib.types.str;
                description = "Stable category identifier.";
              };
              name = lib.mkOption {
                type = lib.types.str;
                description = "Category display name.";
              };
              logo = lib.mkOption {
                type = lib.types.path;
                description = "Local SVG, PNG, WebP, or JPEG logo file.";
              };
              services = lib.mkOption {
                type = lib.types.listOf serviceType;
                default = [ ];
                description = "Services shown and monitored in this category.";
              };
            };
          };
          configFile = (pkgs.formats.json { }).generate "methanium-status.json" {
            public_address = cfg.publicAddress;
            public_port = cfg.publicPort;
            admin_address = cfg.adminAddress;
            admin_port = cfg.adminPort;
            check_interval_seconds = cfg.checkInterval;
            timeout_seconds = cfg.timeout;
            frontend_dir = toString cfg.frontendPackage;
            state_dir = "/var/lib/${cfg.stateDirectory}";
            curl = "${pkgs.curl}/bin/curl";
            categories = map (category: {
              inherit (category) id name;
              logo = toString category.logo;
              services = map (service: {
                inherit (service) id name url;
                check_http3 = service.checkHttp3;
              }) category.services;
            }) cfg.categories;
          };
        in
        {
          options.services.methanium-status = {
            enable = lib.mkEnableOption "Nonanium Status monitoring and status page";
            package = lib.mkPackageOption self.packages.${pkgs.stdenv.hostPlatform.system} "backend" { };
            frontendPackage =
              lib.mkPackageOption self.packages.${pkgs.stdenv.hostPlatform.system} "frontend"
                { };
            hostName = lib.mkOption {
              type = lib.types.str;
              default = "status.nonanium.net";
              description = "Public status page hostname.";
            };
            acmeHost = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "ACME certificate name, defaulting to hostName.";
            };
            publicAddress = lib.mkOption {
              type = lib.types.str;
              default = "127.0.0.1";
              description = "Address on which the public HTTP and WebSocket backend listens.";
            };
            publicPort = lib.mkOption {
              type = lib.types.port;
              default = 8080;
              description = "HTTP backend port used by the nginx reverse proxy.";
            };
            adminAddress = lib.mkOption {
              type = lib.types.str;
              default = "127.0.0.1";
              description = "Address for the unauthenticated incident editor.";
            };
            adminPort = lib.mkOption {
              type = lib.types.port;
              default = 8081;
              description = "TCP port for the unauthenticated incident editor.";
            };
            checkInterval = lib.mkOption {
              type = lib.types.ints.positive;
              default = 300;
              description = "Seconds between service checks.";
            };
            timeout = lib.mkOption {
              type = lib.types.ints.positive;
              default = 15;
              description = "Per-check timeout in seconds.";
            };
            stateDirectory = lib.mkOption {
              type = lib.types.str;
              default = "methanium-status";
              description = "systemd state directory name for incident history.";
            };
            openFirewall = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Open HTTP and HTTPS ports for the public nginx virtual host.";
            };
            openAdminFirewall = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Open the unauthenticated admin TCP port. Use with care.";
            };
            categories = lib.mkOption {
              type = lib.types.listOf categoryType;
              description = "Status categories and checked services.";
              default = [
                {
                  id = "methanium";
                  name = "Nonanium";
                  logo = ./apps/frontend/public/methanium.svg;
                  services = [
                    {
                      id = "methanium-homepage";
                      name = "Homepage";
                      url = "https://nonanium.net";
                    }
                    {
                      id = "methanium-ui";
                      name = "Nonanium UI";
                      url = "https://ui.nonanium.net";
                    }
                    {
                      id = "methanium-git";
                      name = "Git";
                      url = "https://github.com/nonanium";
                    }
                    {
                      id = "methanium-legal";
                      name = "Legal Page";
                      url = "https://legal.nonanium.net";
                    }
                  ];
                }
                {
                  id = "tensamin";
                  name = "Tensamin";
                  logo = ./apps/frontend/public/tensamin.svg;
                  services = [
                    {
                      id = "tensamin-homepage";
                      name = "Homepage";
                      url = "https://tensamin.net";
                    }
                    {
                      id = "tensamin-docs";
                      name = "Docs";
                      url = "https://docs.tensamin.net";
                    }
                  ]
                  ++
                    lib.concatMap
                      (
                        channel:
                        let
                          domain = "${channel}.tensamin.net";
                        in
                        [
                          {
                            id = "tensamin-${channel}-app";
                            name = "Web App";
                            url = if channel == "stable" then "https://app.tensamin.net" else "https://app.${domain}";
                          }
                          {
                            id = "tensamin-${channel}-omega";
                            name = "Omega";
                            url = "https://omega.${domain}/.well-known/tensamin";
                            checkHttp3 = true;
                          }
                          {
                            id = "tensamin-${channel}-omikron-1";
                            name = "Omikron 1";
                            url = "https://omikron.${domain}";
                            checkHttp3 = true;
                          }
                        ]
                      )
                      [
                        "dev"
                        "stable"
                        "canary"
                      ];
                }
              ];
            };
          };

          config = lib.mkIf cfg.enable {
            users.groups.methanium-status = { };
            users.users.methanium-status = {
              isSystemUser = true;
              group = "methanium-status";
            };

            security.acme.certs.${acmeHost} = {
              group = "nginx";
            };

            services.nginx = {
              enable = true;
              virtualHosts.${cfg.hostName} = {
                forceSSL = true;
                useACMEHost = acmeHost;
                root = cfg.frontendPackage;
                locations = {
                  "/".tryFiles = "$uri $uri/ /index.html";
                  "/api/".return = "404";
                  "= /api/status" = {
                    proxyPass = "http://${
                      if lib.hasInfix ":" cfg.publicAddress then "[${cfg.publicAddress}]" else cfg.publicAddress
                    }:${toString cfg.publicPort}";
                    proxyWebsockets = true;
                    extraConfig = ''
                      proxy_read_timeout 90s;
                    '';
                  };
                };
              };
            };

            systemd.services.methanium-status = {
              description = "Nonanium Status monitor";
              wantedBy = [ "multi-user.target" ];
              wants = [
                "network-online.target"
              ];
              after = [
                "network-online.target"
              ];
              restartTriggers = [ configFile ];
              serviceConfig = {
                User = "methanium-status";
                Group = "methanium-status";
                StateDirectory = cfg.stateDirectory;
                ExecStart = "${cfg.package}/bin/methanium-status ${configFile}";
                Restart = "on-failure";
                RestartSec = 5;
                LockPersonality = true;
                NoNewPrivileges = true;
                PrivateDevices = true;
                PrivateTmp = true;
                ProtectClock = true;
                ProtectControlGroups = true;
                ProtectHome = true;
                ProtectHostname = true;
                ProtectKernelLogs = true;
                ProtectKernelModules = true;
                ProtectKernelTunables = true;
                ProtectSystem = "strict";
                RestrictAddressFamilies = [
                  "AF_INET"
                  "AF_INET6"
                ];
                RestrictNamespaces = true;
                RestrictRealtime = true;
                SystemCallArchitectures = "native";
                UMask = "0077";
              };
            };

            networking.firewall.allowedTCPPorts =
              lib.optionals cfg.openFirewall [
                80
                443
              ]
              ++ lib.optionals cfg.openAdminFirewall [ cfg.adminPort ];
          };
        };
    };
}
