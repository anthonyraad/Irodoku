#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uSeed;
uniform vec4 uColor;

out vec4 fragColor;

float hash21(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  float a = hash21(i);
  float b = hash21(i + vec2(1.0, 0.0));
  float c = hash21(i + vec2(0.0, 1.0));
  float d = hash21(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * noise(p);
    p = p * 2.1 + vec2(1.4, 5.3);
    a *= 0.5;
  }
  return v;
}

vec3 hueShift(vec3 color, float shift) {
  const vec3 k = vec3(0.57735);
  float cosA = cos(shift);
  return color * cosA + cross(k, color) * sin(shift) + k * dot(k, color) * (1.0 - cosA);
}

vec3 spectrum(float t) {
  // Soft iridescent ribbon — kept pastel so base neon still dominates.
  float x = fract(t);
  return 0.5 + 0.5 * cos(6.2831853 * (x + vec3(0.0, 0.33, 0.67)));
}

void main() {
  vec2 uv = FlutterFragCoord().xy / max(uSize, vec2(1.0));
  float aspect = uSize.x / max(uSize.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);
  float seed = uSeed * 0.91;

  // Foil micro-warp.
  float n = fbm(uv * 3.5 + seed);
  vec2 q = uv + (n - 0.5) * 0.06;
  vec2 hp = p + (n - 0.5) * 0.08;

  // Viewing-angle style term for thin-film iridescence.
  float angle = atan(hp.y, hp.x);
  float radius = length(hp);
  float film = q.x * 1.7 + q.y * 1.1 + n * 1.4 + seed * 0.2;
  float iris = film * 0.55 + angle * 0.12 + radius * 0.8;

  vec3 base = uColor.rgb;
  vec3 foil = spectrum(iris);
  // Tint-preserving hologram wash (not a full rainbow takeover).
  vec3 holo = mix(base, base * foil * 1.35, 0.42);
  holo = mix(holo, hueShift(base, (n - 0.5) * 0.7), 0.18);

  // Glossy anisotropic highlight streak.
  float streakDir = sin(angle * 2.0 + seed) * 0.35;
  float streak = abs(hp.x * 0.65 - hp.y * 0.75 + streakDir);
  streak = exp(-streak * 14.0) * (0.55 + 0.45 * n);

  // Soft specular dome.
  float spec = pow(smoothstep(0.85, 0.05, radius + (n - 0.5) * 0.15), 2.2);

  // Chromatic sparkle flecks.
  float spark = smoothstep(0.78, 0.96, fbm(uv * 18.0 + seed * 3.0));

  vec3 lit = holo;
  lit += vec3(1.0) * streak * 0.55;
  lit += mix(base, vec3(1.0), 0.7) * spec * 0.35;
  lit += foil * spark * 0.22;

  // Keep punchy neon floor so slots stay distinct.
  lit = max(lit, base * 0.72);
  lit = mix(base, lit, 0.92);

  fragColor = vec4(clamp(lit, 0.0, 1.0), uColor.a);
}
