// SPDX-License-Identifier: GPL-3.0-or-later
// Reuse upstream DPF's plugin lifecycle and Cardinal DSP without a UI or TCP.
#include "Host.h"
#include "src/DistrhoPlugin.cpp"
// Use the portable Windows resource-directory convention. No standalone entry
// point or audio-device backend is linked into this DLL.
#define DISTRHO_PLUGIN_TARGET_JACK
#define DISTRHO_IS_STANDALONE 0
#include "src/DistrhoUtils.cpp"
#undef DISTRHO_PLUGIN_TARGET_JACK
// Godot owns device routing; do not expose JACK-only controls in native menus.
namespace CardinalDISTRHO {
bool isUsingNativeAudio() noexcept { return false; }
bool supportsAudioInput() { return false; }
bool supportsBufferSizeChanges() { return false; }
bool supportsMIDI() { return false; }
bool isAudioInputEnabled() { return false; }
bool isMIDIEnabled() { return false; }
unsigned int getBufferSize() { return 0; }
bool requestAudioInput() { return false; }
bool requestBufferSizeChange(unsigned int) { return false; }
bool requestMIDI() { return false; }
}
#include "CardinalPluginContext.hpp"
#include <patch.hpp>
#include <asset.hpp>
#include <settings.hpp>
#include <system.hpp>
#include <jansson.h>
#include <cmath>
#include <memory>
#include <string>
#include <thread>
#include <vector>
#include <atomic>
#include "cardinal3d/Cardinal3DBridge.hpp"
#define NANOSVGRAST_IMPLEMENTATION
#include <nanosvgrast.h>

// RemoteWindow has no physical cursor. Pointer modifiers will be carried by the
// embedded input adapter when live VR input is introduced.
#ifdef HEADLESS
namespace rack { namespace window { void WindowSetMods(Window*, int) {} } }
#else
#include <windows.h>
namespace rack { namespace window { void WindowRunEmbedded(Window*, void (*)(void*), void*); } }
#endif

