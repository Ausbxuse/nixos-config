# Syncthing quickstart

Shortest path for getting a device into this repo's Syncthing mesh.

For the full model and edge cases, see [syncthing.md](./syncthing.md).

---

## What this repo syncs

Managed hosts get these folders from [`modules/home/syncthing.nix`](../modules/home/syncthing.nix):

- `vault` -> `~/vault`
- `media` -> `~/Media`
- `documents` -> `~/Documents`
- `phone-dcim` -> `~/Media/Phone` as `receiveonly`

`razy` is the introducer. New repo-managed hosts only need to know about
`razy`; Syncthing learns the rest of the mesh from it.

---

## Case 1: new repo-managed laptop / desktop

1. Install the host normally.

```bash
nix run github:ausbxuse/nix-config#install -- --host NEWHOST --nixos --home
```

2. From a trusted peer that already has `nix-secrets`, enroll it.

```bash
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt \
  nix run ~/src/public/nix-config#enroll -- NEWHOST zhenyu@<NEWHOST_IP>
```

3. Verify on the new host:

```bash
systemctl --user status syncthing
syncthing cli show system | jq -r .myID
ls ~/vault ~/Media ~/Documents
```

What enrollment does:

- generates and pins a Syncthing cert/key for the host
- stores the device ID in `nix-secrets/hosts.nix`
- rebuilds the host so Syncthing starts with the pinned identity

After that, `razy` introduces the host to the rest of the mesh.

---

## Case 2: first host or old pre-enroll host

If the machine already has a working Syncthing identity and you want to
preserve it across reinstalls:

1. Read the current device ID:

```bash
syncthing cli show system | jq -r .myID
```

2. Encrypt `~/.local/state/syncthing/cert.pem` and `key.pem` into
   `nix-secrets/secrets.yaml` as:

- `syncthing-cert-<hostname>`
- `syncthing-key-<hostname>`

3. Set `syncthing.deviceId` for that host in `nix-secrets/hosts.nix`.
4. Rebuild.

The complete manual procedure is in [syncthing.md](./syncthing.md).

---

## Case 3: Android phone

Phones are manual. This repo does not manage them declaratively.

1. Install Syncthing on the phone.
2. Add the phone to `razy` in the Syncthing UI.
3. Share `phone-dcim` from the phone's camera directory.
4. Set the phone side of that folder to `send only`.
5. Optionally share `vault` if you want mobile KeePass access.

Important behavior:

- desktops receive `phone-dcim` into `~/Media/Phone`
- local sorting moves files into `~/Media/{Pictures,Videos,Audio}`
- deleting old files from the phone later does not remove the sorted copies

---

## Common checks

```bash
systemctl --user status syncthing
journalctl --user -u syncthing -n 100 --no-pager
syncthing cli show system | jq
```

Web UI:

- <http://127.0.0.1:8384>

Look for:

- expected device ID
- `razy` connected
- folders `vault`, `media`, `documents`, `phone-dcim`
- no repeated "out of sync" or identity mismatch errors
