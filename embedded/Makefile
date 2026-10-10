NAME = CardinalEmbedded
CARDINAL_VARIANT = native
HEADLESS = true
include ../Makefile.cardinal.mk
# Retain the exact module widget factories/DSP used by the working VR build.
# Upstream's headless HostAudio widget omits panel size, knobs and jack layout.
RACK_EXTRA_LIBS := $(subst plugins-headless.a,plugins.a,$(RACK_EXTRA_LIBS))

.PHONY: embedded
embedded: ../../bin/Cardinal3DEngine.dll
$(BUILD_DIR)/Host.cpp.o: Host.cpp Host.h
	@mkdir -p $(dir $@)
	$(CXX) $< $(BUILD_CXX_FLAGS) -DDISTRHO_PLUGIN_TARGET_STATIC -c -o $@
# DPF's Windows MAPI adapter also contains the plugin implementation; Host.cpp
# supplies that implementation directly, so retain only Cardinal's DSP objects.
EMBEDDED_OBJS = $(filter-out %/DistrhoPluginMain_MAPI.cpp.o,$(OBJS_DSP))
../../bin/Cardinal3DEngine.dll: $(EMBEDDED_OBJS) $(BUILD_DIR)/Host.cpp.o Makefile
	@mkdir -p $(dir $@)
	$(CXX) $(filter %.o,$^) $(BUILD_CXX_FLAGS) $(LINK_FLAGS) $(EXTRA_LIBS) $(EXTRA_DSP_LIBS) -shared -Wl,--out-implib,../../bin/libCardinal3DEngine.dll.a -o $@
