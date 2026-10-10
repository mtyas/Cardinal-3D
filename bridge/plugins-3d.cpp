// SPDX-License-Identifier: GPL-3.0-or-later
// Build-only registry for the first prototype. Module implementations are unchanged.
#include "rack.hpp"
#include "plugin.hpp"
#include "Cardinal/src/plugin.hpp"
#include "Fundamental/src/plugin.hpp"
#include "AudibleInstruments/src/plugin.hpp"
#define modelADSR modelBefacoADSR
#define modelMixer modelBefacoMixer
#define modelBurst modelBefacoBurst
#define modelMixer2 modelBefacoMixer2
#define modelSlew modelBefacoSlew
#include "Befaco/src/plugin.hpp"
#undef modelADSR
#undef modelMixer
#undef modelBurst
#undef modelMixer2
#undef modelSlew

// Same exported model aliases as Cardinal’s full static registry.
extern Model* modelBogaudioVCO;
extern Model* modelLVCO;
extern Model* modelSine;
extern Model* modelPulse;
extern Model* modelXCO;
extern Model* modelAdditator;
extern Model* modelFMOp;
extern Model* modelChirp;
extern Model* modelBogaudioLFO;
extern Model* modelLLFO;
extern Model* modelFourFO;
extern Model* modelEightFO;
extern Model* modelBogaudioVCF;
extern Model* modelLVCF;
extern Model* modelFFB;
extern Model* modelEQ;
extern Model* modelEQS;
extern Model* modelLPG;
extern Model* modelLLPG;
extern Model* modelMegaGate;
extern Model* modelPEQ;
extern Model* modelPEQ6;
extern Model* modelPEQ6XF;
extern Model* modelPEQ14;
extern Model* modelPEQ14XF;
extern Model* modelDADSRH;
extern Model* modelDADSRHPlus;
extern Model* modelShaper;
extern Model* modelShaperPlus;
extern Model* modelAD;
extern Model* modelASR;
extern Model* modelBogaudioADSR;
extern Model* modelVish;
extern Model* modelFollow;
extern Model* modelDGate;
extern Model* modelRGate;
extern Model* modelEdge;
extern Model* modelBogaudioNoise;
extern Model* modelSampleHold;
extern Model* modelWalk2;
extern Model* modelWalk;
extern Model* modelMix8;
extern Model* modelMix8x;
extern Model* modelMix4;
extern Model* modelMix4x;
extern Model* modelMix2;
extern Model* modelMix1;
extern Model* modelVCM;
extern Model* modelMute8;
extern Model* modelPan;
extern Model* modelXFade;
extern Model* modelBogaudioVCA;
extern Model* modelVCAmp;
extern Model* modelVelo;
extern Model* modelUMix;
extern Model* modelMumix;
extern Model* modelMatrix81;
extern Model* modelMatrix18;
extern Model* modelMatrix44;
extern Model* modelMatrix44Cvm;
extern Model* modelMatrix88;
extern Model* modelMatrix88Cv;
extern Model* modelMatrix88M;
extern Model* modelSwitch81;
extern Model* modelSwitch18;
extern Model* modelSwitch44;
extern Model* modelSwitch88;
extern Model* modelSwitch1616;
extern Model* modelAMRM;
extern Model* modelPressor;
extern Model* modelClpr;
extern Model* modelLmtr;
extern Model* modelNsgt;
extern Model* modelCmpDist;
extern Model* modelOneEight;
extern Model* modelEightOne;
extern Model* modelAddrSeq;
extern Model* modelAddrSeqX;
extern Model* modelPgmr;
extern Model* modelPgmrX;
extern Model* modelVU;
extern Model* modelAnalyzer;
extern Model* modelAnalyzerXL;
extern Model* modelRanalyzer;
extern Model* modelDetune;
extern Model* modelStack;
extern Model* modelReftone;
extern Model* modelMono;
extern Model* modelArp;
extern Model* modelAssign;
extern Model* modelUnison;
extern Model* modelPolyCon8;
extern Model* modelPolyCon16;
extern Model* modelPolyOff8;
extern Model* modelPolyOff16;
extern Model* modelPolyMult;
extern Model* modelBool;
extern Model* modelCmp;
extern Model* modelCVD;
extern Model* modelFlipFlop;
extern Model* modelInv;
extern Model* modelManual;
extern Model* modelFourMan;
extern Model* modelMult;
extern Model* modelOffset;
extern Model* modelSlew;
extern Model* modelSums;
extern Model* modelSwitch;
extern Model* modelLgsw;
extern Model* modelBlank3;
extern Model* modelBlank6;

Plugin* pluginInstance__Cardinal;
Plugin* pluginInstance__Fundamental;
Plugin* pluginInstance__AudibleInstruments;
Plugin* pluginInstance__Befaco;
Plugin* pluginInstance__BogaudioModules;
std::vector<Model*> hostTerminalModels;

