# Developing Cardinal 3D 0.77 beta

The supported release is a Windows x64 application for Quest Link. Godot 4.5.1 runs the VR interface and audio playback; Cardinal's pinned DSP and complete module registry run in-process through the embedded extension. See [local build instructions](BUILDING-0.77.md).

## Source structure

- `godot/scripts/`: VR interaction, illustrated menus, module browser, physical cases and environments.
- `embedded/`: Windows engine DLL, Godot extension, audio playback and embedded checks.
- `bridge/Cardinal3DBridge.hpp`: native UI commands, descriptors, module surfaces, history and patch operations; shared by the embedded host.
- `scripts/`: source pinning, local WSL builds, validation and release packaging.
- `legal/` and `godot/legal/`: upstream notices and the in-app licence library.

The engine stays on its native owner thread for UI operations, with preallocated audio buffers for playback. Each physical case belongs to the same patch. Case transforms and module membership live in `.vcv.3d.json` files beside saved patches; recovery uses a separate user settings folder.

Normal wrist sensitivity is adjustable; trigger + grip uses one-tenth sensitivity. B opens the main menu and grip + B opens the selected module's native menu. New rack is confirmed before replacing the patch with one Audio 2 module, one locked case and empty surroundings.

## Release checks

Use the pinned source audit, `scripts/check_embedded.py --graphics` and the frontend checks under `tests/`. Copy checked builds into new runtime directories rather than replacing DLLs in a running application. Keep personal patches, recovery state, downloaded tools and credentials outside public release archives.

The obsolete Mac launcher, build scripts, baseline test reports and Mac prototype instructions have been removed from the active source tree. Git history remains available for provenance.