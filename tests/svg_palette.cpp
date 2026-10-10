#include "../bridge/SvgPalette.hpp"
#include <cassert>
#include <iostream>
int main() {
    NSVGimage image{}; image.width = image.height = 30;
    NSVGshape outline{}; outline.flags = NSVG_FLAGS_VISIBLE; outline.opacity = 1;
    outline.bounds[2] = outline.bounds[3] = 30;
    outline.fill.type = NSVG_PAINT_COLOR; outline.fill.color = 0xff111111;
    NSVGshape face = outline; face.bounds[0] = face.bounds[1] = 3;
    face.bounds[2] = face.bounds[3] = 27; face.fill.color = 0xff2266dd;
    NSVGshape pointer = face; pointer.bounds[2] = 5; pointer.fill.color = 0xffffffff;
    outline.next = &face; face.next = &pointer; pointer.next = nullptr; image.shapes = &outline;
    assert(cardinal3d::knobFaceColor(&image) == "#dd6622");
    face.opacity = 0; assert(cardinal3d::knobFaceColor(&image) == "#111111");
    assert(cardinal3d::knobFaceColor(nullptr).empty());
    std::cout << "PASS: native SVG face colours, transparency and small pointer exclusion\n";
}
