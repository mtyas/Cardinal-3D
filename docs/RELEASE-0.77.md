# Cardinal 3D 0.77 beta — first public release

Cardinal's modular synthesis engine runs inside a Windows application for Quest Link, with a full 1,412-model registry and multiple physical cases sharing one patch.

This version introduces pointer-driven rack positioning, wrist-only upright case rotation and trigger + grip wrist fine tuning at one-tenth sensitivity. Illustrated menus, a Quest Touch teaching guide, native MixMaster bus choices, original panel surfaces and an in-app About/licence library are included.

B always opens the main menu; grip + B opens the selected module's context menu. Menu windows have top-right close buttons. The tutorial uses the controller diagram created by mtyas. New rack warns before replacing the current patch with empty surroundings, one case and Cardinal Audio 2 only; saved patch files are untouched.

Downloads:
- `Cardinal-3D-0.77-Windows-x64.zip`: extract and run Launch Quest Link.bat. Python and Docker are not needed.
- `Cardinal-3D-0.77-source.tar.gz`: matching recursive source, bindings, dependency sources and build instructions.
- `SHA256SUMS.txt`: integrity checks for the above files.

Read the [illustrated manual](MANUAL.md). Windows x64, Quest 2, USB Quest Link and a compatible PC are the tested target. This is a PC VR application; it is not an Android headset app or a DAW plugin. Audio input, complete audio driver/channel/buffer controls, MIDI output/SysEx and universal custom-widget coverage remain future work. Windows binaries are unsigned.

Software: GPL-3.0-or-later, no warranty. Godot is MIT. Bundled artwork/fonts retain their individual terms, including noncommercial and custom permissions; see legal/NOTICE.txt and the pinned Cardinal notices. The binary and complete source must remain available together. This is an independent modified Cardinal host; no DISTRHO, VCV or Meta endorsement is implied.

This is a beta: further headset testing, custom-widget coverage and host options are ongoing. Preserve the individual artwork terms and permissions; the complete artwork collection is not GPL or unrestricted commercial material.
