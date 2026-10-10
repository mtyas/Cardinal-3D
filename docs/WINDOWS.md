# Windows and Quest PC VR

Development target: Windows x64 PC, RTX 3060 12 GB, 32 GB RAM and Intel CPU; Quest 2 through USB Link first, then Air Link. Actual headset performance and audio latency must be measured on that PC.

## Current Windows milestone

The UI transport supports Winsock and POSIX with the same authenticated loopback protocol, bounded queues and UI-thread commands. Windows drive and UNC paths are accepted for native patch save/load. Module DSP and audio processing remain upstream Cardinal code.

`Windows bridge checks` compiles and runs the transport regression on a real GitHub Windows runner. `Windows desktop build` is a manually triggered Linux cross-build following Cardinal's pinned PawPaw/MinGW approach. It builds the 190-module runtime and packages Godot 4.5.1 plus a launcher into a private seven-day Actions artifact. These workflows are build infrastructure, not a claim that the full application has passed Windows or VR testing.

In GitHub Actions, select **Windows desktop build → Run workflow**. Download `Cardinal-3D-Windows`, extract both archive layers, install Python 3 from its official distribution, select the Windows default sound output, and double-click **Launch Cardinal 3D.bat**. The native WASAPI engine uses that default output when it starts. Closing Godot leaves synthesis running; close Cardinal normally to save native state.

A successful manual build automatically triggers one frontend refresh against current `main`. Download that refresh's artifact to get the latest VR interface. It reuses the native executable only after verifying identical bridge sources, build instructions and dependency pins. A later UI-only update can also specify a successful run ID in the workflow's optional reuse field.

The bundle carries dependency artwork and license notices for private development. It is not cleared for public distribution. Personal patches, session tokens, downloaded tools, local build directories and imported Godot state are excluded from the repository.

## PC test on 10 October 2026

