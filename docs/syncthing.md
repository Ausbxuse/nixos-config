# Syncthing guide

Operational guide for this repo's Syncthing setup: what is synced, how
devices join, and what to do for different host types.

For the shortest happy path, see [syncthing-quickstart.md](./syncthing-quickstart.md).

---

## Topology

This repo's Syncthing configuration lives in
[`modules/home/syncthing.nix`](../modules/home/syncthing.nix).

Key design points:

- Repo-managed hosts run Syncthing declaratively through home-manager.
- Each managed host can have a pinned Syncthing identity:
  `syncthing.deviceId` in `nix-secrets/hosts.nix` plus encrypted cert/key in
  `nix-secrets`.
- `razy` is the introducer. Managed clients declare only introducer peers,
  then Syncthing learns the rest of the mesh through introductions.
- Folder paths are stable and pre-created so first boot does not depend on
  manual directory setup.

This keeps reinstalls stable: if the same host key and pinned Syncthing
cert/key come back, the device keeps the same Syncthing identity.

---

## Folder model

Managed hosts declare four folders.

### `vault`

- Path: `~/vault`
- Purpose: KeePassXC database, keyfile, notes
- Mode: normal bidirectional sync
- Versioning: `simple`, keep `10`

Use this for:

- `vault.kdbx`
- `vault.kdbx.key`
- markdown notes and other small personal files tied to the vault

### `media`

- Path: `~/Media`
- Purpose: personal media library
- Mode: normal bidirectional sync
- Special rule: ignores `/Phone`

The `/Phone` subdirectory is excluded because phone ingest has its own
folder with different semantics.

### `documents`

- Path: `~/Documents`
- Purpose: general document sync
- Mode: normal bidirectional sync

### `phone-dcim`

- Path: `~/Media/Phone`
- Purpose: phone camera ingest landing zone
- Mode on managed hosts: `receiveonly`

Expected flow:

1. phone uploads camera files
2. desktop receives them into `~/Media/Phone`
3. `phone-media-sort` copies them into `~/Media/Pictures`,
   `~/Media/Videos`, or `~/Media/Audio`
4. phone can later delete its originals without affecting the sorted copy

---

## Device cases

### 1. New repo-managed host

This is the standard path for a new laptop or desktop tracked in this repo.

### Install

```bash
nix run github:ausbxuse/nix-config#install -- --host NEWHOST --nixos --home
```

### Enroll from a trusted existing peer

```bash
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt \
  nix run ~/src/public/nix-config#enroll -- NEWHOST zhenyu@<NEWHOST_IP>
```

Enrollment handles the important Syncthing state:

1. generates a fresh Syncthing cert/key pair for the new host
2. stores them in `nix-secrets/secrets.yaml`
3. records `syncthing.deviceId` in `nix-secrets/hosts.nix`
4. rebuilds the host so Syncthing starts with that pinned identity

Result:

- the device keeps the same Syncthing identity across reinstalls
- `razy` introduces it to the rest of the mesh
- `vault`, `Media`, `Documents`, and `Media/Phone` exist immediately

### Verify

```bash
systemctl --user status syncthing
syncthing cli show system | jq -r .myID
ls ~/vault ~/Media ~/Documents
```

In the web UI at <http://127.0.0.1:8384>, confirm:

- the device is connected to `razy`
- folders are present
- shares begin syncing

### 2. Existing host that predates enrollment

Use this when a machine already has a working Syncthing identity and you
want to preserve it instead of generating a new one.

### Extract the current identity

```bash
CERT=~/.local/state/syncthing/cert.pem
KEY=~/.local/state/syncthing/key.pem
syncthing cli show system | jq -r .myID
```

### Encrypt cert and key into `nix-secrets`

```bash
jq -Rs . < "$CERT" > /tmp/cert.json
jq -Rs . < "$KEY" > /tmp/key.json

cd ~/src/private/nix-secrets
sops set secrets.yaml '["syncthing-cert-NEWHOST"]' "$(cat /tmp/cert.json)"
sops set secrets.yaml '["syncthing-key-NEWHOST"]'  "$(cat /tmp/key.json)"
rm /tmp/cert.json /tmp/key.json
```

### Record the device ID

Set the host entry in `nix-secrets/hosts.nix`:

```nix
NEWHOST = {
  syncthing.deviceId = "FULL-DEVICE-ID-HERE";
};
```

If the machine should act as an introducer, also set:

```nix
syncthing.introducer = true;
```

For this repo, that role normally belongs only to `razy`.

### Rebuild and verify

