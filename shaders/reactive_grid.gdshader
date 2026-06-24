shader_type canvas_item;
render_mode blend_add, unshaded;
// Reactive vector grid floor (DESIGN_SPEC "Reactive vector grid"). A faint blue
// Geometry-Wars-style grid that scrolls toward the ship and warps under action.
//
// Drawn on ONE full-screen quad (a ColorRect) — a single draw call, the cheap path
// the design's "batching over cleverness" rule allows (the warning is against
// per-instance live geometry, not one shaded quad). Output RGB is HDR (grid_color is
// pushed > 1) and the blend is ADDITIVE, so the lines clear the WorldEnvironment HDR
// bloom threshold and glow — the same path MultiMesh/textured neon uses. (Immediate
// draw_* never blooms; a shaded quad does — see memory glow-immediate-draw-no-bloom.)
//
// NOTE: glow + warp are unproven on this dev box (Intel UHD 630 can't compile Godot's
// glow pipelines under MoltenVK) — must be confirmed on the iPhone (#47/#54).
//
// #16/#17: the single transient ripple is now an ARRAY of up to MAX_RIPPLES=8 that the
// fragment sums, so several kills/breaches in flight ring at once; each slot carries an
// IMPLOSION flag (ripple_implode[i] != 0 → the radial push pulls INWARD, for divide/
// breach) and a recent-action COLOR-SHIFT tints the whole grid toward the gate's hue.

// MUST stay in lockstep with GridFloor.MAX_RIPPLES — the GDScript pushes exactly this
// many slots into the uniform arrays each frame. GLSL ES needs a compile-time size, so
// it lives here as a literal; the comment is the contract.
const int MAX_RIPPLES = 8;

// `resolution` is the ACTUAL covered viewport in px (GridFloor pushes the real
// visible_rect size, NOT the 1080x1920 design rect — #70). UV*resolution therefore spans
// the whole device including the tall 19.5:9 region below 1920, so the grid fills it with
// the SAME cell_size px cells (more rows on a taller screen — density unchanged, no stretch).
uniform vec2 resolution = vec2(1080.0, 1920.0);
uniform float cell_size = 96.0;       // grid cell edge in px
uniform float line_width = 1.6;       // line thickness in px (tighter → crisper HDR glow, #71)
uniform float scroll = 0.0;           // vertical scroll in CELLS (fed from distance)
uniform vec4 grid_color : source_color = vec4(0.3, 0.3, 3.8, 1.0);  // HDR blue
uniform float intensity = 0.35;       // overall line brightness (the "~13% faint" look)

// Depth falloff (#71): the grid reads as a receding floor — lines near the ship line (the
// BOTTOM of the screen, UV.y→1) glow brighter, lines toward the horizon (TOP, UV.y→0) dim
// out. `depth_floor` is the residual brightness at the far top; `depth_gamma` shapes the ramp.
uniform float depth_floor = 0.22;     // brightness multiplier at the far (top) edge
uniform float depth_gamma = 1.6;      // >1 keeps the near band bright, fades the far faster

// Ambient warp (gentle, always-on breathing of the grid). Calmed for #71 — the resting
// state should breathe subtly, not slosh; the reactive ripples (#16/#17) carry the action.
uniform float warp_amp = 4.0;         // px
uniform float warp_speed = 0.7;

// Transient ripple ARRAY, poked by Events.trigger_grid_ripple (radial push from a point).
// A slot is INACTIVE when its ripple_strength is 0; GridFloor zeroes freed slots. Width
// stays a single shared falloff (all rings share the same ring profile — cheaper, and the
// look is identical). The SIGN/flag for implosion is carried out-of-band in ripple_implode
// rather than the strength sign so strength==0 unambiguously means "inactive".
uniform vec2 ripple_center[MAX_RIPPLES];
uniform float ripple_radius[MAX_RIPPLES];    // current ring radius in px (expands over life)
uniform float ripple_strength[MAX_RIPPLES];  // px displacement at the ring (0 == inactive)
uniform float ripple_implode[MAX_RIPPLES];   // 0 = outward push, !=0 = inward PULL (#17)
uniform float ripple_width = 120.0;          // shared ring falloff width in px

