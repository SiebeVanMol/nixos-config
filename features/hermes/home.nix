# Hermes Agent (https://github.com/NousResearch/hermes-agent): Nous Research's
# agent harness, imported into Snowy's home only. It is deliberately not a shared
# home module: an agent's credentials, memory and sessions belong to one person,
# so alexander never gets it.
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
  pkgs,
  ...
}: let
  # The agent's toolbox, defined once for this user: the servers, the
  # compilers, and what only the agent needs. See programming.nix.
  programming = import ../../users/snowyrenard/programming.nix {inherit pkgs;};

  # The judge server's endpoint, derived from the module that owns the port, so
  # raising device.app.ai.port moves the plugin with it.
  judgeEndpoint = "http://127.0.0.1:${toString osConfig.device.app.ai.port}/v1/systemone";
in {
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

    # What the agent's shell can reach. extraPackages IS a Hermes process's
    # PATH - the module builds it as [hermes bash coreutils git] ++
    # extraPackages - and the LSP layer resolves its server binaries on that
    # same value.
    #
    # The lists are in programming.nix rather than here, so the editor and the
    # shell take the same definitions instead of three copies that drift. That
    # file explains each entry: which servers the editor resolves too, which
    # compilers the shell shares, and why nix, rustup, rust-analyzer, shellcheck
    # and bear are the agent's alone.
    extraPackages = programming.servers ++ programming.toolchain ++ programming.agentOnly;

    # One `settings` attribute, not two: an attribute set literal cannot repeat a
    # key, and the local wiring is conditional, so the two halves are joined here
    # rather than written as two definitions.
    #
    # DeepSeek is a first-class provider: `provider` selects its built-in
    # endpoint (https://api.deepseek.com) and DEEPSEEK_API_KEY is the
    # credential, so no base_url is needed. deepseek-flash is the cheap agent
    # model; deepseek-v4-pro is the larger sibling. It stays the default model:
    # the host's local server hands its VRAM back when idle and this desktop
    # shares the card with games.
    settings =
      {
        model = {
          provider = "deepseek";
          default = "deepseek-flash";
        };

        # One short name for the cloud model, so a session can return to it
        # without landing on whichever DeepSeek model the built-in alias picks.
        model_aliases.cloud = {
          model = "deepseek-flash";
          provider = "deepseek";
        };

        # The context cap is absolute rather than relative, on purpose. The
        # relative `threshold` fires at half the model's window, so it floats
        # with whatever window the provider advertises - this week's calls
        # averaged 191k of context, which is what a large window plus a relative
        # trigger produces. Cache reads are ~39% of the bill and they grow with
        # the prefix, so this is the one setting that lowers spend without
        # touching quality: sessions now compress near 100k instead of near
        # 200k, and the extra summarisation call costs a fraction of the cache
        # it saves. It also keeps a future model's cheap cache tier in reach.
        compression = {
          threshold_tokens = 100000;
        };

        # Per-turn reasoning effort. A plugin judges each prompt with Kev-0.8B -
        # a decision model, so it scores the effort options in one forward pass
        # (~50 ms on the CPU) instead of writing an answer - and rewrites only
        # the effort field of the request, so a mechanical turn stays at `low`
        # and a debugging turn gets `high` without changing the session's model
        # or touching the prompt-cache prefix. The ceiling is `high` on purpose:
        # `max` costs roughly 13x a task for diminishing returns.
        #
        # Kev speaks TypeSafe's /v1/systemone contract, which is exactly what the
        # plugin's `jev` backend posts to, so the hosted default is just pointed
        # at the local judge server - no shim in between. The backend insists on a
        # non-empty key before it will call; llama.cpp ignores the bearer, so
        # EFFORTLESS_HERMES_TYPESAFE_KEY in ~/.config/hermes/env is a placeholder.
        plugins = {
          enabled = ["effortless-hermes" "peak-price"];
          entries.effortless-hermes.settings = {
            enabled = true;
            judge_backend = "jev";
            fallback_backend = "none";
            jev_url = judgeEndpoint;
            jev_model = "Kev-0.8B-Q8_0";
            judge_timeout_seconds = 5;
            effort_floor = "low";
            effort_ceiling = "high";
            effort_bias = 0;
            feedback_enabled = false;
          };
        };

        # Reasoning is where this setup's tokens actually go: across every
        # recorded session 517K of the 704K output tokens were reasoning tokens
        # (73%), and output is the priciest class - the input side is already 98%
        # cache hits. DeepSeek V4 accepts low/medium/high/max, its thinking
        # defaults to on, and the provider profile emits the toggle on every
        # request so the reasoning_content echo contract holds, which leaves the
        # level as the one lever.
        #
        # `low` rather than a higher tier because this agent's turns are mostly
        # tool-driven and mechanical, where thinking past `low` buys little.
        # Raise it per session with `/reasoning high` - session-scoped, so
        # managed mode is untouched and nothing has to be written - or change
        # this line for the default. `/reasoning none` is turned by the DeepSeek
        # profile into an explicit `thinking: {type: disabled}`, switching it off
        # outright, which is a reasonable choice for a one-shot question and a
        # poor one for a tool loop.
        #
        # Per-model, not `agent.reasoning_effort`, so the larger DeepSeek tier
        # keeps its own default: this line is about the cheap model's mostly
        # mechanical turns, not about reasoning everywhere.

        # C# is the one language he works in that Hermes ships no server for.
        # A config-declared server is gated like nixd and rust-analyzer: it
        # starts only in a workspace the operator pointed Hermes at - a session
        # launched inside the project, a Desktop project, or a terminal.cwd
        # inside it - and the log says `skipped: untrusted workspace` when
        # there is none. That gate is why no directory list appears here: one
        # would go stale at the next move and would trust everything cloned
        # into it. The command resolves on the agent's PATH, which is
        # programming.nix's list.
        lsp.servers.csharp = {
          command = ["csharp-ls"];
          extensions = [".cs"];
          language_id = "csharp";
        };
      }
      # One host runs the judge server (the system.nix beside this file): Kev on
      # loopback, 812 MB of RAM, no VRAM. The agent itself runs on DeepSeek alone,
      # so everything that used to be routed here - the 35B/12B/20B chat models,
      # cron, delegation, background review, the curator, titles - now goes over
      # the API. At the recorded $0.0015 a call (556 calls, $0.82 in total) those
      # models were never the cheaper option; they were the offline one, and they
      # cost 59 GB of store and ~1,100 lines of wiring to keep.
      #
      # Without the service the plugin has nobody to ask, so it is switched off
      # rather than timing out on the URL above on every turn.
      // lib.optionalAttrs (!osConfig.device.app.ai.enable) {
        plugins.entries.effortless-hermes.settings.enabled = false;
      };

    # Secrets travel by runtime path, never as a Nix path literal, which would
    # copy them into the world-readable store. Write a line such as
    # DEEPSEEK_API_KEY=sk-... into this file with mode 0600; activation merges
    # it into ~/.hermes/.env. A missing file only warns, so the first switch
    # succeeds before the key exists.
    environmentFiles = [
      "${config.home.homeDirectory}/.config/hermes/env"
    ];

    # The weekly "Hermes usage & spend digest" cron job runs this script before
    # its agent turn: it reads state.db, prices the week's token mix through
    # Hermes' own cost engine and prints the report on stdout, which the job's
    # prompt receives as context. Declared here rather than created by hand so
    # it is versioned with everything else and survives a rebuild; the cron job
    # itself is state and lives in $HERMES_HOME/cron, which activation does not
    # touch.
    hermesHomeFiles."scripts/usage-digest.py" = ./scripts/usage-digest.py;

    # Peak-price and credit watch, as one feature: the two scripts the cron jobs
    # run, the chat widget, the status-bar pill and the backend route its hover
    # card reads. Every piece used to live only in $HERMES_HOME, which meant a
    # rebuild could not recreate it and no change was ever reviewed here.
    # Filenames are part of the interface: the cron jobs name these scripts and
    # the desktop plugin is found by its folder, so they are declared as-is.
    hermesHomeFiles."scripts/peak_price.py" = ./scripts/peak_price.py;
    hermesHomeFiles."scripts/deepseek_budget.py" = ./scripts/deepseek_budget.py;
    hermesHomeFiles."widgets/peak-price.html" = ./widgets/peak-price.html;
    hermesHomeFiles."desktop-plugins/peak-price/plugin.js" =
      ./plugins/peak-price/desktop/plugin.js;
    # The same file also ships as the package's desktop half. On startup the app
    # materialises that half into desktop-plugins itself, so whichever path runs
    # first the pill is present; keeping both costs one copy and removes the
    # single point of failure that hid the plugin after the last switch.
    hermesHomeFiles."plugins/peak-price/desktop/plugin.js" =
      ./plugins/peak-price/desktop/plugin.js;
    hermesHomeFiles."plugins/peak-price/dashboard/manifest.json" =
      ./plugins/peak-price/dashboard/manifest.json;
    hermesHomeFiles."plugins/peak-price/dashboard/plugin_api.py" =
      ./plugins/peak-price/dashboard/plugin_api.py;
  };
}
