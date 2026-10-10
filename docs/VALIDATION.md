# Validation on the development Mac

Cardinal pin `0a530b73273afc914ec71a78e9165cd28c53b599`, Rack 2.4.1, Godot 4.5.1, Apple M4, macOS 15.7, OpenGL compatibility renderer. Both prototype and full bundled-library standalone builds compile with local tools. Clang 17 needs a diagnostic compatibility flag for legacy template syntax in Surge's UI drawing code; no Surge source is edited.

| Check | Result |
|---|---|
| Six real milestone modules and native audio routing | Passed |
| Parameter interaction and grouped native undo/redo | Passed |
| Fine adjustment, reset and parameter limits | Passed |
| Wire creation, removal, undo and movement | Passed |
| Acknowledged floating cable and colored 3D plug meshes | Passed; visible frontend inspected |
| Momentary trigger release and Scope switch undo | Passed |
| Changing live Scope texture | Passed |
| Native parameter menus | Inspected in Godot's interactive original-UI overlay |
| Native patch save/load | Passed; same patch loaded by bridge-free Cardinal for audio render |
| Deletion during a gesture and undo | Passed |
| Patch reload during dragging and rejection of stale-generation commands | Passed |
| Disconnect/reconnect and held momentary release | Passed |
| Cancelled gesture preserves its value; stalled frontend releases on heartbeat timeout | Passed |
| Four-channel polyphonic cable | Passed in full build using Fundamental Merge → ADSR |
| Deterministic audio compared with original pinned UI baseline | Passed; four seconds, stereo, 48 kHz, 256-frame blocks, fixed RNG seed, byte-identical non-silent output |
| Source confinement | Passed; only two UI files and two Makefiles changed; recursive gitlinks pinned |
| Godot import / script validation | Passed |
| Trackpad pan, Shift-orbit, pinch zoom, click-drag orbit and release | Passed with synthetic events through Godot's viewport; no patch commands emitted |
| Lighting presets and brightness scaling | Passed; running angled rack with Cool stage lighting visually inspected |
| Dynamic case insertion, movement, deletion and unchanged-layout caching | Passed Godot interaction checks |
| Magnetic control binding, focus labels and title-only module dragging | Passed; Alt-click on a control cannot initiate movement |
| Compact transparent native menus, repeated reopening and full-scene opt-in | Passed native bridge and frontend coordinate-mapping checks; captured menu inspected |
| ADSR, VCA and Scope display geometry and native live textures | Passed runtime extraction and frontend texture-binding checks; running rack inspected |
| All 20 Audible Instruments modules and static panel previews | Passed factories, descriptors and native texture capture; previews leave playing patch empty |
| Searchable 3D browser, pagination, ray picking, rotation and insertion binding | Passed Godot checks; gallery selection and real Plaits insertion inspected; test insertion undone |
| Preview cleanup after insertion advances scene generation | Passed native regression check |
| Audible demo audio compared with bridge-free baseline | Passed; four seconds of non-silent stereo Plaits → Ripples → VCA output are byte-identical at 48 kHz / 256 frames |
| Framing, fragmented packets, obsolete snapshots and malformed frames | Passed transport test |

The full runtime scan instantiated 1,412 loaded models across 84 plugins without factory errors. The scan counted 48,712 components: 42,531 physical candidates and 6,181 surface components. Custom parameter widgets account for 2,939 controls across 123 models and stay interactive on their original surfaces. Full module surfaces remain available through overrides. See `library-summary.json`, the per-model `required-overrides.json` and the generated `build/full-library.json`.

Extraction uses actual constructor-established widget trees. Unattached library preview widgets are not stepped: some modules assume rack parents or install scene overlays in their step handlers. Active patch widgets remain attached and step normally. Descriptors establish initial conversion coverage; they do not certify every module's menus, dynamic geometry or behavior. Whole-library compatibility is still a later milestone.

The real Godot frontend sustained **111.5 mean fps**, **14.8 ms p95 frame time**, and **153 native knob gestures** during a 62-second representative six-module/five-wire run. Cardinal's existing audio CPU meter peaked at **3.97%**. The first two seconds were excluded from frame timing. `tests/frontend_benchmark.py` reproduces this check. The native backend does not expose an underrun count through the current UI bridge; underruns were **not measured** and must be instrumented externally before claiming that acceptance check complete.

