{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.my.codexSkills;
  emptySkills = pkgs.runCommandLocal "codex-empty-skills" {} ''
    mkdir -p "$out"
  '';
in {
  options.my.codexSkills = {
    enable = lib.mkEnableOption "declarative Codex skill deployment";

    source = lib.mkOption {
      type = lib.types.path;
      default = emptySkills;
      defaultText = lib.literalExpression "pkgs.runCommandLocal \"codex-empty-skills\" {} \"mkdir -p \\$out\"";
      description = ''
        Directory tree to deploy into ~/.codex/skills.
        This is expected to come from a skill-pack flake package output.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.file.".codex/skills" = {
      source = cfg.source;
      recursive = true;
    };
  };
}
