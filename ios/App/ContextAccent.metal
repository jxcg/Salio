#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static half sampleFrostedChannel(SwiftUI::Layer layer, float2 p, float blur, int channel) {
    if (blur < 0.25f) {
        return layer.sample(p)[channel];
    }
    half center = layer.sample(p)[channel] * half(0.34f);
    half surround =
        layer.sample(p + float2(-blur, 0.0f))[channel] +
        layer.sample(p + float2( blur, 0.0f))[channel] +
        layer.sample(p + float2(0.0f, -blur))[channel] +
        layer.sample(p + float2(0.0f,  blur))[channel];
    return center + surround * half(0.165f);
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
    half r = sampleFrostedChannel(layer, position - offset * (1.0f - 0.28f * dispersion), blur, 0);
    half g = sampleFrostedChannel(layer, position - offset, blur, 1);
    half b = sampleFrostedChannel(layer, position - offset * (1.0f + 0.30f * dispersion), blur, 2);
    half a = layer.sample(position).a;

    half glaze = half(wave * 0.045f);
    return half4(clamp(r + glaze, half(0.0h), half(1.0h)),
                 clamp(g + glaze, half(0.0h), half(1.0h)),
                 clamp(b + glaze, half(0.0h), half(1.0h)),
                 a);
}
