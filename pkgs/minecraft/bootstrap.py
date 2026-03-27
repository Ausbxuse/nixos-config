#!/usr/bin/env python3

import base64
import io
import json
import sys
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path


API = "https://api.modrinth.com/v2"
USER_AGENT = "nixos-config-minecraft-bootstrap/1.0"
MINECRAFT_VERSION = "1.21.7"
INSTANCE_NAME = "Fabulously Optimized 1.21.7"
BASE_PACK_SLUG = "fabulously-optimized"

REQUESTS = [
    ("mod", "Jade"),
    ("mod", "Zoomify"),
    ("mod", "Simple Voice Chat"),
    ("mod", "Chat Heads"),
    ("mod", "Smooth Scrolling"),
    ("mod", "3D Skin Layers"),
    ("mod", "AppleSkin"),
    ("mod", "Better Statistics Screen"),
    ("mod", "Capes"),
    ("mod", "Controlify"),
    ("mod", "Distant Horizons"),
    ("mod", "MiniHUD"),
    ("mod", "Mod Menu"),
    ("mod", "Modern UI"),
    ("mod", "Mouse Tweaks"),
    ("mod", "Xaero's World Map"),
    ("mod", "Visible Traders"),
    ("mod", "Tweakeroo"),
    ("mod", "TweakerMore"),
    ("mod", "Status Effect Bars"),
    ("mod", "Sound Physics Remastered"),
    ("mod", "Roughly Enough Items"),
    ("mod", "Shulker Box Tooltip"),
    ("mod", "Architectury API"),
    ("mod", "MaLiLib"),
    ("mod", "TCDCommons API"),
    ("resourcepack", "Fresh Animations"),
    ("resourcepack", "XK Redstone Display"),
    ("shader", "MakeUp - Ultra Fast"),
]

PROJECT_OVERRIDES = (
    {
        ("mod", "Modern UI"): "modernui-mc-mvus",
    }
    if MINECRAFT_VERSION == "1.21.11"
    else {}
)

FACETS = {
    "mod": "project_type:mod",
    "modpack": "project_type:modpack",
    "resourcepack": "project_type:resourcepack",
    "shader": "project_type:shader",
}

LOADERS = {
    "mod": ["fabric"],
    "modpack": ["fabric"],
    "resourcepack": ["minecraft"],
    "shader": ["iris", "optifine"],
}

DIRECTORIES = {
    "mod": "mods/",
    "resourcepack": "resourcepacks/",
    "shader": "shaderpacks/",
}


def api_get(path, query=None):
    url = API + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)


def download_bytes(url):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req) as resp:
        return resp.read()


def sri_sha512(hex_digest):
    return "sha512-" + base64.b64encode(bytes.fromhex(hex_digest)).decode("ascii")


def pick_version(versions):
    rank = {"release": 0, "beta": 1, "alpha": 2}
    best_rank = min(rank.get(version.get("version_type"), 9) for version in versions)
    candidates = [
        version
        for version in versions
        if rank.get(version.get("version_type"), 9) == best_rank
    ]
    return max(candidates, key=lambda version: version.get("date_published", ""))


def parse_numeric_version(version):
    parts = []
    for segment in version.split("."):
        number = ""
        for char in segment:
            if char.isdigit():
                number += char
            else:
                break
        parts.append(int(number or "0"))
    return tuple(parts)


def pick_file(version):
    for file in version["files"]:
        if file.get("primary"):
            return file
    return version["files"][0]


def search_project(kind, query):
    override_slug = PROJECT_OVERRIDES.get((kind, query))
    if override_slug is not None:
        return api_get(f"/project/{override_slug}")

    hits = api_get(
        "/search",
        {
            "query": query,
            "limit": "10",
            "index": "relevance",
            "facets": json.dumps([[FACETS[kind]]]),
        },
    )["hits"]
    if not hits:
        raise RuntimeError(f'No Modrinth project found for "{query}"')

    wanted = query.casefold()
    exact = [
        hit
        for hit in hits
        if hit.get("title", "").casefold() == wanted
        or hit.get("slug", "").casefold() == wanted
    ]
    chosen = exact[0] if exact else hits[0]
    return api_get(f'/project/{chosen["slug"]}')


def compatible_versions(project_id, kind):
    query = {
        "game_versions": json.dumps([MINECRAFT_VERSION]),
    }
    if kind != "modpack":
        query["loaders"] = json.dumps(LOADERS[kind])
    return api_get(f"/project/{project_id}/version", query)


def quote(value):
    return json.dumps(value)


