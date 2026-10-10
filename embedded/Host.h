// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <stdint.h>
#ifdef _WIN32
#ifdef C3D_HOST_IMPORT
#define C3D_API __declspec(dllimport)
#else
#define C3D_API __declspec(dllexport)
#endif
#else
#define C3D_API
#endif
#ifdef __cplusplus
extern "C" {
#endif
// Experimental engine-only interface. One instance per process. Create, load,
// save and destroy on the owner thread, with audio processing stopped.
// Audio uses non-interleaved stereo buffers, at most buffer_size frames.
C3D_API void* c3d_create(const char* bundle_path, const char* user_path, double sample_rate, uint32_t buffer_size);
C3D_API int c3d_destroy(void* host);
C3D_API const char* c3d_error(void* host);
C3D_API int c3d_load(void* host, const char* patch_path);
C3D_API int c3d_save(void* host, const char* patch_path);
// JSON pointer belongs to host, valid until next call or destroy; UI thread only.
C3D_API const char* c3d_patch_json(void* host);
C3D_API const char* c3d_messages_json(void* host, const char* command_json);
// Original panel SVG rendered on the owner thread. Returned pixels belong to
// host and are valid until the next panel request or destroy. RGBA8, top-down.
C3D_API const uint8_t* c3d_panel_rgba(void* host, const char* module_id, uint32_t* width, uint32_t* height);
C3D_API int c3d_process(void* host, const float* left_in, const float* right_in,
                        float* left_out, float* right_out, uint32_t frames);
#ifdef __cplusplus
}
#endif
