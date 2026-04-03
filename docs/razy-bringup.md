# Razer Blade 16 (`razy`) Bring-Up Notes

This document records the actual debugging and fix path for `razy`, a Razer Blade 16 (`RZ09-0581`) running NixOS from this repo.

It is intentionally practical rather than polished. The point is to explain:

- what was broken
- what hypotheses were wrong
- what finally worked
- which parts are real fixes vs temporary workarounds
- what we later removed again

## Scope

This bring-up covered multiple issues on a very new Panther Lake laptop:

- internal audio did not enumerate
- brightness/backlight control was unreliable
- GDM monitor scaling was not applied
- suspend/resume was unstable
- GNOME wallpaper state after lid resume was inconsistent

The hardest issue by far was internal audio.

## Machine

- Hostname: `razy`
- Vendor: `Razer`
- Product: `Blade 16 - RZ09-0581`
- Platform: Intel Panther Lake
- Internal audio shape discovered during debugging:
  - `rt721`
  - `rt1320`
  - PCH DMIC present

## Initial Audio Symptoms

The original failure mode was:

- GNOME/PipeWire showed dummy output or only NVIDIA HDMI audio
- no usable internal speaker or mic
- `aplay -l` and `arecord -l` often showed no internal card
- kernel logs showed SOF firmware booting, then failing during topology load

The most important early failure looked like this:

```text
loading topology: intel/sof-ipc4-tplg/sof-ptl-rt721-2ch.tplg
Topology: ABI 3:29:1 Kernel ABI 3:23:1
error: can't connect DAI alh-copier.Capture-SmartMic.0 stream Capture-SmartMic
failed to add widget type 28 name : alh-copier.Capture-SmartMic.0
sof_sdw: failed to instantiate card -22
```

At that point the system never brought up a real `sof-soundwire` card.

## Early Hypotheses And Dead Ends

Several ideas were reasonable, but turned out to be incomplete or wrong.

### 1. "Maybe this is just missing firmware/topology files"

This was partly true early on, but not the real final blocker.

There was no true upstream `sof-ptl-rt721-2ch.tplg` in the shipped firmware set, and we temporarily experimented with compatibility shims. That helped reveal later failures, but it was not the real fix.

### 2. "Maybe the SOF ABI mismatch is the whole problem"

The mismatch was real:

- topology ABI: `3:29:1`
- kernel ABI: `3:23:1`

We spent time checking:

- upstream Linux
- `thesofproject/linux`
- public `sof-bin` PTL releases
- reports from Ubuntu, Fedora, SOF upstream, and others

This was useful context, but it did not fully explain the observed behavior.

Why:

- some newer Intel laptops still enumerate a working card despite the same mismatch
- `razy` was failing on a much more specific path: `Capture-SmartMic.0`

So the ABI mismatch was suspicious, but not sufficient to explain the actual board failure.

### 3. "Maybe the right fix is a different monolithic PTL topology"

We tried multiple topology-focused experiments:

- plain `rt721`
- synthetic `rt721-2ch` shims
- the closest upstream `rt722 + rt1320` PTL topology

These were valuable diagnostics because they moved the failure:

- from `Capture-SmartMic`
- to `SDW0-Playback`

That proved the active topology really mattered.

But it also proved there was no packaged monolithic PTL topology in the current firmware set that matched this Razer board cleanly.

### 4. "Maybe this is purely user-space"

It was not.

We checked PipeWire, WirePlumber, ALSA visibility, module reloads, and various runtime probes. Those were useful for narrowing state, but the decisive failures were always in the kernel-side SOF/SoundWire topology path.

## What The Real Problem Turned Out To Be

The actual fix was not "find the correct monolithic topology file."

The real problem was that the system kept falling back onto the wrong monolithic PTL topology path instead of staying on split function topologies.

Two observations mattered:

1. The failing monolithic path kept pulling in `Capture-SmartMic`, even though runtime descriptors on this machine did not support the expected SmartMic path in the way the chosen topology expected.