The pasted Godot crash report corresponded to its file logger trying to rotate logs inside the restricted execution sandbox before project startup. File logging is disabled in `project.godot`; subsequent desktop runs and headless script imports succeeded.

Trackpad navigation and lighting checks can be repeated with `.tools/Godot.app/Contents/MacOS/Godot --headless --path godot --script ../tests/frontend_navigation.gd`. Gesture checks inject Godot input events; physical trackpad gestures have not been independently exercised by automation. The lighting and navigation update changes only frontend scripts and documentation; the previous audio comparison remains applicable.

The expanded default build contains 48 models across Cardinal, Fundamental and Audible Instruments. `tests/audible_bridge.py` validates all 48 factories and previews, insertion/undo for all 26 Fundamental modules, native parameter undo, and a five-module/five-cable demo saved as `build/audible-demo.vcv`. Run `tests/audio_compare.py --patch build/audible-demo.vcv --report build/audible-audio-comparison.json` after building the baseline to reproduce the audio comparison; its result is retained in `audible-audio-comparison.json`. Module DSP source is unchanged, including Audible Instruments and its embedded firmware libraries.

`tests/frontend_hardware.gd` checks case resizing, magnetic binding, title-only movement, native display texture reuse and crop coordinate mapping. `tests/frontend_browser.gd` checks gallery search, trackpad scrolling, last-row reachability, bounded preview windows, actual 3D ray picking, rotation and exact plugin/model insertion. The running seven-module/nine-cable rack displayed about 90 fps and the open gallery about 83 fps during visual inspection. These are observed status readings, not a new sustained benchmark; the earlier sustained benchmark predates the added hardware and browser.

Remaining verification: complete per-module compatibility, dynamic layout changes, all custom keyboard entry edge cases, external native file dialogs, explicit audio-underrun measurement, and Windows. VR/AR, OpenXR, DAW hosting and standalone headsets are deferred by the plan. Artwork distribution clearance is recorded separately in `ARTWORK.md`.

The header now uses the browser as its only insertion UI and groups patch files/examples in a Patch menu. Magnetic cursor movement uses Viewport coordinates with finite/bounds/focus guards, and latches before warping to avoid recursive motion. The hardware regression verifies the actual projected target and one snap per control entry; physical macOS pointer behavior remains subject to desktop verification.

After the 48-module registry update, the four-second Audible demo still renders byte-identical stereo output against the bridge-free baseline (`expanded-audio-comparison.json`). Desktop inspection confirmed the compact header and scrolling through the new Fundamental entries. The user’s saved eight-module/twelve-cable patch was restored; audio processing source remains unchanged.

The next prototype expansion contains 79 modules (31 Befaco, 26 Fundamental, 20 Audible and two Cardinal audio modules). All 79 factories and previews pass; all 31 Befaco modules insert and undo through the native runtime. Native Plaits descriptors expose seven visible knobs and two hidden alternate LPG knobs. Frontend checks verify mode-dependent geometry visibility, name/manufacturer/type sorting, secondary-tag filtering and a single-row header under 65 viewport pixels. Per-module interaction certification remains separate from factory/preview coverage.

The updated app restored the running nine-module/thirteen-cable patch. Desktop inspection confirmed the single-row header, settings dropdown and alphabetically ordered 79-module gallery. The four-second Audible patch remains byte-identical to the bridge-free baseline after the Befaco expansion; see `befaco-audio-comparison.json`.

The default registry now contains 190 modules: two Cardinal audio modules, 26 Fundamental, 20 Audible Instruments, 31 Befaco and 111 Bogaudio. Native checks pass factory/descriptor extraction and insertion/undo for all 111 Bogaudio models. The browser supports exact manufacturer filtering combined with any native type tag, search and sorting. Frontend regression checks cover combined filters, empty results, clearing filters and preserving selections across catalogue refreshes. The four-second Audible demo remains byte-identical to the bridge-free baseline at 48 kHz / 256-frame blocks; see `bogaudio-audio-comparison.json`. The source audit still confines upstream changes to UI and build integration.

The combined native sweep passes all 190 artwork previews without patch/audio-engine insertion, preview cleanup after generation changes, wired demo save/load and parameter undo. The test client now throttles heartbeat messages to avoid replying continuously to heartbeat acknowledgements. Desktop inspection confirmed the restored nine-module/thirteen-cable rack and the combined Bogaudio + Envelope generator filter showing exactly eight modules.
