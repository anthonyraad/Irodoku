#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uSeed;
uniform vec4 uStart;
uniform vec4 uStop;
uniform float uTime;
uniform float uIntensity;

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

// Soft, large-scale fbm — keeps blobs big and edges mushy.
float fbm(vec2 p) {
  float value = 0.0;
  float amplitude = 0.5;
  for (int i = 0; i < 4; i++) {
    value += amplitude * noise(p);
    p = p * 1.85 + vec2(1.3, 4.7);
    amplitude *= 0.55;
  }
  return value;
}

vec3 rgb2hsl(vec3 c) {
  float maxC = max(c.r, max(c.g, c.b));
  float minC = min(c.r, min(c.g, c.b));
  float l = (maxC + minC) * 0.5;
  float d = maxC - minC;
  float h = 0.0;
  float s = 0.0;
  if (d > 0.0001) {
    s = l > 0.5 ? d / (2.0 - maxC - minC) : d / (maxC + minC);
    if (maxC == c.r) {
      h = (c.g - c.b) / d + (c.g < c.b ? 6.0 : 0.0);
    } else if (maxC == c.g) {
      h = (c.b - c.r) / d + 2.0;
    } else {
      h = (c.r - c.g) / d + 4.0;
    }
    h /= 6.0;
  }
  return vec3(h, s, l);
}

float hue2rgb(float p, float q, float t) {
  if (t < 0.0) t += 1.0;
  if (t > 1.0) t -= 1.0;
  if (t < 1.0 / 6.0) return p + (q - p) * 6.0 * t;
  if (t < 1.0 / 2.0) return q;
  if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
  return p;
}

vec3 hsl2rgb(vec3 hsl) {
  if (hsl.y <= 0.0001) {
    return vec3(hsl.z);
  }
  float q = hsl.z < 0.5 ? hsl.z * (1.0 + hsl.y) : hsl.z + hsl.y - hsl.z * hsl.y;
  float p = 2.0 * hsl.z - q;
  return vec3(
    hue2rgb(p, q, hsl.x + 1.0 / 3.0),
    hue2rgb(p, q, hsl.x),
    hue2rgb(p, q, hsl.x - 1.0 / 3.0)
  );
}

vec4 blendHsl(vec4 a, vec4 b, float t) {
  vec3 ha = rgb2hsl(a.rgb);
  vec3 hb = rgb2hsl(b.rgb);
  float dh = hb.x - ha.x;
  if (dh > 0.5) dh -= 1.0;
  if (dh < -0.5) dh += 1.0;
  vec3 mixed = vec3(
    fract(ha.x + dh * t),
    mix(ha.y, hb.y, t),
    mix(ha.z, hb.z, t)
  );
  return vec4(hsl2rgb(mixed), mix(a.a, b.a, t));
}

void main() {
  vec2 uv = FlutterFragCoord().xy / max(uSize, vec2(1.0));
  float aspect = uSize.x / max(uSize.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);

  float intensity = max(uIntensity, 0.2);
  float seed = uSeed * 2.17;
  vec2 seedOff = vec2(seed * 0.41, seed * 1.13);

  // Stronger intensity → deeper warp, punchier contrast, larger drift.
  float freq = mix(1.15, 1.9, clamp(intensity - 0.5, 0.0, 1.5) / 1.5);
  float warpAmt = 1.1 * intensity;
  float curlAmt = 0.12 * intensity;
  float driftAmt = mix(0.28, 0.48, clamp(intensity - 1.0, 0.0, 1.0));

  // Seamless drift — uTime already includes motion speed from the host.
  vec2 drift = vec2(
    sin(uTime * 0.22 + seed) * driftAmt,
    cos(uTime * 0.17 + seed * 0.7) * (driftAmt * 0.85)
  );
  vec2 swirlDrift = vec2(
    cos(uTime * 0.13 + seed * 1.3) * (0.1 * intensity),
    sin(uTime * 0.19 + seed * 0.5) * (0.1 * intensity)
  );
  p += drift * (0.35 * intensity);
  seedOff += drift + swirlDrift;

  vec2 q = vec2(
    fbm(p * (1.35 * freq) + seedOff),
    fbm(p * (1.35 * freq) + seedOff + vec2(3.8, 1.2))
  );
  vec2 r = vec2(
    fbm(p * (1.1 * freq) + 1.6 * q * intensity + vec2(0.9, -2.4) + seedOff * 0.7),
    fbm(p * (1.1 * freq) + 1.6 * q * intensity + vec2(-1.7, 3.1) - seedOff * 0.5)
  );

  float ang = atan(p.y, p.x) + seed * 0.3 + uTime * (0.08 * intensity);
  float rad = length(p);
  vec2 curl = vec2(
    cos(ang * 0.8 + rad * 1.4),
    sin(ang * 0.8 + rad * 1.4)
  ) * curlAmt;

  vec2 field = p * (1.4 * freq) + (r - 0.5) * warpAmt + curl + seedOff * 0.05;

  float blobA = fbm(field * 1.15 + q);
  float blobB = fbm(field.yx * 0.95 + r + vec2(2.1, -1.4));
  float blobC = fbm((field + q - r) * 0.8 + seedOff);

  float t = blobA * 0.5 + blobB * 0.32 + blobC * 0.18;

  float lo = mix(0.28, 0.14, clamp(intensity - 1.0, 0.0, 1.2) / 1.2);
  float hi = mix(0.72, 0.86, clamp(intensity - 1.0, 0.0, 1.2) / 1.2);
  t = smoothstep(lo, hi, t);

  fragColor = blendHsl(uStart, uStop, t);
}
