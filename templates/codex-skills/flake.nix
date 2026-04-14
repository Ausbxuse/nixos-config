{
  description = "Codex skill pack";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
  }: let
    lib = nixpkgs.lib;
    systems = ["x86_64-linux" "aarch64-linux"];
    forAllSystems = lib.genAttrs systems;

    skillsDir = ./skills;
    profileFile = ./profiles/default.nix;
    profiles = import profileFile;

    skillNames = builtins.attrNames (
      builtins.readDir skillsDir
    );

    hasSkillFile = name: builtins.pathExists (skillsDir + "/${name}/SKILL.md");

    mkSkillTree = profileName: let
      selected = profiles.${profileName} or (throw "Unknown Codex skill profile: ${profileName}");
      missing = builtins.filter (name: !(builtins.elem name skillNames)) selected;
      invalid = builtins.filter (name: !hasSkillFile name) selected;
    in
      if missing != [] then
        throw "Profile ${profileName} references missing skills: ${lib.concatStringsSep ", " missing}"
      else if invalid != [] then
        throw "Skills missing SKILL.md: ${lib.concatStringsSep ", " invalid}"
      else
        builtins.path {
          name = "codex-skills-${profileName}";
          path = skillsDir;
          filter = path: type: let
            rel = lib.removePrefix "${toString skillsDir}/" (toString path);
            top = builtins.head (lib.splitString "/" rel);
          in
            rel == ""
            || builtins.elem top selected;
        };
  in {
    lib = {
      inherit profiles skillNames;
      mkSkillTree = profileName: mkSkillTree profileName;
    };

    packages = forAllSystems (_system: let
      profilePackages = lib.mapAttrs (name: _value: mkSkillTree name) profiles;
    in
      {
        default = mkSkillTree "default";
        profiles = profilePackages;
      }
      // lib.mapAttrs' (name: value: lib.nameValuePair "skills-${name}" value) profilePackages);

    checks = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in
      lib.genAttrs skillNames (name:
        pkgs.runCommandLocal "check-codex-skill-${name}" {} ''
          test -f ${lib.escapeShellArg "${skillsDir}/${name}/SKILL.md"}
          mkdir -p "$out"
        ''));

    templates.default = {
      path = ./.;
      description = "Codex skill-pack template";
    };
  };
}