namespace rack { namespace asset {
std::string pluginManifest(const std::string&);
std::string pluginPath(const std::string&);
} namespace plugin {

static Plugin* load(const char* dirname, std::initializer_list<Model*> models) {
    auto* p = new Plugin;
    p->path = asset::pluginPath(dirname);
    json_error_t error;
    auto* root = json_load_file(asset::pluginManifest(dirname).c_str(), 0, &error);
    if (!root) { delete p; throw Exception("Cannot load manifest for %s: %s", dirname, error.text); }
    p->fromJson(root);
    auto* filtered = json_array();
    for (auto* model : models) {
        p->addModel(model);
        size_t i; json_t* entry;
        json_array_foreach(json_object_get(root, "modules"), i, entry) {
            const char* slug = json_string_value(json_object_get(entry, "slug"));
            if (slug && model->slug == slug) json_array_append(filtered, entry);
        }
    }
    p->modulesFromJson(filtered);
    json_decref(filtered); json_decref(root); plugins.push_back(p); return p;
}
void initStaticPlugins() {
    pluginInstance__Cardinal = load("Cardinal", {modelHostAudio2, modelHostAudio8});
    pluginInstance__Fundamental = load("Fundamental", {
        modelVCO, modelVCO2, modelVCF, modelVCA_1, modelVCA, modelLFO, modelLFO2,
        modelDelay, modelADSR, modelMixer, modelVCMixer, model_8vert,
        modelMutes, modelPulses, modelScope, modelSEQ3, modelSequentialSwitch1,
        modelSequentialSwitch2, modelOctave, modelQuantizer, modelSplit,
        modelMerge, modelSum, modelMidSide, modelNoise, modelRandom});
    pluginInstance__AudibleInstruments = load("AudibleInstruments", {
        modelBraids, modelPlaits, modelElements, modelTides, modelTides2,
        modelClouds, modelWarps, modelRings, modelLinks, modelKinks, modelShades,
        modelBranches, modelBlinds, modelVeils, modelFrames, modelMarbles,
        modelStages, modelRipples, modelShelves, modelStreams});
    pluginInstance__BogaudioModules = load("BogaudioModules", {
        modelBogaudioVCO, modelLVCO, modelSine, modelPulse, modelXCO, modelAdditator,
        modelFMOp, modelChirp, modelBogaudioLFO, modelLLFO, modelFourFO, modelEightFO,
        modelBogaudioVCF, modelLVCF, modelFFB, modelEQ, modelEQS, modelLPG,
        modelLLPG, modelMegaGate, modelPEQ, modelPEQ6, modelPEQ6XF, modelPEQ14,
        modelPEQ14XF, modelDADSRH, modelDADSRHPlus, modelShaper, modelShaperPlus, modelAD,
        modelASR, modelBogaudioADSR, modelVish, modelFollow, modelDGate, modelRGate,
        modelEdge, modelBogaudioNoise, modelSampleHold, modelWalk2, modelWalk, modelMix8,
        modelMix8x, modelMix4, modelMix4x, modelMix2, modelMix1, modelVCM,
        modelMute8, modelPan, modelXFade, modelBogaudioVCA, modelVCAmp, modelVelo,
        modelUMix, modelMumix, modelMatrix81, modelMatrix18, modelMatrix44, modelMatrix44Cvm,
        modelMatrix88, modelMatrix88Cv, modelMatrix88M, modelSwitch81, modelSwitch18, modelSwitch44,
        modelSwitch88, modelSwitch1616, modelAMRM, modelPressor, modelClpr, modelLmtr,
        modelNsgt, modelCmpDist, modelOneEight, modelEightOne, modelAddrSeq, modelAddrSeqX,
        modelPgmr, modelPgmrX, modelVU, modelAnalyzer, modelAnalyzerXL, modelRanalyzer,
        modelDetune, modelStack, modelReftone, modelMono, modelArp, modelAssign,
        modelUnison, modelPolyCon8, modelPolyCon16, modelPolyOff8, modelPolyOff16, modelPolyMult,
        modelBool, modelCmp, modelCVD, modelFlipFlop, modelInv, modelManual,
        modelFourMan, modelMult, modelOffset, modelSlew, modelSums, modelSwitch,
        modelLgsw, modelBlank3, modelBlank6});
    hostTerminalModels = {modelHostAudio2, modelHostAudio8};
    pluginInstance__Befaco = load("Befaco", {
        modelEvenVCO, modelRampage, modelABC, modelSpringReverb, modelBefacoMixer,
        modelSlewLimiter, modelDualAtenuverter, modelPercall, modelHexmixVCA,
        modelChoppingKinky, modelKickall, modelSamplingModulator, modelMorphader,
        modelBefacoADSR, modelSTMix, modelMuxlicer, modelMex, modelNoisePlethora,
        modelChannelStrip, modelPonyVCO, modelMotionMTR, modelBefacoBurst,
        modelVoltio, modelOctaves, modelBypass, modelBandit, modelBefacoMixer2,
        modelAtte, modelAxBC, modelBefacoSlew, modelMuDi});
}
void destroyStaticPlugins() { for (auto* p : plugins) delete p; plugins.clear(); }
void updateStaticPluginsDarkMode() {}
} }
