# New host quick start

One-page runbook for adding a new host to the mesh end-to-end:
install → admit → daily use (passwords + TOTP).

For design rationale see [reproducing-from-scratch.md](./reproducing-from-scratch.md).
For install-CLI detail see [installation.md](./installation.md).

Replace `NEWHOST` with your target hostname.

---

## 1. Install (on the new machine)

Boot the NixOS installer ISO, get network, then:

```bash
nix run github:ausbxuse/nix-config#install -- --host NEWHOST --nixos --home
```

This is an **custom install** — NEWHOST does **not** need to exist in
`machines/defs.nix` yet. The installer prompts for profile, disk, swap,
LUKS passphrase, and runs `disko` + `nixos-install`.

The install uses the public `nix-secrets` stub (no-op) so it **does not
require access to your private secrets repo**. The result is an anonymous
box with the full user environment (KeePassXC, syncthing, everything in
`personal-gnome`) but with no personal data and no decrypted secrets.

Reboot into the installed system when done.

---

## 2. Admit into the mesh (from a trusted peer)

On a peer that already has `nix-secrets` checked out and a working age
identity (e.g. razy):

```bash
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt \
  nix run ~/src/public/nix-config#enroll -- NEWHOST zhenyu@<NEWHOST_IP>
```

The `enroll` app:

| #   | Action                                                                                                                                                                       |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | SSHes to NEWHOST, derives its age key from `/etc/ssh/ssh_host_ed25519_key`                                                                                                   |
| 2   | Promotes `NEWHOST` from public staging defs into `nix-secrets/hosts.nix`, then sets `NEWHOST.sops.ageKey = "age1..."`                                                      |
| 3   | Regenerates `nix-secrets/.sops.yaml`, re-encrypts `secrets.yaml`                                                                                                             |
| 4   | Generates a syncthing cert/key for NEWHOST, encrypts them into `secrets.yaml`, records `NEWHOST.syncthing.deviceId` in `hosts.nix` (first boot comes up with pinned identity) |
| 5   | Pushes NEWHOST's user SSH pubkey to milky (so NEWHOST can pull private repos via `git+ssh://`) — _see "Milky dependency" below_                                              |
| 6   | Triggers `nixos-rebuild switch` on NEWHOST pulling `nix-secrets` from milky                                                                                                  |

When it exits cleanly, NEWHOST has `/run/secrets/` populated, a pinned
syncthing identity, and is a full mesh member.

Commit on the peer:

```bash
cd ~/src/public/nix-config && git add machines/defs.nix && git commit -m "stage removal for NEWHOST"
( cd ~/src/private/nix-secrets && git add hosts.nix .sops.yaml secrets.yaml \
    && git commit -m "add NEWHOST recipient" && git push )
```

### Milky dependency

Step 4 + step 5 assume **milky** (the VPS) is online as the
`nix-secrets` git remote. Until milky is set up:

- Step 4 is a no-op (enroll skips the SSH-key push)
- Step 5 falls back to the local path form:
  `--override-input nix-secrets path:/tmp/nix-secrets` after an rsync

Both behaviors are handled by `enroll` automatically — you do not pass
a flag. Once milky is enrolled the path override is dropped.

---

## 3. Daily use — passwords and TOTP

After step 2, NEWHOST has:

- **KeePassXC** installed
- **syncthing** running with the `vault` folder declared
- `~/vault/` existing but empty (first host ever) or auto-populated by
  syncthing from another mesh peer (subsequent hosts)

### First host in the mesh — create the vault

Open KeePassXC from the application launcher:

1. **Database → New Database**
2. Save as `~/vault/vault.kdbx`
3. Set a strong master passphrase (memorized)
4. **Database → Database Security → Security → Add additional protection →
   Key File → Create**, save as `~/vault/vault.kdbx.key`
5. Leave KeePassXC open; syncthing will pick up the new files on its next
   scan (~10 s).

### Subsequent hosts — unlock the synced vault

Wait for syncthing to sync `~/vault/` from a peer (watch
`~/vault/vault.kdbx` appear). Then:

1. Open KeePassXC → **Database → Open**
2. Select `~/vault/vault.kdbx`
3. Enter passphrase + point at `~/vault/vault.kdbx.key` as the key file

### TOTP codes

TOTP entries live **inside** the KeePassXC database alongside the matching
password entries (no separate Authy/Google Authenticator needed).

To add a TOTP secret to an entry:

1. Open the entry in KeePassXC
2. **Entry → TOTP → Set up TOTP**
3. Paste the shared secret from the site (usually the "enter code manually"
   alternative to the QR code)
4. Save

To read a TOTP code:

1. Click the entry
2. **Ctrl+T** copies the current 6-digit code to clipboard (auto-clears
   after 10 s)

Phone parity: install **KeePass2Android Offline** on the phone, point it
at `~/vault/vault.kdbx` once the phone is a syncthing mesh peer. Same
database, same TOTP entries, same passphrase + keyfile.

### Environment secrets (API keys, etc.)

Non-vault secrets (API keys, tokens) live in `nix-secrets/secrets.yaml`
and are materialized into the shell automatically on login:

```bash
echo "$ANTHROPIC_API_KEY"
echo "$GEMINI_API_KEY"
# ...
```

These come from sops-nix via zsh integration; no manual step.

---

## 4. Verify

```bash
nix run ~/src/public/nix-config#validate-host
sudo ls /run/secrets/               # decrypted secrets
ls ~/vault/                         # vault.kdbx present
systemctl --user status syncthing
```

---

## Cheat sheet

| Task                                  | Command                                                                    |
| ------------------------------------- | -------------------------------------------------------------------------- |
| Fresh install (no defs.nix entry)     | `nix run github:ausbxuse/nix-config#install -- --host HOST --nixos --home` |
| Admit new host to mesh                | `nix run .#enroll -- HOST user@ip`                                         |
| Manually set a host's age key         | `nix run .#admit-host -- --set-host-key HOST age1...`                      |
| Rotate secrets after editing defs.nix | `just rotate-secrets`                                                      |
| Remove a host                         | delete its entry from `machines/defs.nix`, then `just rotate-secrets`      |
| Copy TOTP code                        | select entry in KeePassXC → `Ctrl+T`                                       |
