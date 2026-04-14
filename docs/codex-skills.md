# Codex Skills Workflow

This workflow keeps Codex skills easy to author and easy to deploy:

- author skills as plain files in a separate skill-pack repo
- group skills into profiles in Nix
- deploy one built profile into `~/.codex/skills` with Home Manager

## Create a Skill-Pack Repo

Create a new repo from this flake template:

```bash
nix flake init -t /home/zhenyu/src/public/nix-config#codex-skills
```

The generated repo has this shape:

```text
skills/
  example/
    SKILL.md
profiles/
  default.nix
flake.nix
```

The intended authoring flow is explicit:

1. create `skills/<name>/`
2. add `skills/<name>/SKILL.md`
3. register the skill in `profiles/default.nix`
4. build or deploy the profile

No helper command is required.

## Skill-Pack Flake Contract

The generated skill-pack flake exports:

- `packages.<system>.default`: the `default` profile as a directory tree
- `packages.<system>.skills-<profile>`: named profile outputs
- `packages.<system>.profiles.<profile>`: named profile outputs grouped under `profiles`
- `lib.profiles`: the profile definitions

Each selected skill must exist under `skills/<name>/` and contain `SKILL.md`.

## Deploy From nix-config

Add your skill-pack as a flake input in `flake.nix`, for example:

```nix
inputs.codex-skills.url = "path:../codex-skills";
```

Then enable the deployment module in your home-manager config:

```nix
{
  imports = [
    ../../modules/home/codex-skills.nix
  ];

  my.codexSkills = {
    enable = true;
    source = inputs.codex-skills.packages.${pkgs.system}.skills-default;
  };
}
```

Switch profiles by changing the package you point at, for example:

```nix
source = inputs.codex-skills.packages.${pkgs.system}.skills-coding;
```

Then deploy with your normal Home Manager workflow:

```bash
just hm
```

## Design Notes

- The Home Manager module only deploys a directory tree.
- Profile selection stays in the skill-pack flake.
- Skills are authored as normal files, not embedded as Nix strings.
- If the workflow starts feeling complex, prefer simpler profile data over new helpers.
