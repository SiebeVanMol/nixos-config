# Server-side application stacks. Each one is a self-contained folder with a
# default.nix that names its parts (see jellyfin/default.nix for the shape).
#
# `server` is separate from `app` for the same reason the two are separate
# directories at all: what lives here is a service other machines talk to, not
# something a desktop session drives. app/ holds the desktop applications.
{
  imports = [
    ./jellyfin
    ./minecraft
    ./ai.nix
  ];
}