2. The SOF function-topology selector was too brittle for this board:
   - unrelated links such as BT offload could force fallback
   - plain `SDW<port>-Playback/Capture` names were not being mapped back to the right SDCA function fragments, even though the BE IDs already implied the function type

Once we stopped fighting about fake monolithic files and instead forced the machine onto split function topologies, the audio stack finally came up.

## The Actual Working Audio Fix

The working fix lives in:

- [machines/razy/nixos.nix](/home/zhenyu/src/public/nixos-config/machines/razy/nixos.nix)
- [machines/razy/patches/ptl-razer-blade16-rt721-rt1320.patch](/home/zhenyu/src/public/nixos-config/machines/razy/patches/ptl-razer-blade16-rt721-rt1320.patch)

### Kernel-side machine description

The patch adds a Razer-specific PTL machine description:

- DMI match for `Razer Blade 16 - RZ09-0581`
- custom PTL SoundWire machine entry for:
  - `rt721`
  - `rt1320`
  - link 3
- SSID quirk for:
  - `0x1a58:0x3010`
- quirk bits:
  - `SOC_SDW_SIDECAR_AMPS`
  - `SOC_SDW_PCH_DMIC`

This gives the kernel an explicit board model instead of hoping a near match will work.

### Forcing split function topologies

The crucial step was changing the Razer PTL machine entry to use:

```c
.sof_tplg_filename = "sof-ptl-dummy.tplg",
.get_function_tplg_files = sof_sdw_get_tplg_files,
```

This intentionally avoids a broken monolithic fallback path and keeps SOF on split function topologies.

### Making split topology selection robust enough

The patch also modifies `sof-function-topology-lib.c` to do two important things:

1. Ignore `SSP*-BT` links during function-topology selection.

These links are unrelated to the internal speaker/mic path and were able to push topology selection onto the wrong fallback path.

2. Infer function fragments from BE IDs even when the dai links still have plain names like:

- `SDW3-Playback`
- `SDW3-Capture`

Specifically:

- jack BE IDs map to the generic SDCA jack fragment
- amp BE IDs map to the SDCA amp fragment

This was the missing bridge between the board's dai links and the split topology fragments that actually existed in firmware.

## The First Known-Good Boot

The successful boot stopped loading the old fake monolithic path and instead loaded split fragments like:

```text
Topology file: function topologies
Using function topologies instead intel/sof-ipc4-tplg/sof-ptl-dummy-2ch.tplg
loading topology 0: intel/sof-ipc4-tplg/sof-sdca-jack-id0.tplg
loading topology 1: intel/sof-ipc4-tplg/sof-sdca-1amp-id2.tplg
loading topology 2: intel/sof-ipc4-tplg/sof-ptl-dmic-2ch-id3.tplg
loading topology 3: intel/sof-ipc4-tplg/sof-hdmi-pcm5-id5.tplg
```

The earlier failing nodes disappeared:

- no more `Capture-SmartMic.0`
- no more `SDW0-Playback`

And the user confirmed that audio worked.

## Why This Took So Long

The hard part was that several things were true at once:

- the laptop is a very new Intel platform
- the board needed a specific machine description
- the available packaged PTL topology names were misleading
- the topology ABI mismatch was real, but not the only issue
- several experimental changes moved the failure without actually fixing the board

So the debugging path had to separate:

- useful movement in the failure
- from real causal fixes

## What Was Removed Again

Once audio worked, several earlier workarounds were dropped because they were no longer needed or were clearly the wrong layer.

Removed:

- fake `sof-ptl-rt721-2ch.tplg` compatibility overlays
- topology renaming shims
- `bt_link_mask=0` workaround in modprobe config
- redundant typed-dailink forcing path
- the long initrd crypto module override that was only needed to make a custom dev kernel package build

This repo should prefer the minimal patch set that actually explains the success.

## Kernel Choice

The first known-good audio boot happened with a SOF development kernel source:

- `thesofproject/linux`
- `topic/sof-dev`
- version `7.0.0-rc3`

