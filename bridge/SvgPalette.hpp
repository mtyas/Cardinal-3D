#pragma once
#include <nanosvg.h>
#include <cmath>
#include <cstdio>
#include <string>

namespace cardinal3d {
// Sample substantial, centered face layers, excluding small pointer marks.
// Later SVG layers cover earlier outlines. Keep custom artwork as a fallback.
inline std::string knobFaceColor(const NSVGimage* image) {
    if (!image || image->width <= 0 || image->height <= 0) return {};
    unsigned int color = 0;
    bool found = false;
    for (const NSVGshape* shape = image->shapes; shape; shape = shape->next) {
        if (!(shape->flags & NSVG_FLAGS_VISIBLE) || shape->opacity < 0.5f) continue;
        const float width = shape->bounds[2] - shape->bounds[0];
        const float height = shape->bounds[3] - shape->bounds[1];
        if (width < image->width * 0.5f || height < image->height * 0.5f) continue;
        if (std::fabs((shape->bounds[0] + shape->bounds[2]) / 2 - image->width / 2) > image->width * 0.15f ||
            std::fabs((shape->bounds[1] + shape->bounds[3]) / 2 - image->height / 2) > image->height * 0.15f) continue;
        unsigned int candidate;
        if (shape->fill.type == NSVG_PAINT_COLOR) candidate = shape->fill.color;
        else if ((shape->fill.type == NSVG_PAINT_LINEAR_GRADIENT || shape->fill.type == NSVG_PAINT_RADIAL_GRADIENT) &&
                 shape->fill.gradient && shape->fill.gradient->nstops > 0) {
            const NSVGgradient* gradient = shape->fill.gradient;
            // Use the middle stop for a representative material, not a shadow edge.
            int closest = 0;
            for (int i = 1; i < gradient->nstops; ++i)
                if (std::fabs(gradient->stops[i].offset - 0.5f) < std::fabs(gradient->stops[closest].offset - 0.5f)) closest = i;
            candidate = gradient->stops[closest].color;
        } else continue;
        if ((candidate >> 24) < 128) continue;
        color = candidate; found = true;
    }
    if (!found) return {};
    char text[8];
    std::snprintf(text, sizeof(text), "#%02x%02x%02x", color & 255, (color >> 8) & 255, (color >> 16) & 255);
    return text;
}
}
