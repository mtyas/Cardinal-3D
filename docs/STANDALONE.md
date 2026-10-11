# Standalone Windows host

Cardinal 3D 0.77 beta runs Cardinal's complete 1,412-model registry inside Godot on Windows, with Quest Link/OpenXR. There is no separate Cardinal process. Read the [manual](MANUAL.md), [developer guide](DEVELOPMENT.md) and [local build instructions](BUILDING-0.77.md).

Cases share one patch and cables can cross between them. In Layout mode, a held case edge follows the pointing ray, stick depth adjustment and free controller translation; wrist twist rotates the case upright around the vertical axis. Performance mode locks case editing.

The app provides native panel surfaces and context menus, adjustable wrist controls, grip fine control, browser/option scrolling, output-device and MIDI-input selection, patch save/load, undo/redo and recovery. New rack confirms before replacing the current workspace with one Audio 2 module and one case in empty surroundings. Saved patch files remain intact.

The beta is still developing: audio input, complete driver/channel/buffer controls, MIDI output/SysEx and universal custom-widget support remain incomplete. Perceived latency and comfort need physical headset testing. See [validation](VALIDATION.md) for the automated checks and their limits.