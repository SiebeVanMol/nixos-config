# AI stack (KoboldCpp + model store). Currently disabled; see git history for
# the full implementation (system/app/llama-store.py holds the web store app).
{
  config,
  lib,
  ...
}:
{
  config = lib.mkIf config.device.app.ai.enable {
    # (disabled)
  };
}