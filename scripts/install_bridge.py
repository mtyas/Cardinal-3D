#!/usr/bin/env python3
"""Apply the UI-only overlay to the exact pinned Cardinal checkout, idempotently."""
from pathlib import Path
import json
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CARDINAL = ROOT / "vendor/Cardinal"

def replace(path, old, new):
    data = path.read_text()
    if new in data:
        return
    if data.count(old) != 1:
        raise RuntimeError(f"Unexpected upstream content: {path}: {old!r}")
    path.write_text(data.replace(old, new))

def main():
    pin = json.loads((ROOT / "upstream.lock.json").read_text())["commit"]
    revision = subprocess.check_output(["git", "-C", str(CARDINAL), "rev-parse", "HEAD"], text=True).strip()
    if revision != pin:
        raise RuntimeError(f"Expected Cardinal {pin}, found {revision}")
    target = CARDINAL / "src/cardinal3d"
    target.mkdir(exist_ok=True)
    for filename in ("Transport.hpp", "Cardinal3DBridge.hpp"):
        shutil.copy2(ROOT / "bridge" / filename, target / filename)
    shutil.copy2(ROOT / "bridge/plugins-3d.cpp", CARDINAL / "plugins/plugins-3d.cpp")
    ui = CARDINAL / "src/CardinalUI.cpp"
    # Preserve subclass destructors during standalone extraction. Only registered
    # widgets remove a module from the live engine; preview widgets still own/delete it.
    replace(CARDINAL / "src/override/ModuleWidget.cpp", '\t\tAPP->engine->removeModule(this->module);', '\t\tif (APP->engine->getModule(this->module->id) == this->module)\n\t\t\tAPP->engine->removeModule(this->module);')
    replace(ui, '#include "WindowParameters.hpp"', '#include "WindowParameters.hpp"\n#if defined(CARDINAL_3D_BRIDGE) && !defined(DISTRHO_OS_WASM)\n#include "cardinal3d/Cardinal3DBridge.hpp"\n#endif')
    replace(ui, '    int rateLimitStep = 0;', '    int rateLimitStep = 0;\n#ifdef CARDINAL_3D_BRIDGE\n    cardinal3d::Bridge spatialBridge;\n#endif')
    replace(ui, '        context->window->step();\n    }\n\n    void uiIdle()', '        context->window->step();\n#ifdef CARDINAL_3D_BRIDGE\n        spatialBridge.render();\n#endif\n    }\n\n    void uiIdle()')
    replace(ui, '    void uiIdle() override\n    {', '    void uiIdle() override\n    {\n#ifdef CARDINAL_3D_BRIDGE\n        { const ScopedContext sc(this); spatialBridge.poll(); }\n#endif')
    replace(ui, '        context->nativeWindowId = 0;', '        context->nativeWindowId = 0;\n#ifdef CARDINAL_3D_BRIDGE\n        spatialBridge.release();\n        { const DGL_NAMESPACE::Window::ScopedGraphicsContext sgc(getWindow()); spatialBridge.destroyGraphics(); }\n#endif')
    build = CARDINAL / "src/Makefile.cardinal.mk"
    replace(build, 'SURGE_DEP_PATH = $(abspath ../../deps/surge-build)', 'ifneq ($(CARDINAL_3D_PROTOTYPE),true)\nSURGE_DEP_PATH = $(abspath ../../deps/surge-build)')
    replace(build, '# Extra libraries to link against', '# Extra libraries to link against\nendif # full-library Surge dependencies')
    replace(build, 'BASE_FLAGS += -DPRIVATE=', 'BASE_FLAGS += -DPRIVATE=\nifeq ($(CARDINAL_3D_BRIDGE),true)\nBASE_FLAGS += -DCARDINAL_3D_BRIDGE\nendif')
    plugins = CARDINAL / "plugins/Makefile"
    prototype = 'ifeq ($(CARDINAL_3D_PROTOTYPE),true)\nPLUGIN_FILES = plugins-3d.cpp Cardinal/src/HostAudio.cpp Fundamental/src/VCO.cpp Fundamental/src/VCF.cpp Fundamental/src/ADSR.cpp Fundamental/src/VCA-1.cpp Fundamental/src/Scope.cpp\nPLUGIN_BINARIES =\ninclude cardinal3d-audible.mk\nendif\n\nPLUGIN_OBJS  = $(PLUGIN_FILES:%=$(BUILD_DIR)/%.o)'
    old_prototype = prototype.replace('include cardinal3d-audible.mk\n', '')
    if old_prototype in plugins.read_text():
        replace(plugins, old_prototype, prototype)
    else:
        replace(plugins, 'PLUGIN_OBJS  = $(PLUGIN_FILES:%=$(BUILD_DIR)/%.o)', prototype)
    replace(plugins, '$(BUILD_DIR)/plugins.cpp.o: plugins.cpp', '$(BUILD_DIR)/plugins-3d.cpp.o: plugins-3d.cpp\n\t@mkdir -p $(dir $@)\n\t$(CXX) $< $(BUILD_CXX_FLAGS) -c -o $@\n\n$(BUILD_DIR)/plugins.cpp.o: plugins.cpp')
    # Reuse the pinned upstream source list and its existing per-plugin compiler
    # flags. No Audible Instruments DSP source or implementation is copied/edited.
    upstream_make = subprocess.check_output(["git", "-C", str(CARDINAL), "show", "HEAD:plugins/Makefile"], text=True)
    audible_block = upstream_make.split("# AudibleInstruments\n", 1)[1].split("# Autinn\n", 1)[0]
    audible_sources = "\n".join(line for line in audible_block.splitlines() if line.startswith("PLUGIN_FILES +=")) + "\n"
    fundamental_block = upstream_make.split("# Fundamental (always enabled)\n", 1)[1].split("# ZamAudio", 1)[0]
    fundamental_sources = "\n".join(line for line in fundamental_block.splitlines() if line.startswith("PLUGIN_FILES +=")) + "\n"
    befaco_block = upstream_make.split("# Befaco\n", 1)[1].split("# Bidoo\n", 1)[0]
    befaco_sources = "\n".join(line for line in befaco_block.splitlines() if line.startswith("PLUGIN_FILES +=")) + "\n"
    bogaudio_block = upstream_make.split("# BogaudioModules\n", 1)[1].split("# ChowDSP\n", 1)[0]
    bogaudio_sources = "\n".join(line for line in bogaudio_block.splitlines() if line.startswith("PLUGIN_FILES +=")) + "\n"
    (CARDINAL / "plugins/cardinal3d-audible.mk").write_text(fundamental_sources + audible_sources + befaco_sources + bogaudio_sources)
    replace(plugins, 'PLUGIN_BINARIES =\nendif\n\nPLUGIN_OBJS', 'PLUGIN_BINARIES =\ninclude cardinal3d-audible.mk\nendif\n\nPLUGIN_OBJS')
    print("Installed Cardinal UI bridge; no DSP source changed.")

if __name__ == "__main__":
    main()
