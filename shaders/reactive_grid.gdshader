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

uniform vec2 resolution = vec2(1080.0, 1920.0);
uniform float cell_size = 96.0;       // grid cell edge in px
uniform float line_width = 2.5;       // line thickness in px
uniform float scroll = 0.0;           // vertical scroll in CELLS (fed from distance)
uniform vec4 grid_color : source_color = vec4(0.3, 0.3, 3.8, 1.0);  // HDR blue
uniform float intensity = 0.35;       // overall line brightness (the "~13% faint" look)

// Ambient warp (gentle, always-on breathing of the grid).
uniform float warp_amp = 7.0;         // px
uniform float warp_speed = 1.0;

// Transient ripple, poked by Events.trigger_grid_ripple (radial push from a point).
uniform vec2 ripple_center = vec2(540.0, 1680.0);
uniform float ripple_radius = 0.0;    // current ring radius in px (expands over its life)
uniform float ripple_strength = 0.0;  // px displacement at the ring (decays to 0)
uniform float ripple_width = 120.0;   // ring falloff width in px

// Distance (px) from coordinate `c` (in cells) to the nearest integer grid line,
// expressed back in px, turned into a soft line mask.
float line_mask(float c) {
	float f = fract(c);
	float d = min(f, 1.0 - f) * cell_size;     // px to nearest line
	return 1.0 - smoothstep(0.0, line_width, d);
}

void fragment() {
	vec2 px = UV * resolution;

	// Ambient sinusoidal warp.
	float t = TIME * warp_speed;
	vec2 warp = vec2(sin(px.y * 0.012 + t * 1.3), sin(px.x * 0.012 + t * 1.1)) * warp_amp;

	// Transient radial ripple displacement around the impact point.
	vec2 dvec = px - ripple_center;
	float dist = length(dvec) + 0.0001;
	float ring = ripple_strength * exp(-pow((dist - ripple_radius) / max(ripple_width, 1.0), 2.0));
	warp += (dvec / dist) * ring;

	vec2 p = px + warp;
	float gx = p.x / cell_size;
	float gy = p.y / cell_size + scroll;       // scroll moves lines downward toward the ship

	float line = max(line_mask(gx), line_mask(gy));
	COLOR = vec4(grid_color.rgb, line * intensity);
}