```bash
sudo nixos-rebuild switch --flake .#NEWHOST
systemctl --user restart syncthing
syncthing cli show system | jq -r .myID
```

The final device ID should match the pre-existing one exactly.

### 3. Reinstalling an already enrolled managed host

This is the main reason identity pinning exists.

Expected behavior:

- reinstall the host
- rebuild against the same `machines/defs.nix`
- decrypt the same `syncthing-cert-<hostname>` and `syncthing-key-<hostname>`
- Syncthing comes back with the same device ID

You should not need to re-pair the device in the Syncthing UI.

If the device ID changes after reinstall, the pinned cert/key were not
loaded. Check:

- `journalctl --user -u syncthing`
- presence of the decrypted secret files under `/run/user/<uid>/secrets/`
- matching `syncthing.deviceId` in `nix-secrets/hosts.nix`

### 4. Android phone

The phone is outside this repo. Pair it manually.

Recommended use:

- `phone-dcim` for camera ingest
- `vault` only if you want the KeePass database on mobile too

### Pairing flow

1. Install Syncthing on the phone.
2. Copy the phone device ID.
3. On `razy`, open <http://127.0.0.1:8384>.
4. Add the phone as a device.
5. Share the camera folder as `phone-dcim`.
6. Set the phone side of `phone-dcim` to `send only`.
7. Accept the share on the phone.

Why `send only` matters:

- desktops treat `~/Media/Phone` as a disposable ingest area
- sorting or cleanup on desktops should not propagate destructive changes
  back to the phone's camera roll

### Mobile vault access

If you also share `vault`, keep the same expectations as desktop:

- `vault.kdbx` and `vault.kdbx.key` must both be present
- you still need the vault passphrase

The repo's existing quickstart mentions KeePass2Android Offline as the
expected phone client.

### 5. Other unmanaged devices

If a device is not managed by this repo, pair it manually in the Syncthing
UI like the phone.

Guidelines:

- connect it to `razy` first
- do not assume folder IDs or modes if you create folders manually; match
  the existing folder IDs exactly when attaching to an existing share
- be careful with folder type mismatches:
  `phone-dcim` should stay phone `send only`, desktop `receive only`

For laptops or desktops you intend to keep long term, prefer making them
repo-managed instead of leaving them manual. That preserves device identity
and keeps folder declarations reproducible.

---

## Common operations

### View local status

```bash
systemctl --user status syncthing
journalctl --user -u syncthing -n 100 --no-pager
syncthing cli show system | jq
```

### Open the UI

- <http://127.0.0.1:8384>

Useful checks:

- current device ID
- connected peers
- folder state
- remote device and folder type mismatches

### Create the vault on the first host

Do this only once, on the first host in the mesh:

1. Open KeePassXC.
2. Create `~/vault/vault.kdbx`.
3. Add a strong passphrase.
4. Create `~/vault/vault.kdbx.key`.
5. Leave Syncthing running so both files propagate.

### Join an additional host to an existing vault

1. Bring the host into the mesh.
2. Wait for `~/vault/vault.kdbx` and `~/vault/vault.kdbx.key` to arrive.
3. Open the database with passphrase plus keyfile.

---

## Recommended patterns by folder

Use `vault` for small, high-value personal data.

Use `documents` for things you actively edit on multiple devices.

Use `media` for user-curated media you want mirrored across desktops.

Use `phone-dcim` only as an ingest buffer, not as a permanent library.

Avoid storing large transient build artifacts or frequently rewritten cache
trees inside these folders. They create noisy sync churn and weak recovery
value.

---

## Troubleshooting

### Device ID changed unexpectedly

Likely cause: pinned cert/key not loaded.

Check:

- `nix-secrets/hosts.nix` has the expected `syncthing.deviceId`
- `nix-secrets` contains `syncthing-cert-<hostname>` and `syncthing-key-<hostname>`
- user service logs mention loading the expected cert and key paths

### Host does not see the rest of the mesh

Check whether:

- `razy` is online
- the host can connect to `razy`
- the host has the right device ID pinned
- introducer status is set on `razy`, not just plain peering

Initial introductions depend on the introducer being reachable.

### `phone-dcim` keeps looking out of sync

Usually this is a mode mismatch.

Expected state:

- phone side: `send only`
- managed desktop side: `receive only`

If both sides are normal bidirectional folders, sorting and cleanup will
fight with Syncthing.

### Files disappeared from `~/Media/Phone`

That is expected if local post-processing moved them out of the ingest
folder. Treat `~/Media/Phone` as a landing zone, not the long-term store.

Look in:

- `~/Media/Pictures`
- `~/Media/Videos`
- `~/Media/Audio`
