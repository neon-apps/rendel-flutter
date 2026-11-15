// The light on the panel's glass (design/plans/sdk-look-a.md §1.1).
//
// Painted over the frosted backdrop as an ordinary paint shader, so every
// coordinate here is the glass's own: it stays right while the glass slides,
// fades, grows or scrolls. Lighting idea after liquid_glass_renderer
// (MIT, Tim Lehmann for whynotmake.it); the code is our own.
#version 460 core
precision mediump float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;     // the glass, in logical pixels
uniform float uRadius;  // its corner radius
uniform float uLight;   // 0..1, how bright the rim is

out vec4 fragColor;

// Signed distance to a rounded rectangle centred at the origin: negative inside.
float sdRoundRect(vec2 p, vec2 hs, float r) {
  vec2 q = abs(p) - hs + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
  vec2 p = FlutterFragCoord().xy - uSize * 0.5;
  vec2 hs = uSize * 0.5;
  float r = min(uRadius, min(hs.x, hs.y));
  float d = sdRoundRect(p, hs, r);
  if (d > 0.5) {
    fragColor = vec4(0.0);
    return;
  }
  float inside = -d;

  // The outward normal, from the distance field's slope.
  vec2 e = vec2(0.5, 0.0);
  vec2 n = normalize(vec2(
    sdRoundRect(p + e.xy, hs, r) - sdRoundRect(p - e.xy, hs, r),
    sdRoundRect(p + e.yx, hs, r) - sdRoundRect(p - e.yx, hs, r)) + 1e-5);

  // Light from above and a little to the left; its reflection, weaker, from
  // the opposite side, as on Apple's glass.
  vec2 light = normalize(vec2(-0.45, -1.0));
  float facing = max(dot(n, light), 0.0);
  float back = max(dot(n, -light), 0.0);
  float direction = 0.35 + 0.65 * pow(facing, 1.2) + 0.45 * pow(back, 1.5);

  // A thin bright line just inside the edge, and a soft glow under it.
  float rim = exp(-inside / 0.9);
  float glow = exp(-inside / 7.0);
  float a = clamp(uLight * (rim * 0.85 * direction + glow * 0.10 * direction), 0.0, 1.0);

  // Anti-aliased at the very edge.
  a *= clamp(0.5 - d, 0.0, 1.0);
  fragColor = vec4(vec3(a), a);
}
