{
  lib,
  pkgs,
}: {sources}: let
  fetchSource = file:
    pkgs.fetchurl {
      name = file.filename;
      url = file.url;
      hash = file.hash;
    };

  sourceFiles =
    map (file: {
      inherit (file) filename path;
      src = fetchSource file;
    })
    sources.files;

  modFiles = lib.filter (file: file.path == "mods/") sourceFiles;
  resourcePackFiles = lib.filter (file: file.path == "resourcepacks/") sourceFiles;
  baseMrpack = pkgs.fetchurl {
    url = sources.baseMrpack.url;
    hash = sources.baseMrpack.hash;
  };

  mrpackFileName = "${lib.replaceStrings [" "] ["-"] sources.instanceName}.mrpack";
in
  pkgs.stdenvNoCC.mkDerivation {
    pname = "minecraft-mrpack";
    version = sources.dependencies.minecraft;

    nativeBuildInputs = with pkgs; [
      python3
      unzip
    ];

    dontUnpack = true;

    installPhase = ''
            runHook preInstall

            workdir="$(mktemp -d)"
            mkdir -p "$out"
            unzip -qq "${baseMrpack}" -d "$workdir/pack"

            ${lib.concatMapStringsSep "\n" (file: ''
          target_dir="$workdir/pack/overrides/${file.path}"
          mkdir -p "$target_dir"
          cp "${file.src}" "$target_dir/${file.filename}"
          chmod u+w "$target_dir/${file.filename}"
        '')
        sourceFiles}

            python3 - "$workdir/pack/overrides/mods" <<'PY'
      import json
      import pathlib
      import sys
      import zipfile

      mods_dir = pathlib.Path(sys.argv[1])
      preferred = set(${builtins.toJSON (map (file: file.filename) modFiles)})

      def mod_ids(path: pathlib.Path) -> set[str]:
          try:
              with zipfile.ZipFile(path) as archive:
                  if "fabric.mod.json" in archive.namelist():
                      data = json.loads(archive.read("fabric.mod.json"))
                      ids = set()
                      mod_id = data.get("id")
                      if mod_id:
                          ids.add(mod_id)
                      for provided in data.get("provides", []):
                          if isinstance(provided, str):
                              ids.add(provided)
                          elif isinstance(provided, dict) and provided.get("id"):
                              ids.add(provided["id"])
                      return ids
          except Exception:
              return set()
          return set()

      owners: dict[str, pathlib.Path] = {}
      for path in sorted(mods_dir.glob("*.jar")):
          ids = mod_ids(path)
          for mod_id in ids:
              if mod_id not in owners:
                  owners[mod_id] = path
                  continue
              current = owners[mod_id]
              current_preferred = current.name in preferred
              new_preferred = path.name in preferred
              if current_preferred and not new_preferred:
                  break
              if new_preferred and not current_preferred:
                  if current.exists():
                      current.unlink()
                  owners[mod_id] = path
                  continue
              if path.name > current.name:
                  if current.exists():
                      current.unlink()
                  owners[mod_id] = path
              else:
                  if path.exists():
                      path.unlink()
                  break
      PY

            python3 - "$workdir/pack" <<'PY'
      import json
      import pathlib
      import sys

      pack_root = pathlib.Path(sys.argv[1])
      index_path = pack_root / "modrinth.index.json"
      index = json.loads(index_path.read_text(encoding="utf-8"))
      index["name"] = ${builtins.toJSON sources.instanceName}
      index["versionId"] = ${builtins.toJSON sources.dependencies.minecraft}
      deps = dict(index.get("dependencies", {}))
      deps["minecraft"] = ${builtins.toJSON sources.dependencies.minecraft}
      deps["fabric-loader"] = ${builtins.toJSON sources.dependencies."fabric-loader"}
      index["dependencies"] = deps
      index_path.write_text(json.dumps(index, indent=2) + "\n", encoding="utf-8")

      options_path = pack_root / "overrides" / "config" / "yosbr" / "options.txt"
      lines = options_path.read_text(encoding="utf-8").splitlines() if options_path.exists() else []
      resource_packs = ["vanilla", "fabric"] + ${builtins.toJSON (map (file: "file/${file.filename}") resourcePackFiles)}

      updated = []
      seen_resource = False
      seen_incompatible = False
      for line in lines:
          if line.startswith("resourcePacks:"):
              updated.append(f"resourcePacks:{json.dumps(resource_packs)}")
              seen_resource = True
          elif line.startswith("incompatibleResourcePacks:"):
              updated.append("incompatibleResourcePacks:[]")
              seen_incompatible = True
          elif line.startswith("key_key.modmenu.open_menu:"):
              updated.append("key_key.modmenu.open_menu:key.keyboard.m")
          else:
              updated.append(line)

      if not seen_resource:
          updated.append(f"resourcePacks:{json.dumps(resource_packs)}")
      if not seen_incompatible:
          updated.append("incompatibleResourcePacks:[]")
      if not any(line.startswith("key_key.modmenu.open_menu:") for line in updated):
          updated.append("key_key.modmenu.open_menu:key.keyboard.m")

      options_path.parent.mkdir(parents=True, exist_ok=True)
      options_path.write_text("\n".join(updated) + "\n", encoding="utf-8")

      modmenu_path = pack_root / "overrides" / "config" / "modmenu.json"
      if modmenu_path.exists():
          modmenu = json.loads(modmenu_path.read_text(encoding="utf-8"))
      else:
          modmenu = {}
      modmenu["mods_button_style"] = "classic"
      modmenu["game_menu_button_style"] = "replace"
      modmenu["mod_count_location"] = "title_screen_and_mods_button"
      modmenu["modify_title_screen"] = True
      modmenu["modify_game_menu"] = True
      modmenu_path.parent.mkdir(parents=True, exist_ok=True)
      modmenu_path.write_text(json.dumps(modmenu, separators=(",", ":")) + "\n", encoding="utf-8")
      PY

            (
              cd "$workdir/pack"
              python3 - "$out/${mrpackFileName}" <<'PY'
      import pathlib
      import sys
      import zipfile

      dest = pathlib.Path(sys.argv[1])
      root = pathlib.Path(".")
      with zipfile.ZipFile(dest, "w", compression=zipfile.ZIP_DEFLATED) as archive:
          for path in sorted(root.rglob("*")):
              if path.is_file():
                  info = zipfile.ZipInfo(path.as_posix())
                  info.compress_type = zipfile.ZIP_DEFLATED
                  info.date_time = (1980, 1, 1, 0, 0, 0)
                  info.external_attr = 0o100644 << 16
                  archive.writestr(info, path.read_bytes())
      PY
            )

            runHook postInstall
    '';
  }
