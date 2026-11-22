#include <metal_stdlib>
using namespace metal;

[[ stitchable ]] half4 contextAccent(float2 position, half4 color, float4 bounds) {
    float y = position.y - bounds.y;
    float edge = min(y, bounds.w - y);
    return color * half(smoothstep(0.0f, 4.0f, edge));
}
