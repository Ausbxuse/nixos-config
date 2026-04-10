{
  config,
  lib,
  pkgs,
  ...
}: let
  nvimPath = "${config.home.homeDirectory}/src/public/nix-config/modules/home/nvim/nvim";
  gnomeClipboard = pkgs.stdenv.mkDerivation {
    pname = "nvim-gnome-clipboard";
    version = "1";
    dontUnpack = true;
    nativeBuildInputs = [
      pkgs.makeWrapper
      pkgs.wrapGAppsHook3
    ];
    buildInputs = [
      pkgs.gjs
      pkgs.gtk3
    ];
    installPhase = ''
      install -Dm644 ${./gnome-clipboard.js} $out/share/nvim-gnome-clipboard/gnome-clipboard.js

      makeWrapper ${pkgs.gjs}/bin/gjs $out/bin/nvim-gnome-clipboard \
        --add-flags $out/share/nvim-gnome-clipboard/gnome-clipboard.js
    '';
  };
in {
  xdg.configFile."nvim".source = config.lib.file.mkOutOfStoreSymlink nvimPath;

  home.packages = with pkgs; [
    gnomeClipboard
    # lua51Packages.luarocks-nix
    # fortune
    nodejs
    tree-sitter
    # inotify-tools
    fd
    ripgrep
    pre-commit
    file
    # jdk
    # cargo
    gcc
  ];

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    # extraWrapperArgs = with pkgs; [
    #   # LIBRARY_PATH is used by gcc before compilation to search directories
    #   # containing static and shared libraries that need to be linked to your program.
    #   "--suffix"
    #   "LIBRARY_PATH"
    #   ":"
    #   "${lib.makeLibraryPath [stdenv.cc.cc zlib]}"
    #
    #   # PKG_CONFIG_PATH is used by pkg-config before compilation to search directories
    #   # containing .pc files that describe the libraries that need to be linked to your program.
    #   "--suffix"
    #   "PKG_CONFIG_PATH"
    #   ":"
    #   "${lib.makeSearchPathOutput "dev" "lib/pkgconfig" [stdenv.cc.cc zlib]}"
    # ];
  };
}
