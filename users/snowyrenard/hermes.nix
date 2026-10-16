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
    inputs.hermes-agent.homeModules.default
  ];

  programs.hermes-agent = {
    enable = true;
    desktop.enable = true;
  };

  services.hermes-agent = {
    enable = true;
    gateway.enable = true;

    # An OpenRouter model slug. Hermes defaults to OpenRouter when no base_url
    # is set; for a provider used directly, set settings.model.base_url and use
    # that provider's native model id.
    settings.model.default = "deepseek/deepseek-chat";

    # Secrets travel by runtime path, never as a Nix path literal, which would
    # copy them into the world-readable store. Write a line such as
    # OPENROUTER_API_KEY=sk-or-... into this file with mode 0600; activation
    # merges it into ~/.hermes/.env. A missing file only warns, so the first
    # switch succeeds before the key exists.
    environmentFiles = [
      "${config.home.homeDirectory}/.config/hermes/env"
    ];
  };
}
