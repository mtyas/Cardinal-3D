# Experimental embedded Windows engine

This is a development target separate from the user-confirmed Quest runtime.
It loads Cardinal DSP, the original 190-model prototype registry, native patch
manager, widget metadata and undo history into Godot's process. There is no
Cardinal executable or socket in this target. Original upstream DSP is unchanged.

Build locally with `scripts/build_local_windows.ps1 -Embedded`. It reuses the
dedicated WSL compiler cache and writes `dist/embedded`; it does not install over
the working VR bundle. The normal local build command is unchanged. The builder
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
operations require the owner thread. Audio processing uses preallocated buffers;
it never waits for the UI gate. A busy UI operation currently produces silence
for that block. Before release this must be replaced with a command queue and
immutable control snapshots so UI work cannot interrupt the audio stream.

The optional `CARDINAL_3D_EMBEDDED=1` frontend selects a direct backend. The
builder stages it in `dist/embedded/rack` and keeps the normal launcher unchanged.
Six starter modules, their five connections and original SVG panel images are
verified in a clean-cache Godot project with native audio and no TCP connection.
The original non-headless module library is reused; upstream's headless-only
audio widget has no usable panel geometry. Static artwork comes from the actual
parsed native SVG, including Cardinal's colour transforms, rather than guessed
filenames or recreated labels. Custom drawing is still incomplete.

Cold editor imports use a frame delay before shutdown to avoid the confirmed
[Godot extension documentation race](https://github.com/godotengine/godot/issues/111048).
Checks require success markers and reject native assertions/script errors;
timeouts terminate only the test's own process tree.

Still required for a playable replacement: offscreen custom artwork rendering,
live VR input integration (including pointer modifiers), immutable state/command
queue, complete audio/MIDI and host settings UI, all module menus, full Windows
registry, and hardware latency comparisons. The existing VR launcher deliberately
continues using the tested two-process build until these acceptance checks pass.
