#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

[[ stitchable ]] half4 hydrationWaveMask(float2 position, half4 color, float time, float2 size, float progress, float bac) {
    if (size.x <= 0.0 || size.y <= 0.0 || progress <= 0.001) {
        return half4(color.rgb, 0.0h);
    }

    float clampedProgress = clamp(progress, 0.0, 1.0);
    float baseWaterline = (1.0 - clampedProgress) * size.y;

    // Some shader pipelines provide normalized coords; others provide pixel coords.
    float normalizedX = (position.x <= 1.5) ? clamp(position.x, 0.0, 1.0) : (position.x / max(size.x, 1.0));
    // BAC-adaptive water dynamics: calm at low BAC, more active as BAC rises.
    float intensity = clamp(bac / 0.12, 0.0, 1.0);
    float phaseScale = mix(8.0, 13.0, intensity);
    float speedA = mix(0.62, 1.65, intensity);
    float speedB = mix(0.48, 1.25, intensity);
    float ampA = mix(2.8, 7.4, intensity);
    float ampB = mix(1.1, 3.2, intensity);

    float phase = normalizedX * phaseScale;
    float wave = (sin(phase + time * speedA) * ampA) + (sin(phase * 1.58 - time * speedB) * ampB);
    float waveWaterline = baseWaterline + wave;

    if (position.y < waveWaterline) {
        return half4(color.rgb, 0.0h);
    }

    float foamBand = clamp(1.0 - abs(position.y - waveWaterline) / 4.5, 0.0, 1.0);
    float foamStrength = mix(0.18, 0.36, intensity);
    half3 foamTint = mix(color.rgb, half3(0.90h, 0.98h, 1.0h), half(foamBand * foamStrength));
    return half4(foamTint, color.a);
}
