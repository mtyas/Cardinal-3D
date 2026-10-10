// SPDX-License-Identifier: GPL-3.0-or-later
#define C3D_HOST_IMPORT
#include "Host.h"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/classes/audio_stream.hpp>
#include <godot_cpp/classes/audio_stream_playback.hpp>
#include <godot_cpp/classes/audio_frame.hpp>
#include <godot_cpp/classes/image.hpp>
#include <atomic>
#include <vector>

using namespace godot;
class CardinalEmbeddedHost : public RefCounted {
    GDCLASS(CardinalEmbeddedHost, RefCounted)
    void* host = nullptr;
    uint32_t block = 0;
    double sample_rate = 48000;
    std::vector<float> left, right;
    std::atomic<void*> audio_owner{nullptr};
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("initialize", "resources", "user_directory", "sample_rate", "buffer_size"), &CardinalEmbeddedHost::initialize);
        ClassDB::bind_method(D_METHOD("close"), &CardinalEmbeddedHost::close);
        ClassDB::bind_method(D_METHOD("load_patch", "path"), &CardinalEmbeddedHost::load_patch);
        ClassDB::bind_method(D_METHOD("save_patch", "path"), &CardinalEmbeddedHost::save_patch);
        ClassDB::bind_method(D_METHOD("patch_json"), &CardinalEmbeddedHost::patch_json);
        ClassDB::bind_method(D_METHOD("messages_json", "command"), &CardinalEmbeddedHost::messages_json);
        ClassDB::bind_method(D_METHOD("last_error"), &CardinalEmbeddedHost::last_error);
        ClassDB::bind_method(D_METHOD("render_block", "frames"), &CardinalEmbeddedHost::render_block);
        ClassDB::bind_method(D_METHOD("create_audio_stream"), &CardinalEmbeddedHost::create_audio_stream);
        ClassDB::bind_method(D_METHOD("panel_image", "module_id"), &CardinalEmbeddedHost::panel_image);
        ClassDB::bind_method(D_METHOD("render_surface"), &CardinalEmbeddedHost::render_surface);
        ClassDB::bind_method(D_METHOD("surface_image"), &CardinalEmbeddedHost::surface_image);
    }
public:
    ~CardinalEmbeddedHost() { close(); }
    bool initialize(const String& resources, const String& user, double rate, int64_t frames) {
        if (host || frames < 1 || frames > 16384) return false;
        host = c3d_create(resources.utf8().get_data(), user.utf8().get_data(), rate, uint32_t(frames));
        if (!host) return false;
        block = uint32_t(frames);
        sample_rate = rate;
        left.resize(block); right.resize(block);
        return true;
    }
    bool close() {
        if (audio_owner.load(std::memory_order_acquire)) return false;
        if (host && !c3d_destroy(host)) return false;
        host = nullptr; return true;
    }
    bool load_patch(const String& path) { return host && c3d_load(host, path.utf8().get_data()); }
    bool save_patch(const String& path) { return host && c3d_save(host, path.utf8().get_data()); }
    String last_error() const { return String::utf8(c3d_error(host)); }
    String patch_json() const {
        const char* text = host ? c3d_patch_json(host) : nullptr;
        return text ? String::utf8(text) : String();
    }
    String messages_json(const String& command) {
        const char* text = host ? c3d_messages_json(host, command.utf8().get_data()) : nullptr;
        return text ? String::utf8(text) : String();
    }
    // Offline/UI-thread validation only. Live playback will use a dedicated
    // AudioStreamPlayback callback with preallocated buffers and command queue.
    PackedVector2Array render_block(int64_t frames) {
        PackedVector2Array result;
        if (!host || audio_owner.load(std::memory_order_acquire) || frames < 1 || frames > block) return result;
        if (!c3d_process(host, nullptr, nullptr, left.data(), right.data(), uint32_t(frames))) return result;
        result.resize(frames);
        Vector2* data = result.ptrw();
        for (int64_t i = 0; i < frames; ++i) data[i] = Vector2(left[i], right[i]);
        return result;
    }
    Ref<AudioStream> create_audio_stream();
    String render_surface() {
        const char* text = host ? c3d_render_surface(host) : nullptr;
        return text ? String::utf8(text) : String();
    }
    Ref<Image> surface_image() {
        uint32_t width = 0, height = 0;
        const uint8_t* pixels = host ? c3d_surface_rgba(host, &width, &height) : nullptr;
        if (!pixels) return Ref<Image>();
        PackedByteArray bytes; bytes.resize(int64_t(width) * height * 4);
        memcpy(bytes.ptrw(), pixels, bytes.size());
        return Image::create_from_data(width, height, false, Image::FORMAT_RGBA8, bytes);
    }
    Ref<Image> panel_image(const String& module_id) {
        uint32_t width = 0, height = 0;
        const uint8_t* pixels = host ? c3d_panel_rgba(host, module_id.utf8().get_data(), &width, &height) : nullptr;
        if (!pixels) return Ref<Image>();
        PackedByteArray bytes;
        bytes.resize(int64_t(width) * height * 4);
        memcpy(bytes.ptrw(), pixels, bytes.size());
        return Image::create_from_data(width, height, false, Image::FORMAT_RGBA8, bytes);
    }
    bool claim_audio(void* playback) {
        void* empty = nullptr;
        return host && audio_owner.compare_exchange_strong(empty, playback, std::memory_order_acq_rel);
    }
    void release_audio(void* playback) {
        audio_owner.compare_exchange_strong(playback, nullptr, std::memory_order_acq_rel);
    }
    bool mix_audio_frames(AudioFrame* output, int32_t frames) {
        for (int32_t offset = 0; offset < frames; offset += block) {
            const uint32_t count = std::min<uint32_t>(block, frames - offset);
            if (!c3d_process(host, nullptr, nullptr, left.data(), right.data(), count)) return false;
            for (uint32_t i = 0; i < count; ++i) {
                output[offset + i].left = left[i]; output[offset + i].right = right[i];
            }
        }
        return true;
    }
};

