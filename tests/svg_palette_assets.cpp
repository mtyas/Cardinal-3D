#include <cstdio>
#define NANOSVG_IMPLEMENTATION
#include "../bridge/SvgPalette.hpp"
#include <iostream>
// Feed original asset paths on stdin; report the palette without modifying files.
int main() {
    std::string path;
    while (std::getline(std::cin, path)) {
        NSVGimage* image = nsvgParseFromFile(path.c_str(), "px", 75);
        std::cout << path << '\t' << cardinal3d::knobFaceColor(image) << '\n';
        nsvgDelete(image);
    }
}
