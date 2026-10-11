// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <app/LedDisplay.hpp>
#include <ui/TextField.hpp>
#include <tag.hpp>
#include "Transport.hpp"
#include <app/Scene.hpp>
#include <app/RackWidget.hpp>
#include <app/SvgKnob.hpp>
#include "SvgPalette.hpp"
#include <map>
#include <app/SvgSlider.hpp>
#include <app/SvgSwitch.hpp>
#include <app/SvgPort.hpp>
#include <app/SvgScrew.hpp>
#include <app/ModuleLightWidget.hpp>
#include <app/SvgPanel.hpp>
#include <engine/Engine.hpp>
#include <helpers.hpp>
#include <history.hpp>
#include <patch.hpp>
#include <plugin.hpp>
#include <system.hpp>
#include <ui/MenuOverlay.hpp>
#include <widget/FramebufferWidget.hpp>
#include <widget/SvgWidget.hpp>
#include <window/Window.hpp>
#include <algorithm>
#include <functional>
#include <sstream>
#include <stdexcept>
#include <unordered_map>
#include <cxxabi.h>
#include <zstd.h>

namespace rack { namespace window { void WindowSetMods(Window*, int); } }

namespace cardinal3d {
using namespace rack;

inline std::string text(json_t* object, const char* key) {
    const char* value = json_string_value(json_object_get(object, key));
    return value ? value : "";
}
inline double number(json_t* object, const char* key, double fallback = 0) {
    json_t* value = json_object_get(object, key);
    return json_is_number(value) ? json_number_value(value) : fallback;
}
inline void string(json_t* object, const char* key, const std::string& value) {
    json_object_set_new(object, key, json_string(value.c_str()));
}
inline void real(json_t* object, const char* key, double value) {
    json_object_set_new(object, key, json_real(std::isfinite(value) ? value : 0));
}
inline std::string encode(json_t* value) {
    char* buffer = json_dumps(value, JSON_COMPACT | JSON_ENCODE_ANY);
    std::string result = buffer ? buffer : "null";
    free(buffer); return result;
}
inline bool absolutePath(const std::string& path) {
#ifdef _WIN32
    return (path.size() >= 3 && ((path[0] >= 'A' && path[0] <= 'Z') || (path[0] >= 'a' && path[0] <= 'z'))
        && path[1] == ':' && (path[2] == '/' || path[2] == '\\'))
        || (path.size() > 2 && ((path[0] == '\\' && path[1] == '\\') || (path[0] == '/' && path[1] == '/')));
#else
    return !path.empty() && path[0] == '/';
#endif
}

class Bridge {
    Transport transport;
    json_t* localMessages = nullptr;
    bool inProcessMode = false;
    std::function<void(json_t*, const std::vector<uint8_t>&)> localSurface;
    bool enabled = false, authenticated = false, overlayRequested = false, compressSurfaces = false;
    std::string token;
    uint64_t generation = 1;
    std::string topology;
    double lastSeen = 0, lastSnapshot = 0, lastSurface = 0;
    size_t surfaceIndex = 0;
    std::string previousOverlayMode = "none";
    math::Vec mouse;
    int mouseMods = 0;
    int pressedButton = -1;
    bool rackPointer = false;
    std::string activeModule, movingModule;
    math::Vec movingPosition;
    std::unordered_map<std::string, double> surfaceTimes;
    std::unordered_map<std::string, uint64_t> surfaceHashes;
    std::map<std::shared_ptr<window::Svg>, std::string> knobPalette;
    std::vector<std::pair<std::string, std::unique_ptr<app::ModuleWidget>>> previews;
    std::vector<plugin::Model*> scanModels;
    size_t scanIndex = 0;
    json_t* scanReport = nullptr;
    json_t* scanCommand = nullptr;
    std::string scanPath;
    NVGLUframebuffer* framebuffer = nullptr;
    int framebufferWidth = 0, framebufferHeight = 0;
    std::unordered_map<std::string, std::string> overrides;
    static void visit(widget::Widget* root, const std::function<void(widget::Widget*)>& callback) {
        callback(root);
        for (auto* child : root->children) visit(child, callback);
    }
    bool overlayVisible() const {
        if (overlayRequested || APP->scene->browser->isVisible()) return true;
        for (auto* child : APP->scene->children)
            if (dynamic_cast<ui::MenuOverlay*>(child) && child->isVisible()) return true;
        return false;
    }
    ui::MenuOverlay* activeMenu() const {
        for (auto it = APP->scene->children.rbegin(); it != APP->scene->children.rend(); ++it)
            if (auto* menu = dynamic_cast<ui::MenuOverlay*>(*it))
                if (menu->isVisible()) return menu;
        return nullptr;
    }
    const char* overlayMode() const {
        if (overlayRequested || APP->scene->browser->isVisible()) return "full";
        return activeMenu() ? "menu" : "none";
    }
    std::string epoch() const { return std::to_string(generation); }
    app::ModuleWidget* module(const std::string& id) const {
        if (id.empty()) return nullptr;
        size_t end = 0;
        int64_t value = std::stoll(id, &end);
        if (end != id.size()) throw std::runtime_error("Invalid module ID");
        return APP->scene->rack->getModule(value);
    }
    void send(json_t* value, const std::string& key = "") {
        if (localMessages) { json_array_append_new(localMessages, value); return; }
        transport.json(encode(value), key); json_decref(value);
    }
    void ack(json_t* command, const std::string& error = "") {
        auto* value = json_object();
        string(value, "type", "ack");
        json_object_set(value, "request", json_object_get(command, "request"));
        json_object_set_new(value, "ok", json_boolean(error.empty()));
        string(value, "generation", epoch());
        if (!error.empty()) string(value, "error", error);
        send(value);
    }
    void refreshTopology() {
        std::ostringstream signature;
        for (auto* mw : APP->scene->rack->getModules()) signature << mw->module->id << ':' << mw << ';';
        const std::string next = signature.str();
        if (next != topology) {
            release(); ++generation; topology = next;
            surfaceTimes.clear(); surfaceHashes.clear(); lastSnapshot = 0;
        }
    }
    // Conservative recognizers: unknown custom parameters retain their original surface.
    std::string kind(widget::Widget* widget) const {
        if (dynamic_cast<app::SvgSlider*>(widget)) return "slider";
        if (dynamic_cast<app::SvgKnob*>(widget)) return "knob";
        if (dynamic_cast<app::Knob*>(widget)) return "knob";
        if (dynamic_cast<app::SvgSwitch*>(widget)) return "switch";
        if (dynamic_cast<app::Switch*>(widget)) return "switch";
        if (dynamic_cast<app::SvgPort*>(widget)) return "port";
        if (dynamic_cast<app::SvgScrew*>(widget)) return "screw";
        if (dynamic_cast<app::ModuleLightWidget*>(widget)) return "light";
        if (dynamic_cast<app::ParamWidget*>(widget)) return "custom";
        if (dynamic_cast<app::PortWidget*>(widget)) return "port";
        if (dynamic_cast<app::LedDisplayChoice*>(widget) || dynamic_cast<ui::TextField*>(widget)) return "custom";
        // MindMeld's group arrows are native momentary widgets without ParamWidget IDs.
        const std::string name = typeid(*widget).name();
        if (name.find("MmGroupPlusButton") != std::string::npos || name.find("MmGroupMinusButton") != std::string::npos) return "custom";
        return "";
    }
    bool physical(app::ModuleWidget* mw, widget::Widget* w) const {
        const std::string k = kind(w);
        if (k.empty() || k == "custom") return false;
        // Identify native rotary/button input semantics while retaining exact
        // custom-painted faces until a matching 3D visual is available.
        if (k == "knob" && !dynamic_cast<app::SvgKnob*>(w)) return false;
        if (k == "switch" && !dynamic_cast<app::SvgSwitch*>(w)) return false;
        // Illuminated switches must keep their composite appearance on the surface.
        if (dynamic_cast<app::Switch*>(w)) {
            bool composite = false;
            visit(w, [&](widget::Widget* child) {
                if (child != w && dynamic_cast<app::ModuleLightWidget*>(child)) composite = true;
            });
            if (composite) return false;
        }
        // Multi-color and composite controls retain the exact rendered appearance.
        if (auto* light = dynamic_cast<app::ModuleLightWidget*>(w)) {
            if (light->getNumColors() != 1) return false;
        }
        for (auto* p = w->parent; p && p != mw; p = p->parent)
            if (dynamic_cast<app::ParamWidget*>(p)) return false;
        auto it = overrides.find(mw->model->plugin->slug + "/" + mw->model->slug);
        if (it != overrides.end() && it->second == "surface") return false;
        auto component = overrides.find(mw->model->plugin->slug + "/" + mw->model->slug + "/" + k);
        return component == overrides.end() || component->second != "surface";
    }
    json_t* describe(app::ModuleWidget* mw) {
        auto* result = json_object();
        string(result, "id", std::to_string(mw->module->id));
        string(result, "plugin", mw->model->plugin->slug);
        string(result, "model", mw->model->slug);
        string(result, "name", mw->model->name);
        real(result, "x", mw->box.pos.x - app::RACK_OFFSET.x); real(result, "y", mw->box.pos.y - app::RACK_OFFSET.y);
        real(result, "width", mw->box.size.x); real(result, "height", mw->box.size.y);
        string(result, "artwork", mw->model->plugin->path);
        auto* controls = json_array(); auto* screens = json_array(); size_t screw = 0;
        visit(mw, [&](widget::Widget* w) {
            const std::string type = kind(w);
            const bool displayModel = (mw->model->plugin->slug == "Fundamental" &&
                (mw->model->slug == "ADSR" || mw->model->slug == "Scope" || mw->model->slug == "VCA-1")) ||
                (mw->model->plugin->slug == "AudibleInstruments" && mw->model->slug == "Braids");
            if (type.empty() && !displayModel) return;
            int demangleStatus = 0;
            char* typeName = abi::__cxa_demangle(typeid(*w).name(), nullptr, nullptr, &demangleStatus);
            const std::string component = typeName ? typeName : typeid(*w).name(); free(typeName);
            // Explicit visual overrides; geometry comes from instantiated widgets.
            // These widgets keep their native drawing and input behavior.
            if (displayModel && ((mw->model->slug == "ADSR" && component == "ADSRDisplay") ||
                (mw->model->slug == "Scope" && component == "ScopeDisplay") ||
                (mw->model->slug == "Braids" && component == "BraidsDisplay") ||
                (mw->model->slug == "VCA-1" && component == "VCA_1VUKnob"))) {
                auto* screen = json_object(); auto pos = w->getRelativeOffset(math::Vec(), mw);
                string(screen, "kind", component == "VCA_1VUKnob" ? "meter" : "display");
                string(screen, "component_type", component);
                real(screen, "x", pos.x); real(screen, "y", pos.y);
                real(screen, "width", w->box.size.x); real(screen, "height", w->box.size.y);
                json_array_append_new(screens, screen);
            }
            if (type.empty()) return;
            auto* control = json_object();
            string(control, "kind", type);
            string(control, "component_type", component);
            auto center = w->getRelativeOffset(w->box.size.div(2), mw);
            real(control, "x", center.x); real(control, "y", center.y);
            real(control, "width", w->box.size.x); real(control, "height", w->box.size.y);
            json_object_set_new(control, "physical", json_boolean(physical(mw, w)));
            bool visible = true;
            for (auto* ancestor = w; ancestor && ancestor != mw; ancestor = ancestor->parent)
                visible = visible && ancestor->isVisible();
            json_object_set_new(control, "visible", json_boolean(visible));
            if (auto* param = dynamic_cast<app::ParamWidget*>(w)) {
                json_object_set_new(control, "id", json_integer(param->paramId));
                if (auto* quantity = param->getParamQuantity()) {
                    string(control, "label", quantity->getLabel());
                    string(control, "display", quantity->getDisplayValueString());
                    real(control, "value", quantity->getValue());
                    real(control, "normalized", quantity->getScaledValue());
                    real(control, "min", quantity->getMinValue());
                    real(control, "max", quantity->getMaxValue());
                    real(control, "default", quantity->getDefaultValue());
                    json_object_set_new(control, "snap", json_boolean(quantity->snapEnabled));
                }
                if (auto* knob = dynamic_cast<app::Knob*>(w)) {
                    real(control, "min_angle", knob->minAngle); real(control, "max_angle", knob->maxAngle);
                }
                if (auto* knob = dynamic_cast<app::SvgKnob*>(w)) {
                    std::string faceColor;
                    // RoundKnob and Davies knobs split body/background and pointer
                    // across SVG widgets. Read visible layers in native paint order.
                    visit(knob, [&](widget::Widget* child) {
                        auto* svgWidget = dynamic_cast<widget::SvgWidget*>(child);
                        if (!svgWidget || !svgWidget->svg || !child->isVisible()) return;
                        const auto svg = svgWidget->svg;
                        auto cached = knobPalette.find(svg);
                        if (cached == knobPalette.end()) cached = knobPalette.emplace(svg, knobFaceColor(svg->handle)).first;
                        if (!cached->second.empty()) faceColor = cached->second;
                    });
                    if (!faceColor.empty()) string(control, "body_color", faceColor);
                }
                if (auto* sw = dynamic_cast<app::Switch*>(w))
                    json_object_set_new(control, "momentary", json_boolean(sw->momentary));
                if (auto* slider = dynamic_cast<app::SvgSlider*>(w)) {
                    // Slider aiming follows its moving handle, not the centre of
                    // the whole track (which can be far away on mixer faders).
                    const auto handleCenter = slider->getRelativeOffset(slider->handle->box.pos.plus(slider->handle->box.size.div(2)), mw);
                    real(control, "x", handleCenter.x); real(control, "y", handleCenter.y);
                    const auto start = slider->getRelativeOffset(slider->minHandlePos.plus(slider->handle->box.size.div(2)), mw);
                    const auto end = slider->getRelativeOffset(slider->maxHandlePos.plus(slider->handle->box.size.div(2)), mw);
                    real(control, "start_x", start.x); real(control, "start_y", start.y);
                    real(control, "end_x", end.x); real(control, "end_y", end.y);
                    real(control, "handle_width", slider->handle->box.size.x);
                    real(control, "handle_height", slider->handle->box.size.y);
                }
            } else if (auto* port = dynamic_cast<app::PortWidget*>(w)) {
                json_object_set_new(control, "id", json_integer(port->portId));
                string(control, "direction", port->type == engine::Port::INPUT ? "input" : "output");
                if (auto* info = port->getPortInfo()) string(control, "label", info->name);
                int channels = 0;
                if (port->portId >= 0) {
                    if (port->type == engine::Port::INPUT && size_t(port->portId) < mw->module->inputs.size()) channels = mw->module->inputs[port->portId].getChannels();
                    if (port->type == engine::Port::OUTPUT && size_t(port->portId) < mw->module->outputs.size()) channels = mw->module->outputs[port->portId].getChannels();
                }
                json_object_set_new(control, "channels", json_integer(channels));
            } else if (auto* light = dynamic_cast<app::ModuleLightWidget*>(w)) {
                json_object_set_new(control, "id", json_integer(light->firstLightId));
                if (auto* value = light->getLight(0)) real(control, "brightness", value->getBrightness());
                if (light->baseColors.size() == 1) string(control, "color", color::toHexString(light->baseColors.front()));
                float r = 0, g = 0, b = 0;
                for (size_t i = 0; i < light->baseColors.size(); ++i) {
                    auto* value = light->getLight(i);
                    const float brightness = value ? value->getBrightness() : 0;
                    r += light->baseColors[i].r * brightness;
                    g += light->baseColors[i].g * brightness;
                    b += light->baseColors[i].b * brightness;
                }
                real(control, "emission_r", r); real(control, "emission_g", g); real(control, "emission_b", b);
            } else string(control, "id", (type == "custom" ? "surface-" : "screw-") + std::to_string(screw++));
            json_array_append_new(controls, control);
        });
        json_object_set_new(result, "controls", controls);
        json_object_set_new(result, "screens", screens);
        return result;
    }
    void snapshot() {
        auto* root = json_object(); string(root, "type", "snapshot");
        string(root, "generation", epoch());
        string(root, "undo", APP->history->getUndoName());
        string(root, "redo", APP->history->getRedoName());
        real(root, "audio_cpu_average", APP->engine->getMeterAverage());
        real(root, "audio_cpu_max", APP->engine->getMeterMax());
        json_object_set_new(root, "gesture_active", json_boolean(pressedButton >= 0));
        auto* modules = json_array();
        for (auto* mw : APP->scene->rack->getModules()) json_array_append_new(modules, describe(mw));
        json_object_set_new(root, "modules", modules);
        auto* cables = json_array();
        for (auto* child : APP->scene->rack->getCableContainer()->children) {
            auto* cw = dynamic_cast<app::CableWidget*>(child);
            if (!cw || !cw->isComplete()) continue;
            auto* cable = cw->getCable();
            auto* value = json_object();
            string(value, "id", std::to_string(cable->id));
            string(value, "input_module", std::to_string(cable->inputModule->id));
            string(value, "output_module", std::to_string(cable->outputModule->id));
            json_object_set_new(value, "input_port", json_integer(cable->inputId));
            json_object_set_new(value, "output_port", json_integer(cable->outputId));
            char color[16]; snprintf(color, sizeof(color), "#%02x%02x%02x", int(cw->color.r*255), int(cw->color.g*255), int(cw->color.b*255));
            string(value, "color", color); json_array_append_new(cables, value);
        }
        json_object_set_new(root, "cables", cables);
        if (auto* cw = APP->scene->rack->getIncompleteCable()) {
            auto* pending = json_object();
            auto* port = cw->inputPort ? cw->inputPort : cw->outputPort;
            if (port) {
                auto* owner = port->getAncestorOfType<app::ModuleWidget>();
                if (owner) {
                    string(pending, "module", std::to_string(owner->module->id));
                    json_object_set_new(pending, "port", json_integer(port->portId));
                    string(pending, "direction", cw->inputPort ? "input" : "output");
                }
            }
            string(pending, "color", color::toHexString(cw->color));
            json_object_set_new(root, "pending_cable", pending);
        }
        json_object_set_new(root, "overlay", json_boolean(overlayVisible()));
        string(root, "overlay_mode", overlayMode());
        send(root, "snapshot");
    }
    void catalog() {
        auto* root = json_object(); string(root, "type", "catalog");
        auto* models = json_array();
        for (auto* plugin : plugin::plugins) for (auto* model : plugin->models) {
            auto* item = json_object(); string(item, "plugin", plugin->slug);
            string(item, "model", model->slug); string(item, "name", plugin->brand + " / " + model->name);
            string(item, "module_name", model->name); string(item, "manufacturer", plugin->brand);
            auto* tags = json_array();
            for (int tagId : model->tagIds) json_array_append_new(tags, json_string(tag::getTag(tagId).c_str()));
            json_object_set_new(item, "tags", tags);
            json_array_append_new(models, item);
        }
        json_object_set_new(root, "models", models); send(root);
    }
    app::ModuleWidget* add(const std::string& pluginSlug, const std::string& modelSlug, math::Vec position) {
        auto* model = plugin::getModel(pluginSlug, modelSlug);
        if (!model) throw std::runtime_error("Module is not bundled in this Cardinal build");
        auto* helper = dynamic_cast<CardinalPluginModelHelper*>(model);
        if (!helper) throw std::runtime_error("Module has no Cardinal UI factory");
        auto* mw = helper->createModuleWidget(model->createModule());
        APP->engine->addModule(mw->module);
        APP->scene->rack->addModule(mw);
        APP->scene->rack->setModulePosNearest(mw, position);
        auto* action = new history::ModuleAdd; action->setModule(mw); APP->history->push(action);
        return mw;
    }
    void connect(app::ModuleWidget* output, int outputId, app::ModuleWidget* input, int inputId, history::ComplexAction* group = nullptr) {
        auto* cw = new app::CableWidget;
        cw->color = APP->scene->rack->getNextCableColor();
        cw->outputPort = output->getOutput(outputId); cw->inputPort = input->getInput(inputId);
        cw->updateCable(); APP->scene->rack->addCable(cw);
        auto* action = new history::CableAdd; action->setCable(cw);
        if (group) group->push(action); else APP->history->push(action);
    }
    void starter(bool audible = false) {
        release();
        auto modules = APP->scene->rack->getModules();
        float x = app::RACK_OFFSET.x;
        for (auto* mw : modules) x = std::max(x, mw->box.pos.x + mw->box.size.x + 15);
        std::vector<app::ModuleWidget*> added;
        if (audible) {
            const char* plugins[] = {"AudibleInstruments", "AudibleInstruments", "Fundamental", "Fundamental", "Cardinal"};
            const char* models[] = {"Plaits", "Ripples", "VCA-1", "Scope", "HostAudio2"};
            for (size_t i = 0; i < 5; ++i) {
                auto* mw = add(plugins[i], models[i], math::Vec(x, app::RACK_OFFSET.y));
                x += mw->box.size.x; added.push_back(mw);
            }
            if (auto* level = added[2]->getParam(0)) level->getParamQuantity()->setValue(0.15f);
            connect(added[0], 0, added[1], 3);
            connect(added[1], 2, added[2], 1);
            connect(added[2], 0, added[3], 0);
            connect(added[2], 0, added[4], 0);
            connect(added[2], 0, added[4], 1);
            return;
        }
        const char* slugs[] = {"VCO", "VCF", "ADSR", "VCA-1", "Scope", "HostAudio2"};
        for (size_t i = 0; i < 6; ++i) {
            auto* mw = add(i == 5 ? "Cardinal" : "Fundamental", slugs[i], math::Vec(x, app::RACK_OFFSET.y));
            x += mw->box.size.x; added.push_back(mw);
        }
        if (auto* level = added[3]->getParam(0)) level->getParamQuantity()->setValue(0.15f);
        connect(added[0], 0, added[1], 3);
        connect(added[1], 0, added[3], 1);
        connect(added[3], 0, added[4], 0);
        connect(added[3], 0, added[5], 0);
        connect(added[3], 0, added[5], 1);
    }
    void clearPreviews() {
        for (const auto& entry : previews) {
            surfaceTimes.erase(entry.first); surfaceHashes.erase(entry.first);
        }
        previews.clear();
    }
    void preview(const std::string& pluginSlug, const std::string& modelSlug) {
        if (previews.size() >= 16) throw std::runtime_error("Preview window is limited to sixteen modules");
        auto* model = plugin::getModel(pluginSlug, modelSlug);
        auto* helper = dynamic_cast<CardinalPluginModelHelper*>(model);
        if (!helper) throw std::runtime_error("No preview factory");
        std::unique_ptr<engine::Module> instance(model->createModule());
        std::unique_ptr<app::ModuleWidget> mw(helper->createModuleWidget(instance.get()));
        if (!mw) throw std::runtime_error("No preview widget");
        instance.release(); // Unregistered widget owns its module; no audio engine insertion.
        const std::string id = "preview/" + pluginSlug + "/" + modelSlug;
        auto* descriptor = describe(mw.get()); string(descriptor, "id", id);
        auto* message = json_object(); string(message, "type", "preview");
        string(message, "generation", epoch()); json_object_set_new(message, "descriptor", descriptor);
        send(message);
        previews.emplace_back(id, std::move(mw));
    }
    void command(json_t* cmd) {
        const std::string op = text(cmd, "op");
        if (op == "hello") {
            if (number(cmd, "version") != 1) throw std::runtime_error("Unsupported bridge protocol");
            if (!token.empty() && text(cmd, "token") != token) throw std::runtime_error("Invalid session token");
            compressSurfaces = text(cmd, "surface_compression") == "zstd";
            authenticated = true; catalog(); snapshot(); return;
        }
        if (!authenticated) throw std::runtime_error("Send hello before commands");
        if (op == "heartbeat") return;
        if (op == "release") { release(); return; }
        // Preview cleanup owns no patch/widget references and must survive an
        // insertion advancing the generation earlier in the same command batch.
        if (op == "preview_clear") { clearPreviews(); return; }
        if (text(cmd, "generation") != epoch()) throw std::runtime_error("Stale scene; wait for the current snapshot");
        if (op == "pointer") {
            const std::string id = text(cmd, "module");
            math::Vec point(number(cmd, "x"), number(cmd, "y"));
            if (!std::isfinite(point.x) || !std::isfinite(point.y)) throw std::runtime_error("Invalid pointer position");
            rackPointer = id != "scene";
            auto* previousRoot = APP->event->rootWidget;
            if (rackPointer) {
                auto* mw = module(id); if (!mw) throw std::runtime_error("Module was removed");
                APP->scene->mousePos = mw->getAbsoluteOffset(point);
                point = mw->box.pos.plus(point);
                // Bypass the 2D viewport clip: modules outside the original window still work in 3D.
                APP->event->rootWidget = APP->scene->rack;
            }
            mouseMods = number(cmd, "mods");
            rack::window::WindowSetMods(APP->window, mouseMods);
            APP->event->handleHover(point, point.minus(mouse)); mouse = point;
            std::string phase = text(cmd, "phase");
            int button = number(cmd, "button");
            if (phase == "down") {
                if (pressedButton >= 0) release();
                activeModule = id; pressedButton = button;
                APP->event->handleButton(mouse, button, GLFW_PRESS, mouseMods);
            } else if (phase == "up") {
                APP->event->handleButton(mouse, button, GLFW_RELEASE, mouseMods);
                pressedButton = -1; activeModule.clear();
            }
            APP->event->rootWidget = previousRoot;
            // A raw surface click may hit decorative panel space. Never let
            // native module dragging bypass the VR title-strip placement ghost.
            if (dynamic_cast<app::ModuleWidget*>(APP->event->draggedWidget)) release();
            if (dynamic_cast<app::Knob*>(APP->event->draggedWidget)) APP->window->cursorUnlock();
        } else if (op == "parameter_choices") {
            release();
            const std::string id = text(cmd, "module");
            auto* mw = module(id);
            const int paramId = number(cmd, "param");
            if (!mw || !mw->module) throw std::runtime_error("Module was removed");
            if (paramId < 0 || paramId >= (int)mw->module->params.size()) throw std::runtime_error("Parameter does not exist");
            auto* quantity = mw->module->getParamQuantity(paramId);
            auto* widget = mw->getParam(paramId);
            // GroupSelectDisplay rounds its quantity in the upstream widget,
            // rather than setting ParamQuantity::snapEnabled.
            if (!quantity || !widget || std::string(typeid(*widget).name()).find("GroupSelectDisplay") == std::string::npos || !std::isfinite(quantity->minValue) || !std::isfinite(quantity->maxValue) || quantity->maxValue - quantity->minValue > 32)
                throw std::runtime_error("Parameter has no discrete choices");
            APP->scene->mousePos = mw->getAbsoluteOffset(math::Vec(number(cmd, "x"), number(cmd, "y")));
            auto* menu = createMenu();
            menu->addChild(createMenuLabel(quantity->getLabel()));
            for (int value = (int)std::ceil(quantity->minValue); value <= (int)std::floor(quantity->maxValue); ++value) {
                const std::string label = value == 0 ? "Main output" : "Group " + std::to_string(value);
                menu->addChild(createCheckMenuItem(label, "", [this, id, paramId, value]() {
                    auto* target = module(id);
                    auto* quantity = target && target->module && paramId < (int)target->module->params.size() ? target->module->getParamQuantity(paramId) : nullptr;
                    return quantity && quantity->getValue() == value;
                }, [this, id, paramId, value]() {
                    auto* target = module(id);
                    if (!target || !target->module || paramId >= (int)target->module->params.size()) return;
                    auto* quantity = target->module->getParamQuantity(paramId);
                    if (!quantity || quantity->getValue() == value) return;
                    auto* change = new history::ParamChange;
                    change->moduleId = target->module->id; change->paramId = paramId;
                    change->oldValue = quantity->getValue(); quantity->setValue(value);
                    change->newValue = quantity->getValue(); APP->history->push(change);
                }));
            }
        } else if (op == "drag_delta") {
            math::Vec delta(number(cmd, "dx"), number(cmd, "dy"));
            mouseMods = number(cmd, "mods"); rack::window::WindowSetMods(APP->window, mouseMods);
            auto* previousRoot = APP->event->rootWidget;
            if (rackPointer) APP->event->rootWidget = APP->scene->rack;
            mouse = mouse.plus(delta); APP->event->handleHover(mouse, delta);
            APP->event->rootWidget = previousRoot;
        } else if (op == "add") {
            release(); float x = app::RACK_OFFSET.x;
            for (auto* mw : APP->scene->rack->getModules()) x = std::max(x, mw->box.pos.x + mw->box.size.x);
            add(text(cmd, "plugin"), text(cmd, "model"), math::Vec(x, app::RACK_OFFSET.y));
        } else if (op == "new_patch") {
            release(); clearPreviews();
            APP->scene->browser->hide(); overlayRequested = false;
            APP->patch->clear();
            ++generation; surfaceTimes.clear(); surfaceHashes.clear();
            add("Cardinal", "HostAudio2", app::RACK_OFFSET);
        } else if (op == "starter" || op == "audible_starter") starter(op == "audible_starter");
        else if (op == "preview") preview(text(cmd, "plugin"), text(cmd, "model"));
        else if (op == "remove") {
            release(); auto* mw = module(text(cmd, "module"));
            if (!mw) throw std::runtime_error("Module was removed");
            mw->removeAction();
        } else if (op == "remove_many") {
            release();
            auto* ids = json_object_get(cmd, "modules");
            if (!json_is_array(ids)) throw std::runtime_error("Module list required");
            std::vector<app::ModuleWidget*> targets;
            size_t index; json_t* value;
            json_array_foreach(ids, index, value) {
                if (!json_is_string(value)) throw std::runtime_error("Invalid module id");
                auto* mw = module(json_string_value(value));
                if (!mw) throw std::runtime_error("Module was removed; try again");
                targets.push_back(mw);
            }
            // Validate everything before deleting anything. Upstream selection
            // deletion records modules and attached cables as one undo action.
            auto* rack = APP->scene->rack;
            std::vector<std::string> previous;
            for (auto* mw : rack->getSelected()) previous.push_back(std::to_string(mw->module->id));
            rack->deselectAll();
            for (auto* mw : targets) rack->select(mw);
            if (!targets.empty()) rack->deleteSelectionAction();
            rack->deselectAll();
            for (const auto& id : previous) if (auto* mw = module(id)) rack->select(mw);
            rack->updateExpanders();
        } else if (op == "patch_cable") {
            release();
            auto* output = module(text(cmd, "output_module"));
            auto* input = module(text(cmd, "input_module"));
            const int outputId = number(cmd, "output_port"), inputId = number(cmd, "input_port");
            if (!output || !input || !output->getOutput(outputId) || !input->getInput(inputId))
                throw std::runtime_error("Socket was removed");
            const std::string replaceId = text(cmd, "replace_cable");
            auto cables = APP->scene->rack->getCompleteCables();
            bool foundReplacement = replaceId.empty();
            for (auto* cw : cables) {
                auto* c = cw->getCable();
                if (std::to_string(c->id) == replaceId) {
                    if (c->outputModule != output->module || c->outputId != outputId)
                        throw std::runtime_error("Cable endpoint changed; try again");
                    foundReplacement = true;
                }
                if (c->outputModule == output->module && c->outputId == outputId && c->inputModule == input->module && c->inputId == inputId)
                    return;
            }
            if (!foundReplacement) throw std::runtime_error("Cable was removed; try again");
            auto* group = new history::ComplexAction;
            group->name = "patch cable";
            for (auto* cw : cables) {
                auto* c = cw->getCable();
                if ((c->inputModule == input->module && c->inputId == inputId) || std::to_string(c->id) == replaceId) {
                    auto* action = new history::CableRemove; action->setCable(cw); group->push(action);
                    APP->scene->rack->removeCable(cw); delete cw;
                }
            }
            connect(output, outputId, input, inputId, group);
            APP->history->push(group);
        } else if (op == "disconnect_cable") {
            release();
            for (auto* cw : APP->scene->rack->getCompleteCables()) {
                auto* c = cw->getCable();
                if (std::to_string(c->id) != text(cmd, "cable_id")) continue;
                if (std::to_string(c->inputModule->id) != text(cmd, "input_module") || c->inputId != number(cmd, "input_port"))
                    throw std::runtime_error("Cable endpoint changed; try again");
                auto* action = new history::CableRemove; action->setCable(cw);
                APP->scene->rack->removeCable(cw); delete cw;
                APP->history->push(action);
                return;
            }
            throw std::runtime_error("Cable was removed; try again");
        } else if (op == "disconnect_port") {
            release(); auto* mw = module(text(cmd, "module"));
            if (!mw) throw std::runtime_error("Module was removed");
            auto* port = text(cmd, "direction") == "output" ? mw->getOutput(number(cmd, "port")) : mw->getInput(number(cmd, "port"));
            if (!port) throw std::runtime_error("Port does not exist");
            port->deleteTopCableAction();
        } else if (op == "undo" || op == "redo") {
            release(); if (op == "undo") APP->history->undo(); else APP->history->redo();
        } else if (op == "move_begin") {
            release(); movingModule = text(cmd, "module");
            auto* mw = module(movingModule); if (!mw) throw std::runtime_error("Module was removed");
            movingPosition = mw->box.pos; APP->scene->rack->updateModuleOldPositions();
        } else if (op == "move_delta") {
            auto* mw = module(movingModule); if (!mw) throw std::runtime_error("Module was removed");
            movingPosition = movingPosition.plus(math::Vec(number(cmd, "dx"), number(cmd, "dy")));
            if (json_is_true(json_object_get(cmd, "insert"))) APP->scene->rack->setModulePosForce(mw, movingPosition);
            else APP->scene->rack->setModulePosNearest(mw, movingPosition);
        } else if (op == "move_end") finishMove();
        else if (op == "save" || op == "load") {
            release(); const std::string path = text(cmd, "path");
#ifdef _WIN32
            const bool drivePath = path.size() >= 3 && ((path[0] >= 'A' && path[0] <= 'Z') || (path[0] >= 'a' && path[0] <= 'z')) && path[1] == ':' && (path[2] == '/' || path[2] == '\\');
            const bool uncPath = path.size() > 2 && ((path[0] == '\\' && path[1] == '\\') || (path[0] == '/' && path[1] == '/'));
            if (!drivePath && !uncPath) throw std::runtime_error("An absolute patch path is required");
#else
            if (path.empty() || path[0] != '/') throw std::runtime_error("An absolute patch path is required");
#endif
            if (op == "save") { APP->patch->save(path); APP->patch->path = path; APP->history->setSaved(); }
            else {
                if (!system::isFile(path)) throw std::runtime_error("Patch file does not exist");
                ++generation; APP->patch->loadAction(path); surfaceTimes.clear();
            }
        } else if (op == "overlay") overlayRequested = json_is_true(json_object_get(cmd, "enabled"));
        else if (op == "reset_hovered") {
            auto* param = dynamic_cast<app::ParamWidget*>(APP->event->hoveredWidget);
            release();
            if (param) param->resetAction();
        }
        else if (op == "escape") {
            release(); overlayRequested = false;
            const math::Vec scenePoint = rackPointer ? APP->scene->mousePos : mouse;
            APP->event->handleKey(scenePoint, GLFW_KEY_ESCAPE, 0, GLFW_PRESS, 0);
            APP->event->handleKey(scenePoint, GLFW_KEY_ESCAPE, 0, GLFW_RELEASE, 0);
            APP->scene->browser->hide();
            for (auto* child : APP->scene->children) if (auto* menu = dynamic_cast<ui::MenuOverlay*>(child)) {
                widget::Widget::ActionEvent action; menu->onAction(action);
            }
        } else if (op == "scroll") APP->event->handleScroll(mouse, math::Vec(number(cmd, "dx"), number(cmd, "dy")));
        else if (op == "key") {
            APP->event->handleKey(mouse, number(cmd, "key"), 0, number(cmd, "pressed") ? GLFW_PRESS : GLFW_RELEASE, number(cmd, "mods"));
        } else if (op == "text") APP->event->handleText(mouse, number(cmd, "codepoint"));
        else if (op == "describe_library") describeLibrary(text(cmd, "path"));
        else throw std::runtime_error("Unknown operation: " + op);
    }
    void finishMove() {
        if (movingModule.empty()) return;
        APP->history->push(APP->scene->rack->getModuleDragAction()); movingModule.clear();
    }
    void describeLibrary(const std::string& path) {
        if (!absolutePath(path)) throw std::runtime_error("An absolute report path is required");
        if (scanReport) throw std::runtime_error("Library scan already active");
        release(); scanReport = json_object(); scanPath = path; scanIndex = 0; scanModels.clear();
        string(scanReport, "type", "library_report");
        json_object_set_new(scanReport, "modules", json_array());
        for (auto* plugin : plugin::plugins) for (auto* model : plugin->models) scanModels.push_back(model);
    }
    void scanStep() {
        if (!scanReport) return;
        if (scanIndex < scanModels.size()) {
            auto* model = scanModels[scanIndex++];
            auto* item = json_object(); string(item, "plugin", model->plugin->slug); string(item, "model", model->slug);
            try {
                auto* helper = dynamic_cast<CardinalPluginModelHelper*>(model);
                if (!helper) throw std::runtime_error("No UI factory");
                std::unique_ptr<engine::Module> instance(model->createModule());
                std::unique_ptr<app::ModuleWidget> mw(helper->createModuleWidget(instance.get()));
                if (!mw) throw std::runtime_error("UI factory returned no widget");
                instance.release(); // The widget owns its module, including subclass cleanup.
                // Scanning must not insert DSP modules into the playing patch.
                // Only playing, attached widgets step. Unattached previews can
                // have rack-dependent step handlers (or install scene overlays).
                json_object_set_new(item, "descriptor", describe(mw.get()));
                json_object_set_new(item, "stepped", json_false());
                string(item, "fallback", "interactive module surface");
            } catch (const std::exception& e) { string(item, "error", e.what()); }
            json_array_append_new(json_object_get(scanReport, "modules"), item);
            auto* progress = json_object(); string(progress, "type", "library_progress");
            json_object_set_new(progress, "completed", json_integer(scanIndex));
            json_object_set_new(progress, "total", json_integer(scanModels.size())); send(progress, "library_progress");
            return;
        }
        const bool failed = json_dump_file(scanReport, scanPath.c_str(), JSON_INDENT(2));
        if (scanCommand) ack(scanCommand, failed ? "Cannot write report" : "");
        cancelScan();
    }
    void cancelScan() {
        if (scanReport) json_decref(scanReport);
        if (scanCommand) json_decref(scanCommand);
        scanReport = scanCommand = nullptr; scanModels.clear();
    }
public:
    ~Bridge() { cancelScan(); }
    Bridge(bool inProcess = false) {
        inProcessMode = inProcess;
        if (inProcess) { authenticated = true; return; }
        const char* port = std::getenv("CARDINAL_3D_PORT");
        if (!port) return; // Existing Cardinal behaves normally unless explicitly enabled.
        int value = std::atoi(port);
        if (value < 1024 || value > 65535) return;
        const char* key = std::getenv("CARDINAL_3D_TOKEN"); token = key ? key : "";
        const char* overridePath = std::getenv("CARDINAL_3D_OVERRIDES");
        if (overridePath) {
            json_error_t error; auto* root = json_load_file(overridePath, 0, &error);
            if (root) {
                const char* name; json_t* value;
                json_object_foreach(root, name, value) if (json_is_string(value)) overrides[name] = json_string_value(value);
                json_decref(root);
            }
        }
        enabled = transport.listenOn(value);
    }
    // Same native metadata, validation and history as TCP, without a socket.
    // The caller supplies the Cardinal context on the UI/owner thread.
    std::string invokeLocal(const std::string& request) {
        if (enabled || localMessages) throw std::runtime_error("Bridge is not an idle local host");
        json_error_t error;
        json_t* cmd = request.empty() ? nullptr : json_loadb(request.data(), request.size(), JSON_REJECT_DUPLICATES, &error);
        if (!request.empty() && !json_is_object(cmd) && !json_is_array(cmd)) {
            if (cmd) json_decref(cmd);
            throw std::runtime_error("Invalid local command JSON");
        }
        std::vector<json_t*> batch;
        if (json_is_array(cmd)) {
            if (json_array_size(cmd) > 8) {
                json_decref(cmd); throw std::runtime_error("Local batch exceeds eight commands");
            }
            size_t index; json_t* item;
            json_array_foreach(cmd, index, item) {
                if (!json_is_object(item)) {
                    json_decref(cmd); throw std::runtime_error("Invalid local batch command");
                }
                batch.push_back(item);
            }
        } else if (cmd) batch.push_back(cmd);
        localMessages = json_array();
        try {
            refreshTopology();
            for (auto* item : batch) {
                try {
                    command(item); refreshTopology();
                    if (text(item, "op") == "describe_library") scanCommand = json_incref(item);
                    else ack(item);
                }
                catch (const std::exception& e) { ack(item, e.what()); }
            }
            // Controller actions keep their ordering and individual acknowledgments,
            // but the scene and live descriptors only update once per rendered frame.
            APP->scene->step();
            scanStep();
            const std::string mode = overlayMode();
            if (mode != previousOverlayMode) {
                surfaceHashes.erase("scene"); surfaceTimes.erase("scene");
                previousOverlayMode = mode;
            }
            snapshot();
            const std::string result = encode(localMessages);
            json_decref(localMessages); localMessages = nullptr;
            if (cmd) json_decref(cmd);
            return result;
        } catch (...) {
            json_decref(localMessages); localMessages = nullptr;
            if (cmd) json_decref(cmd);
            throw;
        }
    }
    app::ModuleWidget* findLocalModule(const std::string& id) const {
        if (id.compare(0, 8, "preview/") == 0) {
            for (const auto& item : previews) if (item.first == id) return item.second.get();
            return nullptr;
        }
        return module(id);
    }
    void release() {
        if (pressedButton >= 0 && APP && APP->event) {
            // Release away from ports so a dropped connection cannot accidentally patch a cable.
            math::Vec outside(-100000, -100000);
            // Clear hover without synthesizing a final drag delta (which would
            // jump a knob to its limit or alter a rotary control on disconnect).
            APP->event->setHoveredWidget(nullptr);
            APP->event->setDragHoveredWidget(nullptr);
            APP->event->handleButton(outside, pressedButton, GLFW_RELEASE, mouseMods);
        }
        pressedButton = -1; activeModule.clear();
        mouseMods = 0;
        if (APP && APP->window) rack::window::WindowSetMods(APP->window, 0);
        finishMove();
        if (APP && APP->window) APP->window->cursorUnlock();
    }
    void poll() {
        if (!enabled) return;
        const double now = system::getTime();
        refreshTopology();
        if (transport.acceptClient()) { authenticated = false; lastSeen = now; surfaceHashes.clear(); }
        for (const auto& line : transport.receive()) {
            json_error_t error;
            json_t* cmd = json_loadb(line.data(), line.size(), JSON_REJECT_DUPLICATES, &error);
            if (!json_is_object(cmd)) { if (cmd) json_decref(cmd); transport.closeClient(); break; }
            lastSeen = now;
            try {
                const uint64_t before = generation;
                command(cmd);
                refreshTopology();
                if (generation != before) { snapshot(); lastSnapshot = now; }
                if (text(cmd, "op") == "describe_library") scanCommand = json_incref(cmd);
                else ack(cmd);
            }
            catch (const std::exception& e) { ack(cmd, e.what()); }
            json_decref(cmd);
            refreshTopology();
        }
        if (transport.connected() && now - lastSeen > 3) transport.closeClient();
        if (transport.disconnected) { release(); clearPreviews(); cancelScan(); authenticated = false; transport.disconnected = false; }
        if (authenticated) scanStep();
        const std::string mode = overlayMode();
        if (mode != previousOverlayMode) {
            surfaceHashes.erase("scene"); surfaceTimes.erase("scene");
            previousOverlayMode = mode;
            lastSnapshot = 0;
        }
        if (authenticated && now - lastSnapshot > 1.0 / 60) { snapshot(); lastSnapshot = now; }
        transport.flush();
    }
#ifndef HEADLESS
    void setLocalSurfaceCallback(std::function<void(json_t*, const std::vector<uint8_t>&)> callback) { localSurface = std::move(callback); }
    void render() {
        if ((!enabled && !inProcessMode) || !authenticated || !APP->window->fbVg) return;
        const double now = system::getTime();
        if (!inProcessMode && now - lastSurface < 1.0/30) return;
        auto modules = APP->scene->rack->getModules();
        const bool overlay = overlayVisible();
        const size_t count = modules.size() + previews.size() + (overlay ? 1 : 0);
        if (!count) return;
        widget::Widget* root = nullptr; app::ModuleWidget* mw = nullptr;
        std::string id;
        if (inProcessMode && overlay && now - surfaceTimes["scene"] > 1.0 / 60) {
            root = APP->scene; id = "scene";
        }
        for (size_t tries = 0; !root && tries < count; ++tries) {
            size_t index = surfaceIndex++ % count;
            const bool isPreview = index >= modules.size() && index < modules.size() + previews.size();
            if (isPreview && surfaceHashes.count(previews[index - modules.size()].first)) continue;
            mw = index < modules.size() ? modules[index] : isPreview ? previews[index - modules.size()].second.get() : nullptr;
            root = mw ? static_cast<widget::Widget*>(mw) : APP->scene;
            id = isPreview ? previews[index - modules.size()].first : mw ? std::to_string(mw->module->id) : "scene";
            const bool liveDisplay = mw && ((mw->model->plugin->slug == "Fundamental" &&
                (mw->model->slug == "Scope" || mw->model->slug == "ADSR" || mw->model->slug == "VCA-1")) ||
                (mw->model->plugin->slug == "AudibleInstruments" && mw->model->slug == "Braids"));
            const double interval = inProcessMode && (liveDisplay || !mw || id == activeModule) ? 1.0 / 60 : mw ? 0.12 : 0.1;
            if (now - surfaceTimes[id] > interval) break;
            root = nullptr;
        }
        if (!root) return;
        const bool menuOnly = !mw && std::string(overlayMode()) == "menu";
        math::Rect region = root->box.zeroPos();
        if (menuOnly) {
            root = activeMenu();
            if (!root) return;
            bool first = true;
            for (auto* child : root->children) if (child->isVisible()) {
                region = first ? child->box : region.expand(child->box);
                first = false;
            }
            if (first) return;
            // Include menu borders; no rack, toolbar or other scene widgets are drawn.
            region.pos = region.pos.minus(math::Vec(2, 2));
            region.size = region.size.plus(math::Vec(4, 4));
        }
        const float scale = mw ? 2.0f : 1.0f;
        const int width = std::min(4096, int(std::ceil(region.size.x * scale)));
        const int height = std::min(4096, int(std::ceil(region.size.y * scale)));
        if (width <= 0 || height <= 0 || size_t(width) * height * 4 > 16 * 1024 * 1024) return;
        NVGcontext* vg = APP->window->fbVg;
        GLint previousFramebuffer, viewport[4];
        glGetIntegerv(GL_FRAMEBUFFER_BINDING, &previousFramebuffer); glGetIntegerv(GL_VIEWPORT, viewport);
        if (width != framebufferWidth || height != framebufferHeight) {
            if (framebuffer) nvgluDeleteFramebuffer(framebuffer);
            framebuffer = nvgluCreateFramebuffer(vg, width, height, 0);
            framebufferWidth = width; framebufferHeight = height;
        }
        if (!framebuffer) return;
        nvgluBindFramebuffer(framebuffer); glViewport(0, 0, width, height);
        glClearColor(menuOnly ? 0.f : 0.06f, menuOnly ? 0.f : 0.07f, menuOnly ? 0.f : 0.08f, menuOnly ? 0.f : 1.f);
        glClear(GL_COLOR_BUFFER_BIT | GL_STENCIL_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        std::vector<std::pair<widget::Widget*, bool>> visibility;
        std::vector<std::pair<widget::FramebufferWidget*, bool>> caching;
        visit(root, [&](widget::Widget* w) {
            if (auto* fb = dynamic_cast<widget::FramebufferWidget*>(w)) { caching.emplace_back(fb, fb->bypassed); fb->bypassed = true; }
            // All LEDs now have live RGB overlays, including lights nested in
            // buttons. Do not leave a stale baked glow underneath those overlays.
            if (mw && (physical(mw, w) || dynamic_cast<app::ModuleLightWidget*>(w))) { visibility.emplace_back(w, w->visible); w->visible = false; }
        });
        nvgBeginFrame(vg, width, height, 1);
        nvgScale(vg, scale, scale);
        nvgTranslate(vg, -region.pos.x, -region.pos.y);
        widget::Widget::DrawArgs args; args.vg = vg; args.fb = framebuffer; args.clipBox = region;
        root->draw(args); root->drawLayer(args, 1); nvgEndFrame(vg);
        for (const auto& entry : visibility) entry.first->visible = entry.second;
        for (const auto& entry : caching) entry.first->bypassed = entry.second;
        std::vector<uint8_t> pixels(width * height * 4);
        glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels.data());
        // DGL resolves framebuffer extensions on Windows; opengl32 only exports
        // OpenGL 1.1. Use its NanoVG helper to restore the exact previous FBO.
        NVGLUframebuffer previousTarget = {};
        previousTarget.fbo = static_cast<GLuint>(previousFramebuffer);
        nvgluBindFramebuffer(&previousTarget); glViewport(viewport[0], viewport[1], viewport[2], viewport[3]);
        surfaceTimes[id] = now; lastSurface = now;
        uint64_t hash = 1469598103934665603ull;
        for (uint8_t byte : pixels) { hash ^= byte; hash *= 1099511628211ull; }
        hash ^= uint64_t(width) << 32 | uint32_t(height);
        // A moved crop must be sent even when its pixels remain identical.
        hash ^= std::hash<float>{}(region.pos.x) + (std::hash<float>{}(region.pos.y) << 1);
        hash ^= menuOnly ? 0x91a73u : 0u;
        if (surfaceHashes.count(id) && surfaceHashes[id] == hash) return;
        surfaceHashes[id] = hash;
        auto* header = json_object(); string(header, "module", id); string(header, "generation", epoch());
        json_object_set_new(header, "width", json_integer(width)); json_object_set_new(header, "height", json_integer(height));
        if (!mw) {
            string(header, "overlay_mode", menuOnly ? "menu" : "full");
            json_object_set_new(header, "origin_x", json_real(region.pos.x));
            json_object_set_new(header, "origin_y", json_real(region.pos.y));
        }
        std::vector<uint8_t> artwork;
        artwork.reserve(pixels.size());
        for (int row = height - 1; row >= 0; --row)
            artwork.insert(artwork.end(), pixels.begin()+row*width*4, pixels.begin()+(row+1)*width*4);
        if (inProcessMode && localSurface) {
            localSurface(header, artwork);
            json_decref(header);
            return;
        }
        if (compressSurfaces) {
            std::vector<uint8_t> compressed(ZSTD_compressBound(artwork.size()));
            const size_t compressedSize = ZSTD_compress(compressed.data(), compressed.size(), artwork.data(), artwork.size(), 1);
            if (!ZSTD_isError(compressedSize) && compressedSize < artwork.size()) {
                compressed.resize(compressedSize);
                artwork.swap(compressed);
                string(header, "encoding", "zstd");
            }
        }
        std::string metadata = encode(header); json_decref(header);
        std::vector<uint8_t> payload;
        uint32_t size = metadata.size();
        for (int i = 0; i < 4; ++i) payload.push_back((size >> (8*i)) & 255);
        payload.insert(payload.end(), metadata.begin(), metadata.end());
        payload.insert(payload.end(), artwork.begin(), artwork.end());
        transport.queue(2, payload, "surface/" + id);
        transport.flush();
    }
    void destroyGraphics() {
        clearPreviews();
        if (framebuffer) nvgluDeleteFramebuffer(framebuffer);
        framebuffer = nullptr; framebufferWidth = framebufferHeight = 0;
    }
#else
    void render() {}
    void destroyGraphics() { clearPreviews(); }
#endif
};
}
