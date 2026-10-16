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

    # DeepSeek is a first-class provider: `provider` selects its built-in
    # endpoint (https://api.deepseek.com) and DEEPSEEK_API_KEY is the
    # credential, so no base_url is needed. deepseek-flash is the model dsh
    # already runs (see overlays/dsh-model-router.nix); deepseek-v4-pro is the
    # larger sibling.
    settings.model = {
      provider = "deepseek";
      default = "deepseek-flash";
    };

    # The host runs its own llama-server (system/server/ai) on loopback:8080.
    # Naming the endpoint makes the local model selectable and not merely
    # detectable: `llamacpp` resolves to this server instead of depending on the
    # port probe alone, and the `local` alias gives /model a name to switch with.
    # It has to be an alias, because managed mode refuses `hermes config set` -
    # a runtime config write is exactly what the next switch would undo.
    #
    # Local is deliberately not the default. The server hands its VRAM back when
    # idle and this desktop shares the card with games, so a new session still
    # starts on DeepSeek and /model local is the deliberate move. The port is
    # device.app.ai.port; change both together.
    settings.providers.llamacpp.base_url = "http://127.0.0.1:8080/v1";

    # Self-contained (provider + base_url, no key): an alias is resolved before
    # any provider is contacted, so it must not depend on the server being up.
    settings.model_aliases.local = {
      model = "qwen3.6-35b-a3b";
      provider = "custom";
      base_url = "http://127.0.0.1:8080/v1";
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