class CardinalAudioPlayback : public AudioStreamPlayback {
    GDCLASS(CardinalAudioPlayback, AudioStreamPlayback)
    std::atomic<bool> playing{false};
    std::atomic<uint32_t> mixing{0};
    std::atomic<uint64_t> processed{0};
protected:
    static void _bind_methods() {}
public:
    Ref<CardinalEmbeddedHost> host;
    double sample_rate = 48000;
    ~CardinalAudioPlayback() { _stop(); }
    void _start(double) override {
        if (playing.load() || host.is_null()) return;
        if (host->claim_audio(this)) { processed.store(0); playing.store(true, std::memory_order_release); }
    }
    void _stop() override {
        playing.store(false, std::memory_order_release);
        if (host.is_valid() && mixing.load(std::memory_order_acquire) == 0) host->release_audio(this);
    }
    bool _is_playing() const override { return playing.load(std::memory_order_acquire); }
    double _get_playback_position() const override { return processed.load() / sample_rate; }
    int32_t _mix(AudioFrame* buffer, float rate_scale, int32_t frames) override {
        mixing.fetch_add(1, std::memory_order_acq_rel);
        int32_t result = 0;
        if (playing.load(std::memory_order_acquire) && rate_scale == 1.f && host->mix_audio_frames(buffer, frames)) {
            processed.fetch_add(frames); result = frames;
        }
        if (mixing.fetch_sub(1, std::memory_order_acq_rel) == 1 && !playing.load(std::memory_order_acquire)) host->release_audio(this);
        return result;
    }
};
class CardinalAudioStream : public AudioStream {
    GDCLASS(CardinalAudioStream, AudioStream)
protected:
    static void _bind_methods() {}
public:
    Ref<CardinalEmbeddedHost> host;
    double sample_rate = 48000;
    Ref<AudioStreamPlayback> _instantiate_playback() const override {
        Ref<CardinalAudioPlayback> playback; playback.instantiate();
        playback->host = host; playback->sample_rate = sample_rate;
        return playback;
    }
    double _get_length() const override { return 0.0; }
};
Ref<AudioStream> CardinalEmbeddedHost::create_audio_stream() {
    if (!host) return Ref<AudioStream>();
    Ref<CardinalAudioStream> stream; stream.instantiate();
    stream->host = Ref<CardinalEmbeddedHost>(this);
    stream->sample_rate = sample_rate;
    // Live initialization must use AudioServer.get_mix_rate(). Pitch scaling is
    // intentionally rejected until a resampling contract is implemented.
    return stream;
}
void initialize_host(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
        ClassDB::register_class<CardinalEmbeddedHost>();
        ClassDB::register_class<CardinalAudioPlayback>();
        ClassDB::register_class<CardinalAudioStream>();
    }
}
void uninitialize_host(ModuleInitializationLevel) {}
extern "C" GDExtensionBool GDE_EXPORT cardinal3d_embedded_init(
        GDExtensionInterfaceGetProcAddress get_proc, GDExtensionClassLibraryPtr library, GDExtensionInitialization* initialization) {
    GDExtensionBinding::InitObject init(get_proc, library, initialization);
    init.register_initializer(initialize_host);
    init.register_terminator(uninitialize_host);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