def render_entry(entry):
    return "\n".join(
        [
            "    {",
            f'      filename = {quote(entry["filename"])};',
            f'      path = {quote(entry["path"])};',
            f'      url = {quote(entry["url"])};',
            f'      hash = {quote(entry["hash"])};',
            "    }",
        ]
    )


def render_sources(base_file, fabric_loader_version, entries):
    rendered_entries = "\n".join(render_entry(entry) for entry in entries)
    return f"""\
{{
  instanceName = {quote(INSTANCE_NAME)};

  baseMrpack = {{
    url = {quote(base_file["url"])};
    hash = {quote(base_file["hash"])};
  }};

  dependencies = {{
    minecraft = {quote(MINECRAFT_VERSION)};
    "fabric-loader" = {quote(fabric_loader_version)};
  }};

  files = [
{rendered_entries}
  ];
}}
"""


def main():
    if len(sys.argv) > 2:
        raise SystemExit("usage: minecraft-bootstrap [target-sources.nix]")

    target = (
        Path(sys.argv[1])
        if len(sys.argv) == 2
        else Path.cwd() / "modules/home/minecraft/sources.nix"
    )

    base_project = api_get(f"/project/{BASE_PACK_SLUG}")
    base_versions = compatible_versions(base_project["id"], "modpack")
    if not base_versions:
        raise RuntimeError(
            f"No compatible Fabulously Optimized release found for {MINECRAFT_VERSION}"
        )

    base_version = pick_version(base_versions)
    base_file = pick_file(base_version)
    base_bytes = download_bytes(base_file["url"])
    with zipfile.ZipFile(io.BytesIO(base_bytes)) as archive:
        index = json.loads(archive.read("modrinth.index.json"))

    base_entry = {
        "url": base_file["url"],
        "hash": sri_sha512(base_file["hashes"]["sha512"]),
    }

    fabric_loader_version = index["dependencies"].get("fabric-loader")
    if not fabric_loader_version:
        raise RuntimeError("Fabulously Optimized version does not expose fabric-loader")
    fabric_loader_version = max(
        fabric_loader_version,
        "0.17.0",
        key=parse_numeric_version,
    )

    base_paths = {entry["path"] for entry in index.get("files", [])}
    base_dependency_ids = {
        dep["project_id"]
        for dep in base_version.get("dependencies", [])
        if dep.get("project_id")
    }

    resolved_entries = []
    files_by_path = {}

    for entry in index.get("files", []):
        relative_path = entry["path"]
        directory, filename = relative_path.rsplit("/", 1)
        files_by_path[relative_path] = {
            "filename": filename,
            "path": f"{directory}/",
            "url": entry["downloads"][0],
            "hash": sri_sha512(entry["hashes"]["sha512"]),
        }

    skipped = []
    unsupported = []

    for kind, query in REQUESTS:
        project = search_project(kind, query)
        if project["id"] in base_dependency_ids:
            skipped.append((query, project["slug"], "already included in Fabulously Optimized"))
            continue

        versions = compatible_versions(project["id"], kind)
        if not versions:
            unsupported.append((query, project["slug"]))
            continue

        version = pick_version(versions)
        file = pick_file(version)
        target_path = f'{DIRECTORIES[kind]}{file["filename"]}'
        if target_path in files_by_path or target_path in base_paths:
            skipped.append((query, project["slug"], "already included in Fabulously Optimized"))
            continue
        files_by_path[target_path] = {
            "filename": file["filename"],
            "path": DIRECTORIES[kind],
            "url": file["url"],
            "hash": sri_sha512(file["hashes"]["sha512"]),
        }
        skipped.append((query, project["slug"], version["version_number"]))

    resolved_entries = [files_by_path[path] for path in sorted(files_by_path)]

    target.write_text(
        render_sources(base_entry, fabric_loader_version, resolved_entries),
        encoding="utf-8",
    )

    print(f"Wrote {target}")
    print(f"Base pack: {base_project['title']} {base_version['version_number']}")
    skipped_in_base = [
        item for item in skipped if item[2] == "already included in Fabulously Optimized"
    ]
    if skipped_in_base:
        print("Skipped addons already included in Fabulously Optimized:")
        for query, slug, reason in skipped_in_base:
            print(f"  - {query} ({slug}): {reason}")
    if unsupported:
        print(f"Skipped addons with no {MINECRAFT_VERSION} build:")
        for query, slug in unsupported:
            print(f"  - {query} ({slug})")
    print("Pinned addons:")
    for entry in resolved_entries:
        print(f"  - {entry['path']}{entry['filename']}")


if __name__ == "__main__":
    main()
