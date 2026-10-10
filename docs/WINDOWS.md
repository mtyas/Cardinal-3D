# Windows and Quest PC VR

Development target: Windows x64 PC, RTX 3060 12 GB, 32 GB RAM and Intel CPU; Quest 2 through USB Link first, then Air Link. Actual headset performance and audio latency must be measured on that PC.

## Current Windows milestone

The UI transport supports Winsock and POSIX with the same authenticated loopback protocol, bounded queues and UI-thread commands. Windows drive and UNC paths are accepted for native patch save/load. Module DSP and audio processing remain upstream Cardinal code.

`Windows bridge checks` compiles and runs the transport regression on a real GitHub Windows runner. `Windows desktop build` is a manually triggered Linux cross-build following Cardinal's pinned PawPaw/MinGW approach. It builds the 190-module runtime and packages Godot 4.5.1 plus a launcher into a private seven-day Actions artifact. These workflows are build infrastructure, not a claim that the full application has passed Windows or VR testing.

In GitHub Actions, select **Windows desktop build → Run workflow**. Download `Cardinal-3D-Windows`, extract both archive layers, install Python 3 from its official distribution, and double-click **Launch Cardinal 3D.bat**. The original Cardinal window is available for choosing the native audio device. Closing Godot leaves synthesis running; close Cardinal normally to save native state.

The bundle carries dependency artwork and license notices for private development. It is not cleared for public distribution. Personal patches, session tokens, downloaded tools, local build directories and imported Godot state are excluded from the repository.

## Cloud execution

Codex Cloud can work on the private GitHub source and prepare/review changes. The repository and build scripts can also run in a Linux build environment; upstream cross-compilation produces Windows binaries. This local Mac chat has not automatically moved to a cloud task. Cloud builders cannot certify the connected Quest, physical hand tracking, audio-device configuration or motion-to-sound latency on the user's PC.

Official cloud setup: https://learn.chatgpt.com/docs/cloud . Choose the private `mtyas/Cardinal-3D` repository when configuring the environment. Dependency setup needs access to upstream repositories and source/tool download hosts.

## Next acceptance steps

1. Launch the Windows desktop bundle, build a wired patch, verify native save/load and inspect the original Cardinal window.
2. Compare deterministic audio with the same pinned Windows baseline, sample rate and settings.
3. Enable OpenXR, position the rack at a comfortable scale, and validate stereo rendering through Quest Link.
4. Add controller rays and tracked hands. Hand pointing/pinching must operate knobs, switches and wires; loss of tracking must release gestures. Grabbing the case changes scene placement only.
5. Verify which OpenXR hand extensions the active PC runtime exposes; retain controllers when tracking is unavailable. Test clarity, frame timing and sustained audio while interacting.
6. Explore Android standalone after the PC VR interaction is usable. Evaluate RackDroid platform code against the pinned Cardinal runtime and native patch compatibility.
