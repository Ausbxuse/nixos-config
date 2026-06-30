{
  email = "user@example.com";
  name = "Nix User";
  nix.extraSubstituters = [];
  nix.extraTrustedPublicKeys = [];
  supported-systems = ["x86_64-linux" "aarch64-linux"];
  username = "zhenyu";
  services.searxng.url = null;
}
