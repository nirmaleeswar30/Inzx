// Liquid glass lens: rounded-rect edge refraction with optional chromatic
// dispersion. A line-for-line GLSL port of the AGSL
// RoundedRectRefraction[WithDispersion] shaders from Kyant0/backdrop
// (Apache-2.0), which both LastWave and BitChord render their glass with.
//
// Runs as an ImageFilter.shader inside a BackdropFilter, after the colour
// matrix and blur, exactly where the Kotlin version runs it in its
// RenderEffect chain. Pixels deeper inside the shape than the refraction
// band take the early return, so the cost is one texture read for all of
// the interior and the extra work only happens along the rim.

#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

// Filled in by the engine for ImageFilter.shader: the input texture's size.
uniform vec2 uTexSize;
// The glass shape in the input texture's pixel space: left, top, width, height.
uniform vec4 uRect;
// Corner radii, clockwise from top-left, in the same pixel space.
uniform vec4 uRadii;
uniform float uRefractionHeight;
uniform float uRefractionAmount;
uniform float uDepthEffect;
uniform float uChromatic;

uniform sampler2D uTexture;

out vec4 fragColor;

float radiusAt(vec2 coord, vec4 radii) {
    if (coord.x >= 0.0) {
        return coord.y <= 0.0 ? radii.y : radii.z;
    }
    return coord.y <= 0.0 ? radii.x : radii.w;
}

float sdRoundedRect(vec2 coord, vec2 halfSize, float radius) {
    vec2 cornerCoord = abs(coord) - (halfSize - vec2(radius));
    float outside = length(max(cornerCoord, 0.0)) - radius;
    float inside = min(max(cornerCoord.x, cornerCoord.y), 0.0);
    return outside + inside;
}

vec2 gradSdRoundedRect(vec2 coord, vec2 halfSize, float radius) {
    vec2 cornerCoord = abs(coord) - (halfSize - vec2(radius));
    if (cornerCoord.x >= 0.0 || cornerCoord.y >= 0.0) {
        vec2 c = max(cornerCoord, 0.0);
        float l = max(length(c), 1e-4);
        return sign(coord) * (c / l);
    }
    float gradX = step(cornerCoord.y, cornerCoord.x);
    return sign(coord) * vec2(gradX, 1.0 - gradX);
}

float circleMap(float x) {
    return 1.0 - sqrt(1.0 - x * x);
}

vec4 sampleAt(vec2 p) {
    vec2 uv = p / uTexSize;
#ifdef IMPELLER_TARGET_OPENGLES
    uv.y = 1.0 - uv.y;
#endif
    return texture(uTexture, uv);
}

vec2 safeNormalize(vec2 v) {
    float l = length(v);
    return l > 1e-4 ? v / l : vec2(0.0);
}

void main() {
    vec2 coord = FlutterFragCoord().xy;
    vec2 halfSize = uRect.zw * 0.5;
    vec2 centered = coord - uRect.xy - halfSize;
    float radius = radiusAt(centered, uRadii);

    float sd = sdRoundedRect(centered, halfSize, radius);
    if (uRefractionHeight <= 0.0 || -sd >= uRefractionHeight) {
        fragColor = sampleAt(coord);
        return;
    }
    sd = min(sd, 0.0);

    // The upstream shader is handed -refractionAmount, so it pulls samples
    // inward from the rim; the sign is folded in here instead.
    float d = -circleMap(1.0 - -sd / uRefractionHeight) * uRefractionAmount;
    float gradRadius = min(radius * 1.5, min(halfSize.x, halfSize.y));
    vec2 grad = safeNormalize(
        gradSdRoundedRect(centered, halfSize, gradRadius) +
        uDepthEffect * safeNormalize(centered)
    );

    vec2 refracted = coord + d * grad;
    if (uChromatic < 0.5) {
        fragColor = sampleAt(refracted);
        return;
    }

    float dispersionIntensity = (centered.x * centered.y) / (halfSize.x * halfSize.y);
    vec2 dispersed = d * grad * dispersionIntensity;

    vec4 color = vec4(0.0);

    vec4 red = sampleAt(refracted + dispersed);
    color.r += red.r / 3.5;
    color.a += red.a / 7.0;

    vec4 orange = sampleAt(refracted + dispersed * (2.0 / 3.0));
    color.r += orange.r / 3.5;
    color.g += orange.g / 7.0;
    color.a += orange.a / 7.0;

    vec4 yellow = sampleAt(refracted + dispersed * (1.0 / 3.0));
    color.r += yellow.r / 3.5;
    color.g += yellow.g / 3.5;
    color.a += yellow.a / 7.0;

    vec4 green = sampleAt(refracted);
    color.g += green.g / 3.5;
    color.a += green.a / 7.0;

    vec4 cyan = sampleAt(refracted - dispersed * (1.0 / 3.0));
    color.g += cyan.g / 3.5;
    color.b += cyan.b / 3.0;
    color.a += cyan.a / 7.0;

    vec4 blue = sampleAt(refracted - dispersed * (2.0 / 3.0));
    color.b += blue.b / 3.0;
    color.a += blue.a / 7.0;

    vec4 purple = sampleAt(refracted - dispersed);
    color.r += purple.r / 7.0;
    color.b += purple.b / 3.0;
    color.a += purple.a / 7.0;

    fragColor = color;
}
