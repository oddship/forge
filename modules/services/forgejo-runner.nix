{
  config,
  lib,
  ...
}:

let
  cfg = config.forge.services.forgejoRunner;
  hasContainerLabels = lib.any (label: lib.hasInfix ":docker" label) cfg.labels;
in
{
  options.forge.services.forgejoRunner = {
    enable = lib.mkEnableOption "a Forgejo Actions runner";

    url = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:3000/";
      description = "Forgejo URL used by the runner.";
    };

    uuid = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Registered runner UUID; keep it in deployment configuration, not generated state.";
    };

    tokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Runtime file containing the registered runner token.";
    };

    labels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "ubuntu-latest:docker://node:22-bookworm" ];
      description = "OCI labels accepted by this runner.";
    };

    containerRuntime = lib.mkOption {
      type = lib.types.enum [
        "docker"
        "podman"
      ];
      default = "podman";
      description = ''
        OCI runtime used for labels of type `docker`.

        Forgejo calls this label type `docker` for compatibility; the
        selected runtime may be Docker or Podman. Podman is the default for
        Forge because it avoids a Docker daemon dependency while preserving
        the same workflow label contract.
      '';
    };

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Start the runner with the host; disable during one-time registration bootstrap.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.uuid != null && cfg.tokenFile != null;
        message = "forge.services.forgejoRunner requires a registered uuid and tokenFile.";
      }
    ];

    virtualisation.docker.enable = lib.mkIf (
      hasContainerLabels && cfg.containerRuntime == "docker"
    ) true;
    virtualisation.podman.enable = lib.mkIf (
      hasContainerLabels && cfg.containerRuntime == "podman"
    ) true;

    services.forgejo-runner.instances.default = {
      enable = true;
      settings = {
        runner.labels = cfg.labels;
        server.connections.default = {
          url = cfg.url;
          uuid = cfg.uuid;
        };
      };
      runtimes.docker = hasContainerLabels && cfg.containerRuntime == "docker";
      runtimes.podman = hasContainerLabels && cfg.containerRuntime == "podman";
      secrets.server.connections.default.token_url = cfg.tokenFile;
    };

    systemd.services."forgejo-runner-default".wantedBy = lib.mkIf (!cfg.autoStart) (lib.mkForce [ ]);
  };
}
