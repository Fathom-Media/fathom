#version 460 core
#include <flutter/runtime_effect.glsl>

// A light, organic caustic drawn as an additive overlay so underwater light
// appears to play over the content beneath it, without distorting it. The
// domain is warped so the light veins meander instead of forming a regular
// grid (which reads as fake). Meant to fill the whole window; a soft radial
// pool concentrates the light on the center and fades it out before any edge,
// so there's no visible boundary. Driven by uTime (seconds) from Dart.
uniform vec2 uSize;   // paint area in logical pixels
uniform float uTime;  // elapsed seconds

out vec4 fragColor;

void main() {
  vec2 fc = FlutterFragCoord().xy;
  float t = uTime;

  // Pixel-based domain so the vein scale stays constant at any window size.
  vec2 p = fc / 95.0;
  p += 0.35 * vec2(sin(p.y * 1.7 + t * 0.6), cos(p.x * 1.9 - t * 0.5));

  // Sum of non-harmonic sines, folded into thin bright ridges where the waves
  // cross zero, the way real caustics focus light into wavering veins.
  float c = sin(p.x * 3.1 + t * 1.0)
          + sin(p.y * 3.7 - t * 0.8)
          + sin((p.x + p.y) * 2.3 + t * 1.2)
          + sin((p.x - p.y) * 2.9 - t * 0.9);
  c *= 0.25; // ~ -1..1
  float veins = pow(1.0 - abs(c), 4.0);

  // A slower, broader layer so it reads as depth, not one flat sheet.
  float c2 = sin(p.x * 1.6 - t * 0.7) + sin(p.y * 1.9 + t * 0.6);
  veins += 0.35 * pow(max(0.0, 1.0 - abs(c2 * 0.5)), 3.0);

  // Soft radial pool centered in the window, fading out well before the edges.
  float d = distance(fc, uSize * 0.5);
  float fall = smoothstep(340.0, 40.0, d);

  float a = clamp(veins, 0.0, 1.0) * fall * 0.13; // deliberately faint
  vec3 tint = vec3(0.82, 0.95, 1.0); // pale aqua
  fragColor = vec4(tint * a, a); // premultiplied, added via BlendMode.plus
}
