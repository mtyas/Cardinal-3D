// SPDX-License-Identifier: GPL-3.0-or-later
// Offline host for the *existing* Cardinal plugin. No replacement DSP implementation.
#define DISTRHO_PLUGIN_TARGET_JACK
#define main cardinal_unused_native_main
#include "DistrhoPluginMain.cpp"
#undef main
#include "CardinalPluginContext.hpp"
#include <patch.hpp>
#include <random.hpp>
#include <settings.hpp>
#include <fstream>
#include <cmath>

int main(int argc, char** argv) {
    if (argc != 3) return 2;
    using namespace CardinalDISTRHO;
    d_nextBufferSize = 256; d_nextSampleRate = 48000;
    PluginExporter host(nullptr, nullptr, nullptr, nullptr);
    auto* plugin = static_cast<CardinalBasePlugin*>(host.getInstancePointer());
    rack::contextSet(plugin->context);
    plugin->context->patch->load(argv[1]);
    rack::settings::threadCount = 1;
    rack::random::local().seed(1234567, 7654321);
    host.activate();
    float silence[256] = {}, left[256], right[256];
    const float* inputs[] = {silence, silence};
    float* outputs[] = {left, right};
    std::ofstream file(argv[2], std::ios::binary);
    double energy = 0;
    TimePosition time;
    time.playing = true;
    for (int block = 0; block < 750; ++block) {
        time.frame = block * 256;
        host.setTimePosition(time);
        host.run(inputs, outputs, 256, nullptr, 0);
        for (int i = 0; i < 256; ++i) {
            if (!std::isfinite(left[i]) || !std::isfinite(right[i])) return 3;
            file.write(reinterpret_cast<char*>(&left[i]), sizeof(float));
            file.write(reinterpret_cast<char*>(&right[i]), sizeof(float));
            energy += double(left[i]) * left[i] + double(right[i]) * right[i];
        }
    }
    host.deactivate(); rack::contextSet(nullptr);
    return file.good() && energy > 1e-4 ? 0 : 4;
}
