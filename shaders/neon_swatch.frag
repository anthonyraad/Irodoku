#include <flutter/runtime_effect.glsl>

// Unused — Neon glow is a soft radial gradient in Dart (NeonSwatchShader).
// Kept so pubspec asset registration stays valid if referenced elsewhere.

uniform vec2 uSize;
uniform float uSeed;
uniform vec4 uColor;

out vec4 fragColor;

void main() {
  fragColor = uColor;
}
