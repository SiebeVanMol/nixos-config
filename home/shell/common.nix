# Common shell tool: zoxide (smart directory jumper) with Nushell integration.
{
  programs.zoxide = {
    enable = true;
    enableNushellIntegration = true;
  };
}
