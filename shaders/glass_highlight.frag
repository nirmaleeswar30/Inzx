// Liquid glass rim highlight, ported from Kyant0/backdrop's
// DefaultHighlight / AmbientHighlight AGSL shaders (Apache-2.0).
//
// Upstream strokes the outline twice the rim width, clips it to the inside
// of the shape, blurs the stroke and colours it with the shader. Here the
// band, its soft inner edge and the directional falloff are all evaluated
// analytically in one pass over the surface: no stroke, no mask blur and
// no offscreen layer.

#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;      // logical size of the surface
uniform vec4 uRadii;     // logical corner radii, clockwise from top-left
uniform vec4 uColor;     // straight (non-premultiplied) colour; .a is the paint alpha
uniform float uAngle;    // light direction, radians
uniform float uFalloff;
uniform float uWidth;    // rim width in physical pixels
uniform float uBlur;     // rim softness (sigma) in physical pixels
uniform float uDpr;
uniform float uMode;     // 0 = directional, 1 = ambient (light + shade), 2 = plain

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

void main() {
    vec2 halfSize = uSize * 0.5;
    vec2 centered = FlutterFragCoord().xy - halfSize;
    float radius = radiusAt(centered, uRadii);

    // Distance in from the edge, in physical pixels.
    float inset = -sdRoundedRect(centered, halfSize, radius) * uDpr;
    float soft = max(uBlur * 2.0, 1.0);
    float coverage = clamp(inset + 0.5, 0.0, 1.0) *
        clamp((uWidth - inset) / soft + 0.5, 0.0, 1.0);
    if (coverage <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    float gradRadius = min(radius * 1.5, min(halfSize.x, halfSize.y));
    vec2 grad = gradSdRoundedRect(centered, halfSize, gradRadius);
    vec2 normal = vec2(cos(uAngle), sin(uAngle));
    float d = dot(grad, normal);
    float intensity = uMode > 1.5 ? 1.0 : pow(abs(d), uFalloff);

    float a = uColor.a * intensity * coverage;
    if (uMode < 0.5 || uMode > 1.5) {
        fragColor = vec4(uColor.rgb * a, a);
    } else {
        float t = step(0.0, d);
        fragColor = vec4(vec3(t) * a, a);
    }
}
