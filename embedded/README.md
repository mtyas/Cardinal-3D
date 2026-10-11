# Embedded Windows engine — 0.77 beta

This is the engine used by the Windows Quest Link release.
It loads Cardinal DSP, the full 1,412-model registry (or the smaller prototype), native patch
manager, widget metadata and undo history into Godot's process. There is no
Cardinal executable or socket in this target. Original upstream DSP is unchanged.

Build locally with `scripts/build_local_windows.ps1 -Embedded` for the engine-only
variant, or `-EmbeddedGraphics` for the original offscreen graphics backend. Both reuse the
dedicated WSL compiler cache and writes `dist/embedded`; it does not install over
the working VR bundle. Use `-FullRegistry` for the full original graphics library,
with its own `/root/cardinal3d-full` cache and `dist/embedded-full` output.
The normal local build command is unchanged. The builder
needs SCons (`apt-get install scons` in the dedicated build distro). Godot C++
bindings are pinned to `e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77` (4.5 stable,
compatible with the project's 4.5.1 runtime).

Run `scripts/check_embedded.py --godot <Godot console exe> --resources <portable Cardinal folder>`.
Tests use temporary patches/settings and silent Dummy audio output. The native
probe verifies a generated oscillator signal, finite/bounded samples, native
compressed patch round trip, resource colours, module registry, cable removal,
module addition and undo. The Godot probe exercises the registered extension,
the native AudioStreamPlayback callback and actual Godot audio-thread playback
with Dummy output. It also rejects simultaneous playback and refuses closing an
engine while its playback is active. Stop both the AudioStreamPlayer and its
AudioStreamPlayback explicitly before closing the host.

`CardinalEmbeddedHost` owns the engine lifetime. It supports initialize/close,
patch load/save, serialized patch inspection, direct native protocol messages,
offline audio blocks and an experimental native AudioStream. One engine and one
active audio playback are supported. Host settings live in an explicit caller
directory, separate from the current Cardinal standalone settings. Patch/metadata
operations require the owner thread. Audio processing uses preallocated buffers
and runs concurrently with the UI using upstream Rack's engine synchronization.
Panel rendering and control snapshots no longer replace audio blocks with silence.
The stress check rasterizes panels and reads snapshots while a separate thread
processes DSP, rejecting any silent block. Native structural edits still use
upstream locks; a bounded command queue and immutable control snapshots remain
required before release to reduce contention and measure worst-case timing.

The optional `CARDINAL_3D_EMBEDDED=1` frontend selects a direct backend. The
builder stages it in `dist/embedded/rack` and keeps the normal launcher unchanged.
Six starter modules, their five connections and original SVG panel images are
verified in a clean-cache Godot project with native audio and no TCP connection.
The original non-headless module library is reused; upstream's headless-only
audio widget has no usable panel geometry. Static artwork comes from the actual
parsed native SVG, including Cardinal's colour transforms, rather than guessed
filenames or recreated labels. The graphics variant uses Cardinal's existing
hidden GL context and exact NanoVG module drawing, including custom displays and
module context menus, with direct RGBA images instead of compressed TCP frames.
Physical controls and LEDs remain separate live 3D overlays. Godot's WGL context
is restored after each owner-thread native call. Run the check command with
`--graphics` to require native artwork and menu images and exercise a real
Godot desktop GL window in addition to the headless tests.

Cold editor imports use a frame delay before shutdown to avoid the confirmed
[Godot extension documentation race](https://github.com/godotengine/godot/issues/111048).
Checks require success markers and reject native assertions/script errors;
timeouts terminate only the test's own process tree.

Full-library validation:

```powershell
scripts/build_local_windows.ps1 -FullRegistry
py -3 scripts/check_embedded.py --graphics --build dist/embedded-full --minimum-models 1400 --godot .tools/Godot/Godot_v4.5.1-stable_win64_console.exe --resources dist/embedded-full/Cardinal
py -3 scripts/audit_embedded_library.py --dll dist/embedded-full/Cardinal3DEngine.dll --resources dist/embedded-full/Cardinal --minimum-models 1400 --report reports/embedded-full-library.json
py -3 scripts/freeze_embedded_windows.py
py -3 scripts/run_embedded_windows.py --vr
```

The launch copy lives outside `dist`; compiling again does not overwrite DLLs in
a running app. Only use the freeze command after checks pass. Development can
launch a build directly using `--build`, but then that build must not be replaced
while it is running. Real launches use the normal audio driver; automated tests
use Dummy output. The embedded audio/view panel selects output devices, volume
and MIDI inputs. Recovery is saved on shutdown and every 120 seconds, with a backup.
Short MIDI messages use a preallocated queue; native note gates and panic are
tested. MIDI output, SysEx and physical MIDI hardware remain acceptance work.

Still required for a playable replacement: complete custom artwork coverage and
render scheduling, hardware VR input validation, immutable state/command
queue/state optimization, complete audio/MIDI and host settings UI, acceptance
of plugin-specific menu actions, and hardware latency comparisons. The existing VR launcher deliberately
continues using the tested two-process build until these acceptance checks pass.

Direct commands may be a single object or an array of up to eight objects.
Arrays execute in order, retain individual acknowledgments, and produce one
final scene step/snapshot. The frontend uses this path once per frame. Invalid
array members are rejected before execution; ordinary command errors are
reported per action. `scripts/benchmark_embedded_commands.py` measures this
owner-thread overhead with the six-module starter, without audio or XR.