// Color-shift by recent action (#17). GridFloor sets shift_color to the last gate's hue
// (Palette.GATE_MULTIPLY/GATE_ADD/GATE_NEGATIVE) and decays shift_amount → 0 over ~0.6s.
uniform vec4 shift_color : source_color = vec4(0.3, 0.3, 3.8, 1.0);  // HDR, blooms like the grid
uniform float shift_amount = 0.0;     // 0 = pure grid_color, 1 = full shift_color

// Music beat pulse (#61). GridFloor arms this to a beat's strength (0..1, bar downbeat = 1)
// on each Events.music_beat and decays it to 0, so the whole grid throbs BRIGHTER (and warps a
// touch more) on the bass — the music-reactive breath. 0 = resting grid, unchanged.
uniform float beat_pulse = 0.0;
uniform float beat_brightness = 0.6;  // extra line brightness at a full-strength beat (×)
uniform float beat_warp = 0.3;        // extra warp swell at a full-strength beat (× the warp)

// Distance (px) from coordinate `c` (in cells) to the nearest integer grid line,
// expressed back in px, turned into a soft line mask.
float line_mask(float c) {
	float f = fract(c);
	float d = min(f, 1.0 - f) * cell_size;     // px to nearest line
	return 1.0 - smoothstep(0.0, line_width, d);
}

void fragment() {
	vec2 px = UV * resolution;

	// Ambient sinusoidal warp — gentle, low-frequency breathing (calmed for #71). Lower
	// spatial frequency + amplitude reads as a slow swell rather than a busy ripple.
	float t = TIME * warp_speed;
	// A music beat swells the ambient warp a touch (#61) so the grid breathes outward on the bass.
	vec2 warp = vec2(sin(px.y * 0.006 + t * 1.3), sin(px.x * 0.006 + t * 1.1))
		* warp_amp * (1.0 + beat_pulse * beat_warp);

	// Transient radial ripples — SUM every active slot's displacement around its impact
	// point. An inactive slot (strength 0) contributes nothing (ring scales by strength),
	// so the loop is branch-free. ripple_implode flips the push to a PULL (toward centre).
	for (int i = 0; i < MAX_RIPPLES; i++) {
		vec2 dvec = px - ripple_center[i];
		float dist = length(dvec) + 0.0001;
		float ring = ripple_strength[i] * exp(-pow((dist - ripple_radius[i]) / max(ripple_width, 1.0), 2.0));
		float dir = (ripple_implode[i] != 0.0) ? -1.0 : 1.0;   // implosion pulls inward
		warp += (dvec / dist) * ring * dir;
	}

	vec2 p = px + warp;
	float gx = p.x / cell_size;
	float gy = p.y / cell_size + scroll;       // GridFloor feeds NEGATIVE scroll on forward travel so lines flow TOP->BOTTOM toward the ship

	float line = max(line_mask(gx), line_mask(gy));

	// Depth falloff (#71): brighten the near band (bottom, by the ship), fade toward the
	// horizon (top). Driven by the STABLE screen UV.y — not the warped coord — so the ramp
	// stays a steady vertical gradient regardless of warp/ripple. UV.y=0 is the far top.
	float depth = mix(depth_floor, 1.0, pow(clamp(UV.y, 0.0, 1.0), depth_gamma));

	// Color-shift: lerp the grid hue toward the recent action's colour (still HDR → blooms).
	vec3 col = mix(grid_color.rgb, shift_color.rgb, clamp(shift_amount, 0.0, 1.0));
	// Music beat brightens the whole grid (#61) — a global throb on the bass that blooms harder.
	float beat = 1.0 + clamp(beat_pulse, 0.0, 1.0) * beat_brightness;
	COLOR = vec4(col, line * intensity * depth * beat);
}
