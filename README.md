# Cardinal 3D · 0.77

A modular synthesizer you can build around yourself in VR. Cardinal 3D runs Cardinal's synthesis engine inside one Windows application, with 1,412 module models, original panels and several physical racks sharing one patch.

![Cardinal 3D starter rack](docs/images/rack.png)

**[Download releases](https://github.com/mtyas/Cardinal-3D/releases) · [Illustrated manual](docs/MANUAL.md) · [Support mtyas](https://ko-fi.com/mtyas)**

## Start playing

1. Extract the entire Windows x64 release ZIP.
2. Connect Quest 2 by USB, open Meta Horizon Link on the PC, and enter Quest Link in the headset.
3. Run **Launch Quest Link.bat**. Start with a low volume; the starter rack produces a tone.
4. Follow the illustrated controller tutorial, or skip it and reopen it from B.

The portable download includes the runtime. Python, Docker and compiling are not required. **Launch desktop.bat** offers a monitor-only test. Windows x64, a Quest Link-compatible PC and Meta's OpenXR runtime are required. This is a Windows PC VR app, not an Android headset app or DAW plugin. The binaries are unsigned.

![Quest Touch tutorial](docs/images/tutorial.png)

## Your hands on the instrument

Trigger + wrist twist adjusts knobs and faders. Hold the grip as well for ten times finer wrist control; the B menu sets your normal sensitivity. A opens the browser. B opens the main menu, or a selected module's own context menu. Grip + B always opens the main menu.

The sticks pan and zoom; grip + stick moves vertically and turns your viewpoint. In menus and the browser, the stick scrolls. Move modules from their title strips using an insertion ghost. Connect, repatch and unplug cables through their sockets, with native undo.

![Illustrated main menu](docs/images/main-menu.png)

## Arrange your space

Enable Layout mode to add or delete physical cases in one patch. Hold a case edge and aim your ray to position it, use the stick to change distance, and twist your wrist to rotate it upright. Cases can stand beside, above or around you. Switch Layout mode off to lock them for a performance. Save the native .vcv patch together with its .vcv.3d.json arrangement.

![Rack management](docs/images/rack-menu.png)

Choose a studio, forest, mountain, stage, warehouse, desert or flowery field, with time-of-day lighting and picture-quality choices. These are lightweight stylized environments. Output audio, MIDI input, note panic and recovery have their own settings.

![Forest environment](docs/images/forest.png)

## Version 0.77

This is the first public release candidate. The engine, artwork, audio, menus and recovery are tested locally; the latest rack/wrist changes still need physical Quest acceptance. Audio input, complete driver/channel/sample-rate/buffer controls, MIDI output/SysEx and universal custom-widget coverage remain future work. Other headsets and Air Link are not validated.

[Release notes](docs/RELEASE-0.77.md) · [Local build instructions](docs/BUILDING-0.77.md) · [Developer history](docs/DEVELOPMENT.md)

## Free software and credits

Project code is **GPL-3.0-or-later**, with no warranty. Built on [DISTRHO Cardinal](https://github.com/DISTRHO/Cardinal), VCV Rack, the work of all included module authors, and [Godot](https://godotengine.org) (MIT). This is an independent modified host; no DISTRHO, VCV or Meta endorsement is implied.

**Artwork and fonts keep separate licences**, including noncommercial and custom terms. Read [credits and terms](legal/NOTICE.txt), [Cardinal's licence table](legal/LICENSES.md), [artwork permissions](legal/LICENSE-PERMISSIONS.md), [Godot notices](legal/Godot-COPYRIGHT.txt) and the individual notices in `legal/upstream`. These documents are included in the download and accessible in the app. Documentation screenshots retain their artwork terms. Supplied reference screenshots are not redistributed; the Quest teaching render is project-original.

Each binary release is paired with a matching **complete source archive**, including recursive Cardinal modules, bindings and dependency sources. GitHub's automatic source ZIP alone is incomplete. Keep the source download and notices available with the binaries.

Created by [mtyas](https://github.com/mtyas). [Voluntary Ko-fi support](https://ko-fi.com/mtyas) helps development and does not grant extra rights to third-party artwork.
