# Validation for 0.77 beta

The current checks cover the embedded Windows host and Quest-facing interface. Historical Mac baseline reports have been removed from the active tree.

- `tests/source_audit.py`: exact pinned Cardinal source and permitted UI/build integration; DSP sources remain unchanged.
- `tests/embedded_host.py`: the 1,412-model registry, native DSP/audio, patch save/load, undo, MIDI input/panic, MixMaster faders/routing and concurrent UI/audio processing.
- `embedded/godot/test_rack.gd`: original module panels, embedded menus, wrist settings, clean-settings recovery and New rack warning/cancel/reset. The reset must leave one Audio 2 module, no cables, one locked case and empty surroundings, without changing a saved patch file.
- `tests/frontend_xr.gd`: controller/hand routing, captured controls, cable gestures, B/grip+B, selected modules and top-right close buttons.
- `tests/frontend_layout.gd`: case movement/rotation, performance locks, delete warning, layout sidecars, joystick option scrolling, tutorial bounds and environments.
- `tests/frontend_browser_controls.gd`: category selection and joystick browsing.

The public portable package is also exercised with fresh settings and a system-only dependency path. Automated checks cannot measure every headset's perceived latency, comfort or hardware compatibility. The beta remains subject to user testing and further custom-widget coverage.