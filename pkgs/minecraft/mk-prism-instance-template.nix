{
  lib,
  pkgs,
}:
{
  sources,
  javaPackage ? pkgs.jdk21,
  minMemMiB ? 2048,
  maxMemMiB ? 8192,
}: let
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

  resourcePackFiles = lib.filter (file: file.path == "resourcepacks/") sourceFiles;

  resourcePackList =
    ["vanilla"]
    ++ map (file: "file/${file.filename}") resourcePackFiles;

  baseMrpack = pkgs.fetchurl {
    url = sources.baseMrpack.url;
    hash = sources.baseMrpack.hash;
  };

  componentUidMap = {
    minecraft = "net.minecraft";
    "fabric-loader" = "net.fabricmc.fabric-loader";
    "quilt-loader" = "org.quiltmc.quilt-loader";
    forge = "net.minecraftforge";
    neoforge = "net.neoforged";
  };

  components =
    lib.mapAttrsToList (name: version: {
      uid = componentUidMap.${name} or name;
      inherit version;
    })
    sources.dependencies;

  mmcPack = builtins.toJSON {
    formatVersion = 1;
    inherit components;
  };

  instanceCfg = ''
[General]
AutoCloseConsole=false
AutomaticJava=false
CloseAfterLaunch=false
ConfigVersion=1.3
EnableFeralGamemode=false
EnableMangoHud=false
InstanceType=OneSix
JavaPath=${javaPackage}/bin/java
JoinServerOnLaunch=false
JvmArgs=
LogPrePostOutput=true
ManagedPack=false
MaxMemAlloc=${toString maxMemMiB}
MinMemAlloc=${toString minMemMiB}
OverrideJavaLocation=true
OverrideMemory=true
RecordGameTime=true
ShowConsole=false
ShowConsoleOnError=true
ShowGameTime=true
iconKey=default
name=${sources.instanceName}
notes=
  '';
in
  pkgs.stdenvNoCC.mkDerivation {
    pname = "prism-instance-template";
    version = sources.dependencies.minecraft;

    nativeBuildInputs = with pkgs; [
      python3
      unzip
    ];

    dontUnpack = true;

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/minecraft"
      tmpdir="$(mktemp -d)"

      unzip -qq "${baseMrpack}" -d "$tmpdir/base"

      for override_dir in overrides client-overrides; do
        if [ -d "$tmpdir/base/$override_dir" ]; then
          cp -a "$tmpdir/base/$override_dir/." "$out/minecraft/"
        fi
      done

      # Fabulously Optimized ships runtime defaults under config/modpack_defaults.
      # Copy those into the live config tree so mods actually read them on launch.
      if [ -d "$out/minecraft/config/modpack_defaults/config" ]; then
        mkdir -p "$out/minecraft/config"
        cp -a "$out/minecraft/config/modpack_defaults/config/." "$out/minecraft/config/"
      fi

      if [ -f "$out/minecraft/config/modpack_defaults/options.txt" ]; then
        cp "$out/minecraft/config/modpack_defaults/options.txt" "$out/minecraft/options.txt"
        chmod u+w "$out/minecraft/options.txt"
      fi

      ${lib.concatMapStringsSep "\n" (file: ''
        target_dir="$out/minecraft/${file.path}"
        mkdir -p "$target_dir"
        cp "${file.src}" "$target_dir/${file.filename}"
        chmod u+w "$target_dir/${file.filename}"
      '') sourceFiles}

      options_file="$out/minecraft/options.txt"
      python3 - "$options_file" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
resource_packs = ${builtins.toJSON resourcePackList}

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

path.write_text("\n".join(updated) + "\n", encoding="utf-8")
PY

      modmenu_config="$out/minecraft/config/modmenu.json"
      if [ -f "$modmenu_config" ]; then
        python3 - "$modmenu_config" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["mods_button_style"] = "classic"
data["game_menu_button_style"] = "replace"
data["mod_count_location"] = "title_screen_and_mods_button"
data["modify_title_screen"] = True
data["modify_game_menu"] = True
path.write_text(json.dumps(data, separators=(",", ":")) + "\n", encoding="utf-8")
PY
      fi

      cp ${pkgs.writeText "mmc-pack.json" mmcPack} "$out/mmc-pack.json"
      cp ${pkgs.writeText "instance.cfg" instanceCfg} "$out/instance.cfg"

      runHook postInstall
    '';
  }