That was later switched back toward nixpkgs stock kernel packaging to remove unnecessary divergence.

Important caution:

- the known-good runtime proof happened on the SOF dev kernel path
- switching back to nixpkgs latest kernel is a cleanup step and should be treated as a new validation point

In other words:

- the patch logic is the important part
- but the only fully proven working combination during debugging was still the dev-kernel path

## Other `razy` Issues Fixed Along The Way

### Brightness

Brightness was fixed separately from audio.

The important setting is:

```nix
boot.kernelParams = [ "xe.enable_dpcd_backlight=1" ];
```

That is the actual backlight fix. `brightnessctl` is optional convenience, not part of the kernel fix itself.

### GDM scaling

GDM needed its own monitor configuration copied into the GDM home directory:

- [machines/razy/gdm-monitors.xml](/home/zhenyu/src/public/nixos-config/machines/razy/gdm-monitors.xml)
- installed into `/var/lib/gdm/.config/monitors.xml`

This is separate from the user session GNOME scaling.

### Suspend instability

Suspend/resume was unstable while experimenting with the new GPU/kernel stack.

The immediate mitigation was:

```nix
hardware.nvidia.powerManagement.finegrained = lib.mkForce false;
```

That was kept as a pragmatic stability choice.

### Blue wallpaper after lid resume

The blue background after resume was not caused by the static GNOME wallpaper settings anymore. The most likely remaining cause was the `azwallpaper` GNOME extension overriding wallpaper state and resuming badly.

That extension was disabled in:

- [modules/home/gnome/dconf.nix](/home/zhenyu/src/public/nixos-config/modules/home/gnome/dconf.nix)

This leaves GNOME's declarative wallpaper settings as the only wallpaper source.

## Current Practical State

At the end of this debugging pass:

- internal audio works
- the fake topology shims are gone
- the real fix is concentrated in one host patch plus host kernel selection
- brightness works
- GDM scaling is configured
- NVIDIA fine-grained PM is disabled for stability
- wallpaper handling is simpler again

## What Still Deserves Future Cleanup

### 1. Validate stock nixpkgs kernel

If the same patch works on nixpkgs latest kernel, that is the preferred long-term state.

That should be treated as a separate validation, not assumed automatically.

### 2. Upstream the audio fix properly

The patch is now coherent, but it is still local bring-up work.

Good next upstream step:

- reduce it to the minimal causally necessary changes
- attach the successful logs
- explain why the split-function-topology path is required for this board

### 3. Re-check ALSA user-space visibility

During debugging there was at least one odd state where:

- `/proc/asound/cards` showed the card
- but `aplay -l` and `arecord -l` did not

That inconsistency was secondary once real audio worked, but it is still worth cleaning up if it reappears.

## Files Most Relevant To `razy`

- [machines/razy/nixos.nix](/home/zhenyu/src/public/nixos-config/machines/razy/nixos.nix)
- [machines/razy/patches/ptl-razer-blade16-rt721-rt1320.patch](/home/zhenyu/src/public/nixos-config/machines/razy/patches/ptl-razer-blade16-rt721-rt1320.patch)
- [machines/razy/gdm-monitors.xml](/home/zhenyu/src/public/nixos-config/machines/razy/gdm-monitors.xml)
- [machines/razy/power.nix](/home/zhenyu/src/public/nixos-config/machines/razy/power.nix)
- [modules/home/gnome/dconf.nix](/home/zhenyu/src/public/nixos-config/modules/home/gnome/dconf.nix)

## Short Version

The audio fix was not "find the right PTL topology filename."

It was:

- give the kernel a real Razer-specific `rt721 + rt1320` PTL board description
- stop monolithic topology fallback
- force split function topologies
- make split topology selection tolerant of BT offload links
- infer jack/amp fragments from BE IDs when dai link names are still plain `SDW<port>-*`

That is what finally made the machine behave like a real `sof-soundwire` laptop instead of dying on `Capture-SmartMic.0`.
