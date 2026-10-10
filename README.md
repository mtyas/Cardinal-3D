# Cardinal 3D

Playable macOS desktop prototype: Godot renders the rack; the pinned Cardinal standalone owns the audio, controls, connections, undo history and native `.vcv` files. No audio is transported to Godot.

## Run on this Mac

The tools and prototype are already built in this workspace:

Double-click **Launch Cardinal 3D.command**, or run:

```sh
python3 scripts/run.py
```

Choose **Patch → Fundamental starter rack** for Fundamental VCO, VCF, ADSR, VCA-1, Scope and Cardinal Audio 2. The starter routes VCO → VCF → VCA → stereo audio output and Scope; ADSR is available for patching. Audio starts at a modest VCA level. The original Cardinal window stays available. Closing Godot leaves Cardinal and its audio running; close Cardinal separately when finished.

Drag knobs and sockets. Drag a connected socket to move its top wire. Cmd-drag an output adds another wire; Shift-click a socket removes its top wire. Wires have curved 3D meshes, colored plugs and a floating preview while patching. Cardinal performs connection validation and polyphonic signal processing.

Cmd provides fine parameter adjustment. Double-click resets. Right-click opens a compact native context menu at the pointer; Escape or clicking outside closes it. **Drag the top title strip to move a module**; dragging controls, including with Alt held, cannot move a module. Delete removes the module under the pointer. Middle-drag orbits, Shift-middle pans, wheel zooms. The browser inserts modules; the Patch menu opens/saves native patches, and toolbar buttons invoke native undo/redo. **Patch → Show original Cardinal UI** explicitly exposes the complete live Cardinal interface inside Godot.

For a Mac trackpad, use **two fingers to pan**, **Shift + two fingers to orbit**, and **pinch to zoom**. Alternatively hold **Space while click-dragging to orbit**, or **Shift + Space to pan**. The **View** menu switches between Play controls, Orbit view and Pan view; the latter two let an ordinary click-drag navigate without a keyboard modifier. **Front** restores the front view. The compact toolbar’s **Frame** button fits the rack. Open **View & lighting** for navigation modes, Front, lighting presets and exposure.

Choose **Studio**, **Warm desk**, **Cool stage** or **Night** in **View & lighting** and adjust the Exposure slider. Faceplates, meshes and cables respond to the scene lighting. These controls affect only the 3D presentation.

The Eurorack case fits the current module layout, with walnut cheeks, aluminum mounting rails and a recessed interior. It grows and shrinks when modules are inserted, moved or removed. Hardware includes fluted knobs, socket nuts and bores, cross-head screws, smooth cable tubes and detailed plug boots. ADSR, Scope and VCA meter graphics remain native live textures behind recessed glass and bezels; Braids gets the same display treatment. Native single-color lights retain their actual colors, while composite controls retain their original surfaces.

**Magnet** snaps the pointer onto nearby controls and shows a cyan focus ring, control name and current value. Snapping happens once on entering a control's proximity, so you can move away freely. Disable the toolbar toggle to use ordinary picking. Camera navigation, native menus and browser previews do not use this magnet.

**Browse modules** opens the searchable, scrollable 3D gallery. Use two fingers, the mouse wheel or the scrollbar to explore; up to sixteen native previews are kept alive at a time. Sort by **Name**, **Manufacturer** or **Module type**. Use **All manufacturers** to show one manufacturer and **All types** to show one module category. The filters combine with search and each other; choose All to clear either restriction. Click to select, drag to rotate, then double-click or choose **Add selected module**. Previews use actual runtime widget descriptions and native panel captures; they are never registered with the audio engine. The default build includes **190 modules**: 26 Fundamental modules, 20 Audible Instruments modules, 31 Befaco modules, 111 Bogaudio modules and Cardinal’s two audio modules. New choices include LFOs, SEQ-3, delay, mixers, quantizer, noise/random, switches and polyphonic split/merge utilities. Audible Instruments includes Braids, Plaits, Rings, Clouds, Elements, Marbles and Stages. Befaco adds Rampage, Kickall, Even VCO, Spring Reverb, Muxlicer, Noise Plethora and other instruments/utilities. Bogaudio adds oscillators/FM operators, envelopes, sequencers, arpeggiators, mixers/matrices, filters/EQ, analyzers and polyphonic utilities. Search by module, manufacturer or type. **Patch → Audible Instruments rack** adds a wired Plaits → Ripples → VCA patch feeding Scope and stereo output at a modest level.

## Reproduce the build

Requires macOS, Xcode Command Line Tools, Python 3, Git, curl and network access. Downloaded build tools stay under `.tools`; no package manager is required.

```sh
python3 scripts/bootstrap.py
python3 scripts/build.py
python3 tests/live_bridge.py
python3 scripts/build.py --baseline
python3 tests/audio_compare.py
python3 tests/source_audit.py
```

Godot is pinned to 4.5.1; Cardinal and all recursive submodules are pinned by `upstream.lock.json`. Bootstrap refuses to overwrite a different dirty checkout. Upstream Makefiles require paths without spaces, so compilation uses a temporary checkout whose path is recorded in `build/cardinal-path.txt`. Rebuild if that temporary directory is cleaned. The prototype registry contains 190 models, including Audio 8.

The complete bundled library is an optional larger build:

```sh
python3 scripts/build.py --full
python3 scripts/run.py --full
```

For coverage, run Cardinal alone with `CARDINAL_3D_PORT=39413` and a token in `CARDINAL_3D_TOKEN`, then use the same variables with `python3 scripts/inspect_library.py`. The bridge accepts one frontend at a time. Scans instantiate real widget trees incrementally, without inserting their DSP modules into the playing patch. Reports identify component types, physical conversion, custom controls needing overrides and complete-surface fallback coverage.

## Implementation

`bridge/` is a UI-only overlay installed by `scripts/install_bridge.py`. Godot uses procedural meshes, so Blender is optional. See [protocol](docs/PROTOCOL.md), [validation](docs/VALIDATION.md) and [artwork attribution](docs/ARTWORK.md).

This is the desktop prototype milestone. Windows build preparation is underway; see [Windows and cloud builds](docs/WINDOWS.md). OpenXR controller/hand interaction, AR, DAW integration and standalone headsets require separate validation. Dynamic CPU-transferred surfaces are throttled; the 3D scene renders independently. Original artwork remains local to the pinned source tree. Camera and scene scale never change native module layout or patch data.