namespace {
using namespace CardinalDISTRHO;
struct Host {
    std::string bundle, error, patch;
    std::thread::id owner = std::this_thread::get_id();
    uint32_t block;
    std::vector<float> silence;
    std::vector<uint8_t> panel;
    std::vector<uint8_t> surface;
    std::string surface_header;
    uint32_t surface_width = 0, surface_height = 0;
    std::unique_ptr<PluginExporter> plugin;
    std::unique_ptr<cardinal3d::Bridge> bridge;
    CardinalPluginContext* context = nullptr;
    std::atomic_flag busy = ATOMIC_FLAG_INIT;
    std::atomic_flag audio_busy = ATOMIC_FLAG_INIT;
    Host(const char* path, const char* user, double rate, uint32_t frames)
        : bundle(path), block(frames), silence(frames, 0.f) {
        rack::asset::userDir = user;
        rack::system::createDirectories(user);
        rack::settings::settingsPath = rack::system::join(user, "embedded-settings.json");
        d_nextBufferSize = frames;
        d_nextSampleRate = rate;
        d_nextBundlePath = bundle.c_str();
        plugin.reset(new PluginExporter(nullptr, nullptr, nullptr, nullptr));
        context = static_cast<CardinalBasePlugin*>(plugin->getInstancePointer())->context;
        bridge.reset(new cardinal3d::Bridge(true));
#ifndef HEADLESS
        bridge->setLocalSurfaceCallback([this](json_t* header, const std::vector<uint8_t>& pixels) {
            surface_header = cardinal3d::encode(header); surface = pixels;
            surface_width = json_integer_value(json_object_get(header, "width"));
            surface_height = json_integer_value(json_object_get(header, "height"));
        });
#endif
        plugin->activate();
    }
    ~Host() {
#ifndef HEADLESS
        rack::contextSet(context);
        rack::window::WindowRunEmbedded(context->window, [](void* ptr) { static_cast<Host*>(ptr)->bridge->destroyGraphics(); }, this);
        rack::contextSet(nullptr);
#endif
        bridge.reset(); if (plugin) plugin->deactivate();
    }
};
Host* live = nullptr;
std::string creation_error;
// DGL changes the thread's current GL context. Preserve Godot's context across
// every owner-thread call, including engine construction and destruction.
struct PreserveWglContext {
#ifndef HEADLESS
    HDC dc = wglGetCurrentDC(); HGLRC context = wglGetCurrentContext();
    ~PreserveWglContext() { wglMakeCurrent(dc, context); }
#endif
};
struct Context {
    Context(Host* h) { rack::contextSet(h->context); }
    ~Context() { rack::contextSet(nullptr); }
};
Host* checked(void* ptr) { return ptr && ptr == live ? live : nullptr; }
bool owner(Host* h) {
    if (h->owner == std::this_thread::get_id()) return true;
    h->error = "Patch operations require the host owner thread";
    return false;
}
template<class F> int operation(void* ptr, F fn) {
    Host* h = checked(ptr);
    if (!h || !owner(h)) return 0;
    if (h->busy.test_and_set(std::memory_order_acquire)) { h->error = "Audio callback is busy; retry on the next frame"; return 0; }
    struct Unlock { Host* h; ~Unlock() { h->busy.clear(std::memory_order_release); } } unlock{h};
    try { PreserveWglContext graphics; Context scope(h); fn(h); h->error.clear(); return 1; }
    catch (const std::exception& e) { h->error = e.what(); }
    catch (...) { h->error = "Unknown Cardinal host error"; }
    return 0;
}
}
void* c3d_create(const char* bundle, const char* user, double rate, uint32_t block) {
    if (live) { creation_error = "Only one embedded host is supported"; return nullptr; }
    if (!bundle || !*bundle || !user || !*user || !std::isfinite(rate) || rate < 8000 || rate > 384000 || !block || block > 16384) {
        creation_error = "Invalid resource path, sample rate or buffer size"; return nullptr;
    }
    try { PreserveWglContext graphics; live = new Host(bundle, user, rate, block); creation_error.clear(); return live; }
    catch (const std::exception& e) { creation_error = e.what(); }
    catch (...) { creation_error = "Unable to initialize Cardinal"; }
    return nullptr;
}
int c3d_destroy(void* ptr) {
    Host* h = checked(ptr);
    if (!h || !owner(h) || h->busy.test_and_set(std::memory_order_acquire)) return 0;
    PreserveWglContext graphics; delete h; live = nullptr; return 1;
}
const char* c3d_error(void* ptr) { Host* h = checked(ptr); return h ? h->error.c_str() : creation_error.c_str(); }
int c3d_load(void* ptr, const char* path) {
    if (!path || !*path) return 0;
    return operation(ptr, [path](Host* h) {
        if (!rack::system::isFile(path)) throw std::runtime_error("Patch file does not exist");
        h->context->patch->load(path);
    });
}
int c3d_save(void* ptr, const char* path) {
    if (!path || !*path) return 0;
    return operation(ptr, [path](Host* h) { h->context->patch->save(path); });
}
const char* c3d_patch_json(void* ptr) {
    if (!operation(ptr, [](Host* h) {
        json_t* root = h->context->patch->toJson();
        char* text = json_dumps(root, JSON_COMPACT | JSON_SORT_KEYS);
        json_decref(root);
        if (!text) throw std::runtime_error("Unable to serialize patch");
        h->patch = text;
        free(text);
    })) return nullptr;
    return live->patch.c_str();
}
const char* c3d_messages_json(void* ptr, const char* command) {
    if (!operation(ptr, [command](Host* h) {
        h->patch = h->bridge->invokeLocal(command ? command : "");
    })) return nullptr;
    return live->patch.c_str();
}
const char* c3d_render_surface(void* ptr) {
    if (!operation(ptr, [](Host* h) {
        h->surface_header.clear();
#ifndef HEADLESS
        rack::window::WindowRunEmbedded(h->context->window, [](void* ptr) { static_cast<Host*>(ptr)->bridge->render(); }, h);
#endif
    })) return nullptr;
    return live->surface_header.c_str();
}
const uint8_t* c3d_surface_rgba(void* ptr, uint32_t* width, uint32_t* height) {
    Host* h = checked(ptr);
    if (!h || !owner(h) || !width || !height || h->surface_header.empty()) return nullptr;
    *width = h->surface_width; *height = h->surface_height;
    return h->surface.data();
}
const uint8_t* c3d_panel_rgba(void* ptr, const char* id, uint32_t* width, uint32_t* height) {
    if (!id || !width || !height) return nullptr;
    *width = *height = 0;
    if (!operation(ptr, [id, width, height](Host* h) {
        rack::app::SvgPanel* panel = nullptr;
        if (auto* module = h->bridge->findLocalModule(id)) {
            for (auto* child : module->children) {
                panel = dynamic_cast<rack::app::SvgPanel*>(child);
                if (panel && panel->svg && panel->svg->handle) break;
            }
        }
        if (!panel || !panel->svg || !panel->svg->handle) throw std::runtime_error("Module has no static SVG panel");
        NSVGimage* image = panel->svg->handle;
        if (image->width <= 0 || image->height <= 0) throw std::runtime_error("Invalid panel dimensions");
        const float scale = std::min(2.f, 4096.f / std::max(image->width, image->height));
        const uint32_t w = uint32_t(std::ceil(image->width * scale));
        const uint32_t y = uint32_t(std::ceil(image->height * scale));
        if (!w || !y || uint64_t(w) * y > 4 * 1024 * 1024) throw std::runtime_error("Panel exceeds image budget");
        h->panel.assign(size_t(w) * y * 4, 0);
        std::unique_ptr<NSVGrasterizer, decltype(&nsvgDeleteRasterizer)> raster(nsvgCreateRasterizer(), nsvgDeleteRasterizer);
        if (!raster) throw std::runtime_error("Cannot create panel rasterizer");
        nsvgRasterize(raster.get(), image, 0, 0, scale, h->panel.data(), w, y, w * 4);
        *width = w; *height = y;
    })) return nullptr;
    return live->panel.data();
}
int c3d_process(void* ptr, const float* in_l, const float* in_r, float* out_l, float* out_r, uint32_t frames) {
    Host* h = checked(ptr);
    if (!h || !out_l || !out_r || !frames || frames > h->block) return 0;
    // Upstream Cardinal/Rack deliberately supports an audio thread alongside
    // its UI thread. Engine::stepBlock and structural edits own the native
    // engine locks. Artwork, JSON and widget stepping must not silence audio.
    // Only prevent unsupported simultaneous DSP callbacks for this instance.
    if (h->audio_busy.test_and_set(std::memory_order_acquire)) return 0;
    const float* inputs[] = {in_l ? in_l : h->silence.data(), in_r ? in_r : h->silence.data()};
    float* outputs[] = {out_l, out_r};
    try { h->plugin->run(inputs, outputs, frames, nullptr, 0); }
    catch (...) {
        std::fill(out_l, out_l + frames, 0.f); std::fill(out_r, out_r + frames, 0.f);
        h->audio_busy.clear(std::memory_order_release); return 0;
    }
    h->audio_busy.clear(std::memory_order_release);
    return 1;
}
