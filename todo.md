1. Set up auto-backup to external drive — udev + systemd auto-rsync on plug-in
2. Windows recovery USB + update BIOS — for razy
3. secure boot

# razy specific issues

1. no auto brightness
2. does not dim before turn off screen
3. power manangement
4. do not disturb button
5. external monitor very laggy in input and screen refresh rate.

# host

1. rounded corners not applied in new host
2. harden syncthing deviceid with sops
3. recovery drive and auto backup on plugin
4. rename to "nix-config"
5. milky git source integration
6. yazi mimetypes
7. local llm easy bootstrap (possibly needing python template in nixos-conifg for teh cuda runtime for future reuse.)

# IMPORTANT!

1. recieve only `Phone` in syncthing
2. laggy monitor on razy
3. zsh histsory loss
4. recovery usb backup failed
5. disaster recovery design and guide
6. user name customization in .#install script
7. provision should also update the target's nixos-config. also target nixos-config needs to be proper git please
8. provision nix-secrets should install to ~/src/private/nix-secrets instead of /tmp/nix-secrets
