# Hermes Agent (https://github.com/NousResearch/hermes-agent): Nous Research's
# agent harness, imported into Snowy's home only. It is deliberately not a
# shared home module like deepseek-harness: an agent's credentials, memory and
# sessions belong to one person, so alexander never gets it.
#
# `programs.hermes-agent` is the installation - the `hermes` CLI and the
# Electron desktop application. `services.hermes-agent` owns HERMES_HOME and the
# gateway daemon. The gateway is a systemd *user* unit, so
# users.users.snowyrenard.linger must stay true (system/default.nix) or systemd
# stops the user manager at logout and takes the unit with it.
#
# The module runs in managed mode: `hermes setup` and `hermes config set` refuse
# to run and name `home-manager switch` instead. The model is therefore declared
# here, and the API key goes in the env file below, never into this repository.
{
  config,
  inputs,
  lib,
  osConfig,
  ...
}: {
  imports = [
    inputs.hermes-agent.homeManagerModules.default
  ];

  programs.hermes-agent = {
    enable = true;
    desktop.enable = true;
  };

  services.hermes-agent = {
    enable = true;
    gateway.enable = true;

    # One `settings` attribute, not two: an attribute set literal cannot repeat a
    # key, and the local wiring is conditional, so the two halves are joined here
    # rather than written as two definitions.
    #
    # DeepSeek is a first-class provider: `provider` selects its built-in
    # endpoint (https://api.deepseek.com) and DEEPSEEK_API_KEY is the
    # credential, so no base_url is needed. deepseek-flash is the model dsh
    # already runs (see overlays/dsh-model-router.nix); deepseek-v4-pro is the
    # larger sibling. It stays the default model: the host's local server hands
    # its VRAM back when idle and this desktop shares the card with games.
    settings =
      {
        model = {
          provider = "deepseek";
          default = "deepseek-flash";
        };
      }
      # The host runs its own llama-server in router mode (system/server/ai) on
      # loopback:8080, serving two models. Naming the endpoint makes them
      # selectable and not merely detectable: `llamacpp` resolves to this server
      # instead of depending on the port probe alone, and the aliases give /model
      # names to switch with. The ids are the router's - one per GGUF file name -
      # and they are read from the module rather than repeated here, so renaming
      # a model file cannot leave behind an alias that silently stops resolving.
      #
      # Aliases rather than a different default, because managed mode refuses
      # `hermes config set`: a runtime config write is exactly what the next
      # switch would undo, while an alias resolves per session and writes
      # nothing. `/model local` is the thinking model, `/model small` the quick
      # one; the port is device.app.ai.port, so change both together.
      #
      # DeepSeek stays the default because the local models are the wrong tool
      # for anything multi-step. A 12B's wrong tool call costs more than the
      # round-trip it saves, and the failure is silent - a plausible action on the
      # wrong file - while the local window is 64K against the cloud model's much
      # larger one, so long sessions hit compression sooner. `/model small` is for
      # a question, a page to summarise, a draft; `/model local` for local or
      # offline work where a 35B is worth 29 tok/s instead of 62.
      #
      # Measured on this host after the two models were fetched: `/model local`
      # decodes at ~29 tok/s holding 5.4 GiB of VRAM (experts in RAM), `/model
      # small` at ~62 tok/s holding 10 GiB, and `/model small` emits real tool
      # calls. Both drop the model after 15 minutes idle, and a cold load off
      # /Vault is ~23 s for the small one and ~75 s for the big one - the second
      # use in a session is seconds, because the page cache kept it.
      #
      # Gated on the service, so a host without it gets neither the aliases nor
      # an endpoint pointing at a port nothing serves.
      // lib.optionalAttrs osConfig.device.app.ai.enable {
        providers.llamacpp.base_url = "http://127.0.0.1:8080/v1";

        # Self-contained (provider + base_url, no credential): an alias is
        # resolved before any provider is contacted, so selecting one must not
        # depend on the server being up.
        model_aliases = {
          # The 35B MoE with its experts in RAM: a session that has to think.
          local = {
            model = osConfig.device.app.ai.modelIds.agent;
            provider = "custom";
            base_url = "http://127.0.0.1:8080/v1";
          };

          # The 12B dense one: a question, a page to summarise, a screenshot.
          small = {
            model = osConfig.device.app.ai.modelIds.quick;
            provider = "custom";
            base_url = "http://127.0.0.1:8080/v1";
          };
        };
      };

    # Secrets travel by runtime path, never as a Nix path literal, which would
    # copy them into the world-readable store. Write a line such as
    # DEEPSEEK_API_KEY=sk-... into this file with mode 0600; activation merges
    # it into ~/.hermes/.env. A missing file only warns, so the first switch
    # succeeds before the key exists.
    environmentFiles = [
      "${config.home.homeDirectory}/.config/hermes/env"
    ];
  };
}
