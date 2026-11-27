#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// A soft sample of the whole pixel, colour and coverage together, so edges stay consistent.
static half4 sampleFrosted(SwiftUI::Layer layer, float2 p, float blur) {
    if (blur < 0.25f) {
        return layer.sample(p);
    }
    half4 surround =
        layer.sample(p + float2(-blur, 0.0f)) +
        layer.sample(p + float2( blur, 0.0f)) +
        layer.sample(p + float2(0.0f, -blur)) +
        layer.sample(p + float2(0.0f,  blur));
    return layer.sample(p) * half(0.34f) + surround * half(0.165f);
}

[[ stitchable ]] half4 frostedRefraction(
    float2 position,
    SwiftUI::Layer layer,
    float2 origin,
    float radius,
    float bandWidth,
    float strength,
    float blurRadius,
    float dispersion
) {
    float2 delta = position - origin;
    float dist = length(delta);
    float bandDist = fabs(dist - radius);
    if (strength <= 0.001f || bandDist >= bandWidth) {
        return layer.sample(position);
    }

    float wave = cos((bandDist / bandWidth) * 1.5707963f) * strength;
    float2 dir = dist > 0.001f ? (delta / dist) : float2(0.0f, 0.0f);
    float2 offset = dir * (wave * 11.0f);
    float blur = wave * blurRadius;

    // Natural optical dispersion: R bends slightly less than G, B bends slightly more.
    // `dispersion` scales the split, where 1 is a gentle fringe.
    half4 red = sampleFrosted(layer, position - offset * (1.0f - 0.28f * dispersion), blur);
    half4 green = sampleFrosted(layer, position - offset, blur);
    half4 blue = sampleFrosted(layer, position - offset * (1.0f + 0.30f * dispersion), blur);
    // SwiftUI layers are premultiplied, so splitting channels is only sound where all three samples
    // agree on coverage. Across a see-through edge, use the green sample whole instead, so the edge
    // refracts without stepped black or coloured fringes.
    half edge = max(abs(red.a - green.a), abs(blue.a - green.a));
    half4 colour = mix(half4(red.r, green.g, blue.b, green.a), green, edge);
    half a = colour.a;
    half3 rgb = colour.rgb + half(wave * 0.045f) * a;
    return half4(min(rgb, half3(a)), a);
}
