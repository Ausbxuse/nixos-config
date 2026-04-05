#
# Operator age keys — humans allowed to decrypt nix-secrets from their own
# workstation without sudo. These are NOT hosts; they are additional sops
# recipients merged alongside per-host keys when generating
# nix-secrets/.sops.yaml (see scripts/admit-host.sh).
#
# Derive a key from your existing SSH key with:
#   nix shell nixpkgs#ssh-to-age -c ssh-to-age < ~/.ssh/id_ed25519.pub
#
{
  zhenyu-razy = "age1y4acshfrcncq4hscm0nag7eeemkql24muy956u0zzuun5rnmgqqq6u0zk0";
}
