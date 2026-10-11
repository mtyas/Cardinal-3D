# Embedded Windows host

The target is one Windows application using Quest Link/OpenXR. Cardinal is a library inside that process, not a second executable. This is not an Android port.

## Current evidence

With the nine-module test patch, the old TCP artwork stream delivered 3.87 control snapshots/second with a 1,966,080-byte backlog. Negotiated lossless compression delivered 32.33 snapshots/second with a 44,937-byte backlog in the same 72 Hz polling test. This fixes one measured bottleneck before the host migration; headset latency still needs verification.

## Integration boundary

An initial Windows engine DLL and Godot extension are now implemented in
`embedded/`. Local tests generate real Cardinal audio inside Godot, round-trip
native patches, discover all 1,412 models from 84 registered plugin families, and exercise cable removal,
module addition and undo through a direct in-process command adapter. This is
an experimental target, not yet a replacement for the working VR application.
The offscreen graphics variant also reuses original NanoVG module artwork and
context menus inside the same process. Panel and metadata work run alongside
the native audio thread without the former UI gate producing silent blocks.
The full registry factory audit instantiates every module and widget without
attaching it to the playing audio engine. It found 11,121 knob controls: 9,387
have original SVG body colours; the remaining 1,734 retain their native custom
faces. This audit checks factories and descriptors, not every module's GPU drawing
or behavior in a headset. Packaging uses Cardinal's complete upstream asset list,
including generated Surge data and assets outside conventional `res` folders.

The embedded frontend includes output-device selection, output volume, MIDI
input selection and a release-all-notes action. A preallocated MIDI queue delivers
short messages to native Host MIDI; note-on, note-off and panic are verified.
MIDI output and SysEx are not implemented. Actual MIDI hardware remains untested.
Recovery saves every two minutes and on orderly shutdown, retains the previous
copy, and restores the changed patch after restart. Settings and recovery live
separately from the tested Cardinal host.

See `embedded/README.md` for the isolated build/check commands and remaining
acceptance work. The confirmed runtime is tagged `quest2-tested-2026-10-10`.

Build Cardinal's engine, module registry, patch manager and history as static libraries linked into a Godot GDExtension. A single extension owns CardinalPluginContext and its lifetime. The audio callback processes the unchanged engine with preallocated buffers. Godot reads the latest immutable control state and submits validated commands through a bounded queue. Neither artwork generation nor filesystem operations may run in the audio callback.

Keep one OpenXR/Godot window. For modules with custom drawing, initially retain an offscreen NanoVG compatibility renderer inside this same process. Render it independently of control state so a slow custom scope cannot delay knobs or LEDs. Replace compatibility surfaces incrementally with native 3D displays; preserve original widget colours and behavior during conversion.

## Host feature acceptance checklist

Each item must be checked against the pinned Cardinal host before removing the separate executable:

- Audio driver, output/input device, channels, sample rate and buffer size; hot unplug and device changes.
- MIDI input/output device selection, mapping and clock/transport behavior.
- New/open/save/save-as, autosave/recovery, recent files and template patch; retain native VCV patch compatibility.
- Undo/redo, cable replacement, duplicate/delete, insertion, selection and clipboard actions.
- Module presets, randomize/reset/bypass and every module's native contextual menu, including plugin-specific actions.
- Module browser search, favorites, tags and model discovery across the complete registry.
- Host preferences, resource/plugin lookup, UI scaling/themes, CPU meters and safe shutdown.

Expose the native menu tree and host settings through the extension rather than maintaining guessed duplicate menus. Store the current application's settings separately and migrate only supported values. Preserve existing patches and backups during transition.

## Conversion sequence

1. Extract visual metadata from instantiated native widgets, using original SVG fills for knob faces. The initial cached palette extractor and coloured 3D cap are implemented, with checks for transparent layers and pointer exclusion. Gradients use a representative middle stop; detailed artwork and custom/composite knobs still need individual review. Never scan SVG paths at every control update.
2. Extend the module audit across the full pinned registry, retaining explicit fallback for composite/custom controls. Registry availability and 3D coverage are separate checks.
3. Implement an embedded extension with a minimal engine lifecycle and patch round trip, then audio/device selection, then the full command/history/menu API.
4. Compare audio, control and artwork timing against the compressed bridge before retiring the existing host.

## Local builds

Run `scripts/build_local_windows.ps1` with the dedicated `Cardinal3DBuild` WSL distribution. It builds Windows executables locally using the pinned upstream cross compiler. Sources and compiler caches remain in Linux storage at `/root/cardinal3d` and `/root/PawPawBuilds`; the resulting bundle is copied to the checkout's `dist` folder. Docker is not required. The first toolchain build is long; subsequent builds reuse compiled dependencies.

Status on 11 October 2026: the full embedded Windows library builds locally using
the separate `/root/cardinal3d-full` cache and writes `dist/embedded-full`. The
prototype cache remains separate. Native audio, patch/history operations, MIDI
gate/panic, original GL artwork and menus, and Godot headless/desktop startup and
recovery checks pass. The concurrent UI/audio check processed more than 4,500
blocks without silent blocks. These checks do not measure headset latency.

In this PC's workspace, run `Build standalone locally.bat` to build, verify and
copy the result into a fresh runtime directory. `Launch standalone Quest test.bat`
starts that saved copy with Quest Link. It launches only Godot with Cardinal's
engine inside it. `standalone-user` stores its patch recovery and audio settings;
the first launch seeds from `Quest starter.vcv` if present. Future builds never
overwrite the saved runtime's loaded DLLs. The normal Quest launcher still uses
the user-confirmed two-process version, and `Launch tested Quest version.bat`
opens its explicit restore point. Full host feature parity and physical Quest
responsiveness remain acceptance work.

The initial asset audit found 423 named knob SVGs across the full pinned source tree. The palette extractor supplies colours for 377; 46 retain artwork fallback for review. This count describes assets, not converted module models. See `docs/knob-palette-summary.json`; the full local report is `reports/knob-palettes.json`. Re-run with `scripts/audit_knob_palettes.py` and the native `tests/svg_palette_assets.cpp` probe compiled against Rack's pinned NanoSVG headers.
