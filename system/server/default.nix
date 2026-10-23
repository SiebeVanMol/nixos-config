# Server-side application stacks, one self-contained folder each.
#
# Separate from app/ because what lives here is a service other machines talk to,
# not something driven by a desktop session.
{
  imports = [
    ./ai
    ./amoeba
    ./media
    ./minecraft
  ];
}