Build [38048874513](https://github.com/mtyas/Cardinal-3D/actions/runs/38048874513) starts the native runtime with its portable resources, including core fonts and component artwork. A six-module Fundamental patch with five cables was saved and loaded from a Windows path containing spaces. The user confirmed its tone through Quest 2 headphones with the Quest selected as the Windows default output. Godot connects to the native bridge and renders this rack through Meta OpenXR in the desktop mirror. The user confirmed the rack is visible inside the headset and controller input reaches it, but reported the aiming dot moving across controls during a held gesture. The frontend now locks the dot to the captured knob, avoids a final pointer jump on release, and adds wrist/distance tuning and thumbstick locomotion. These changes pass local synthetic checks; their physical retest, sustained performance and latency remain pending. The Meta runtime did not advertise optical hand tracking in the initial preflight.

Godot crashed while opening its application log folder from a restricted automation session. Relaunching with normal Windows application-folder access succeeded. No administrator elevation is required by the launchers themselves.

## Local compilation

The Windows native runtime can be cross-compiled locally in Linux through WSL or Docker using `scripts/build_windows.sh`. Keep the checkout at a Linux path without spaces, install the upstream bootstrap dependencies, and preserve the PawPaw toolchain and build objects between runs. The script currently defaults to four jobs; `CARDINAL_3D_BUILD_JOBS` can change that. This PC's local builder has not yet been provisioned. Frontend-only changes can reuse the existing native runtime instead of rebuilding Cardinal.

## Cloud execution

Codex Cloud can work on the private GitHub source and prepare/review changes. The repository and build scripts can also run in a Linux build environment; upstream cross-compilation produces Windows binaries. This local Mac chat has not automatically moved to a cloud task. Cloud builders cannot certify the connected Quest, physical hand tracking, audio-device configuration or motion-to-sound latency on the user's PC.

Official cloud setup: https://learn.chatgpt.com/docs/cloud . Choose the private `mtyas/Cardinal-3D` repository when configuring the environment. Dependency setup needs access to upstream repositories and source/tool download hosts.

## VR and hands prototype

**Launch Cardinal 3D VR.bat** starts Godot with OpenXR enabled. Connect Quest Link and select the Meta PC OpenXR runtime before launching. Enable hand tracking on the headset; Meta documents Developer Runtime Features for development over Link. See [Meta's Link development requirements](https://developers.meta.com/vr/documentation/native/android/mobile-passthrough-over-link/). Actual extension availability must be checked on the PC.

Both tracked hands display joint lines and pointing rays. A visible marker snaps to nearby controls. Point and pinch to press switches, adjust knobs by moving the hand vertically, drag sliders, and connect or move cables between sockets. Open the fingers to release. Pinching the module's top strip moves the module through Cardinal's history; pinching the exposed case moves the whole rack in space without changing patch coordinates. Controller trigger actions take over when optical tracking is absent. Hold a knob with the trigger, roll the wrist for coarse adjustment, and move closer or farther from that knob for finer adjustment (pulling away increases its value). The target dot remains on the captured knob until release. Sliders and optical hand pinches use vertical movement. Clicking the module header strip selects it with a cyan mark; holding and dragging that strip moves it. With a module selected, B/Y opens its complete native context menu, including duplicate, delete and module-specific actions. Clicking exposed rack space clears the selection. Both thumbsticks move sideways and closer/farther relative to headset yaw, without rotating the view. Both use a deadzone and eased velocity; locomotion pauses while a control or object is held. In VR the permanent toolbar is hidden. A/X toggles the module browser, and B/Y toggles a compact main menu placed in front of the current headset pose when no module is selected. The menu contains patch open/save, undo/redo, lighting, rack recentering and the last hovered control's native context menu. Its transparent texture and cropped collision panel remove the unused blank window. The browser retains filters and scrolling.

Pinch detection uses separate press/release distances. Tracking recovery requires opening the fingers before another press. Focus loss, bridge disconnect, patch reload and module deletion release active gestures. Inferred controller hands do not generate optical pinch presses. Cable meshes use rack-local coordinates so spatial rack movement keeps endpoints attached.

Automated synthetic joint and interaction checks pass on macOS; the Windows workflow also runs them. These verify routing and lifecycle behavior, not physical hand accuracy or headset rendering. The first virtual hands are joint outlines; detailed hand meshes and direct fingertip touching remain later work. There is no headset keyboard yet; use the PC keyboard for search and file names.

## Next acceptance steps

1. Launch the Windows desktop bundle, build a wired patch, verify native save/load and inspect the original Cardinal window.
2. Compare deterministic audio with the same pinned Windows baseline, sample rate and settings.
3. Launch VR, position the rack at a comfortable scale, and validate stereo rendering through Quest Link.
4. Exercise controller rays and tracked hands. Hand pointing/pinching must operate knobs, switches and wires; loss of tracking must release gestures. Grabbing the case changes scene placement only.
5. Verify which OpenXR hand extensions the active PC runtime exposes; retain controllers when tracking is unavailable. Test clarity, frame timing and sustained audio while interacting.
6. Explore Android standalone after the PC VR interaction is usable. Evaluate RackDroid platform code against the pinned Cardinal runtime and native patch compatibility.

The user confirmed wrist/distance tuning affects the sound, then reported that knob rotation was hard to see in VR. A live Windows bridge probe changed VCO frequency from 261.63 to 554.75 Hz and its normalized visual value from 0.5 to 0.62048. Rendering those actual snapshots moved the 3D knob from 0 to -0.6283 radians. The indicator is now wider, unshaded and drawn above the cap for visibility in headset lighting. XR menu/navigation and hardware tests pass; the indicator visibility and popup changes await physical retest.

The current frontend preserves existing panel textures across topology refreshes and bridge reconnects, applies the latest snapshot before uploading textures, and coalesces queued images by module. Its larger read budget helps clear delayed control and position updates. The browser marks its selected module, names the Add button and closes before insertion. Local Windows browser, XR, hardware/texture retention and streaming burst checks pass. An isolated Windows native test confirmed non-overlapping placement after adding a module and dragging it toward occupied space, and successfully opened a module header context menu. Headset menu usability, visual latency and sustained panel rendering still require physical retesting.
