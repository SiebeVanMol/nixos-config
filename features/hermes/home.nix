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

  # The local server's endpoint, derived from the module that owns the port, so
  # raising device.app.ai.port moves every client with it. Reading the model ids
  # from that same option tree is the same rule applied to the names below.
  aiEndpoint = "http://127.0.0.1:${toString osConfig.device.app.ai.port}/v1";
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
        # Per-model, not `agent.reasoning_effort`, so the local models are not
        # sent an effort field: they are reached through a custom base_url, which
        # receives whatever effort resolves, and llama-server has no use for it.
        agent.reasoning_overrides."deepseek-flash" = "low";

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
      # The host runs its own llama-server in router mode (the system.nix
      # beside this file) on loopback:8080, serving four models. Naming the endpoint makes them
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
      # for anything multi-step: a 12B's wrong tool call costs more than the
      # round-trip it saves, the failure is silent (a plausible action on the
      # wrong file), and the local window is 64K against the cloud model's much
      # larger one, so a long session compresses sooner.
      #
      # It is also not the expensive choice at this volume. Recorded usage across
      # every session so far: 556 calls, 1.20M input tokens, 0.70M output, 74.4M
      # cache reads - 98% of the prompt volume bills as cache hits, because the
      # prefix only grows at the end. The estimate for all of it is $0.82, about
      # $0.0015 a call; the heaviest single session, 193 calls, was $0.33.
      #
      # The habit that matters more than the model: switch at a session boundary,
      # not mid-conversation. A provider's cache is keyed to the model serving the
      # request, so a mid-session /model change makes the next turn re-read the
      # whole conversation at cache-miss price - often more than the cloud turn it
      # was meant to save. `/new` first, then `/model small` for a question, a page
      # to summarise, a draft; `/model local` for local or offline work where a 35B
      # is worth 29 tok/s instead of 62.
      #
      # Measured on this host after the two models were fetched: `/model local`
      # decodes at ~29 tok/s holding 5.4 GiB of VRAM (experts in RAM), `/model
      # small` at ~62 tok/s holding 10 GiB, and `/model small` emits real tool
      # calls. Both drop the model after 15 minutes idle, and a cold load off
      # /Vault is ~23 s for the small one and ~75 s for the big one - the second
      # use in a session is seconds, because the page cache kept it.
      #
      # Those speeds assume the card is the model's alone, which is why
      # `models-max` is 1: with two resident the small model measured 15 tok/s,
      # not 62, because the pair does not fit in 16 GiB.
      #
      # Gated on the service, so a host without it gets neither the aliases nor
      # an endpoint pointing at a port nothing serves.
      // lib.optionalAttrs osConfig.device.app.ai.enable {
        providers.llamacpp.base_url = aiEndpoint;

        # Self-contained (provider + base_url, no credential): an alias is
        # resolved before any provider is contacted, so selecting one must not
        # depend on the server being up.
        model_aliases = {
          # The cloud model under its own short name, so a session can go back to
          # it in one command without landing on whichever DeepSeek model the
          # built-in `deepseek` alias happens to resolve to.
          cloud = {
            model = "deepseek-flash";
            provider = "deepseek";
          };

          # The 35B MoE with its experts in RAM: a session that has to think.
          local = {
            model = osConfig.device.app.ai.modelIds.agent;
            provider = "custom";
            base_url = aiEndpoint;
          };

          # The 12B dense one: a question, a page to summarise, long-form
          # writing. Multimodal weights, but no projector is served - images are
          # not wanted, so the vision path stays unwired deliberately.
          small = {
            model = osConfig.device.app.ai.modelIds.quick;
            provider = "custom";
            base_url = aiEndpoint;
          };

          # The alternative to `local`: the one that fits the card outright with
          # the best tool-calling measured in its size class.
          oss = {
            model = osConfig.device.app.ai.modelIds.oss;
            provider = "custom";
            base_url = aiEndpoint;
          };
        };

        # Scheduled work runs on the local server: it is the traffic that can
        # wait out a cold load, and per-token price is the whole bill for a job
        # nobody is waiting on. Resolution at fire time is per-job pin >
        # cron.model > the main model, so a job that wants the cloud model
        # keeps its own pin and this default never forces one onto it.
        #
        # The 35B rather than the 12B: unattended work has no latency to
        # protect, and the big one is the lighter of the two in VRAM (5.4 GiB
        # with its experts in RAM against 10 GiB dense) while being the one
        # whose tool calls were measured as real.
        #
        # `llamacpp` is the provider id, not a second endpoint: it resolves to
        # custom and takes the base_url from providers.llamacpp above. A cron
        # job resolves its provider this way - the scheduler has no base_url
        # field of its own - and `hermes chat --provider llamacpp --model
        # <quick id>` was run against the live server to prove the pair
        # resolves and answers with no credential at all.
        cron = {
          model = osConfig.device.app.ai.modelIds.agent;
          model_provider = "llamacpp";
        };

        # The same reasoning for background work. The fork that files a turn -
        # memory writes, skill edits - is a routine replay of work the main
        # model already did, so it does not pay for a frontier model; a session
        # title needs no model at all. What stays on the cloud is deliberate:
        # compression blocks the session it is summarising, the approval
        # classifier decides whether a dangerous command runs, and vision needs
        # a model that is not served here.
        # Delegation is the escalation half of the routing design. The driving
        # model stays the cloud one; the children it spawns run here, free, on the
        # model that fits the card outright. Measured head-to-head on four
        # sandboxed tasks with identical prompts and budgets (~/bench): the cloud
        # model finished 4/4 in 47 s, this one 2/4 in 478 s, and its two failures
        # were its own claims of success - so it is a worker, not a planner, and
        # the check decides whether a step escalates, never the model's confidence.
        #
        # Concurrency stays at the runtime default: the router serves one model at
        # a time (`models-max` in the system.nix beside this file), so parallel
        # children queue behind a single slot rather than finishing faster.
        delegation = {
          provider = "llamacpp";
          model = osConfig.device.app.ai.modelIds.oss;
        };

        auxiliary = {
          background_review = {
            provider = "llamacpp";
            model = osConfig.device.app.ai.modelIds.agent;
          };

          curator = {
            provider = "llamacpp";
            model = osConfig.device.app.ai.modelIds.agent;
          };

          # Titles are a 3-7 word task, so they go to the smallest model the
          # router serves - the one `tiny` exists for. The size is the point:
          # this call fires at the start of every session, and against the 12B
          # it meant a 6.72 GB weight load and ~10 GiB of the card held for the
          # next fifteen minutes, to emit five tokens. Hermes' instant derived
          # title stays the fallback when the small model returns nothing
          # usable, so a bad title costs a worse title and not a failure.
          title_generation = {
            provider = "llamacpp";
            model = osConfig.device.app.ai.modelIds.tiny;
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

    # The weekly "Hermes usage & spend digest" cron job runs this script before
    # its agent turn: it reads state.db, prices the week's token mix through
    # Hermes' own cost engine and prints the report on stdout, which the job's
    # prompt receives as context. Declared here rather than created by hand so
    # it is versioned with everything else and survives a rebuild; the cron job
    # itself is state and lives in $HERMES_HOME/cron, which activation does not
    # touch.
    hermesHomeFiles."scripts/usage-digest.py" = ./hermes-usage-digest.py;
  };
}
