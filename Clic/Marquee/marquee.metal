#include <metal_stdlib>

using namespace metal;

// Add smoothstep function for easing
float easeInOut(float t) {
    return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t;
}

[[ stitchable ]] float2 marquee(float2 position, float time, float phase) {
    // When time is 0, don't move the text
    if (time == 0) {
        return position;
    }
    
    float x = fmod(position.x + time * 50, phase);
    if (x < 0) {
        x += phase;
    }
    return float2(x, position.y);
}
