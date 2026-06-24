extends Node
## Particle Budget (#37) — a PURE policy/caps helper the effect layer reads to keep the particle
## load mobile-safe. It owns no GPU resources and emits nothing; it just answers questions the
## EffectLayer asks before it fires a burst:
##   • which emitter KIND to use for a burst of N particles (GPUParticles2D for a big >50 burst,
##     cheap CPU points for a tiny <20 puff, GPU for the middle by default),
##   • how many particles a burst is ALLOWED given the live total (cap the swarm at <1000 visible),
##   • whether a request fits the texture-size budget (<=64px) and uses additive blending.
##
## All logic is PURE + STATIC so the verify asserts the selection + caps with no renderer. The
## EffectLayer keeps the actual GPUParticles2D pool; this is only the decision layer, so it can't
## regress gameplay (it never touches run state).
##
## Thresholds (mobile budget, DESIGN_SPEC perf pass):
##   • USE GPUParticles2D for a burst > GPU_MIN_COUNT (50) — batched, cheap at scale.
##   • USE cheap CPU points for a burst < CPU_MAX_COUNT (20) — too few to be worth a GPU emitter.
##   • Between [20, 50] default to GPU (the bursts read as one punch; GPU keeps the draw-call count
##     flat). The band edges are exclusive on the GPU/CPU sides so the policy is unambiguous.
##   • Hard cap TOTAL_VISIBLE_CAP (1000) particles alive across all emitters; a request that would
##     exceed it is clamped to the remaining headroom (never negative).
##   • Particle textures must be <= MAX_TEX_PX (64) on a side and use ADDITIVE blending (so they
##     feed the bloom and overlap white-hot — the only path that glows).

# Emitter selection thresholds.
const GPU_MIN_COUNT := 50      # burst strictly ABOVE this → GPUParticles2D
const CPU_MAX_COUNT := 20      # burst strictly BELOW this → cheap CPU points

# Visible-particle hard cap across ALL live emitters (mobile budget).
const TOTAL_VISIBLE_CAP := 1000

# Particle sprite size cap (a side, px) — small textures keep VRAM/fill cheap on mobile GPUs.
const MAX_TEX_PX := 64

# Emitter kinds the policy hands back (strings so the verify reads them with no enum import).
const KIND_GPU := "gpu"        # GPUParticles2D — batched burst
const KIND_CPU := "cpu"        # cheap CPU-side points — tiny puff


## Pick the emitter KIND for a burst of `count` particles. PURE:
##   count >  GPU_MIN_COUNT → KIND_GPU
##   count <  CPU_MAX_COUNT → KIND_CPU
##   otherwise (the 20..50 band) → KIND_GPU (default to batched).
static func select_kind(count: int) -> String:
	if count > GPU_MIN_COUNT:
		return KIND_GPU
	if count < CPU_MAX_COUNT:
		return KIND_CPU
	return KIND_GPU


## Clamp a requested particle count to the remaining headroom under TOTAL_VISIBLE_CAP, given how
## many are already alive. Never returns negative; never lets the total exceed the cap. PURE.
##   live=950, request=100 → 50 (fills to the cap)
##   live=1000, request=40 → 0  (no headroom)
static func grant(live_count: int, request: int) -> int:
	var headroom: int = TOTAL_VISIBLE_CAP - maxi(live_count, 0)
	if headroom <= 0:
		return 0
	return clampi(request, 0, headroom)


## Would emitting `request` more particles exceed the visible cap given `live_count` already alive?
## PURE convenience for the EffectLayer / verify.
static func would_exceed_cap(live_count: int, request: int) -> bool:
	return maxi(live_count, 0) + maxi(request, 0) > TOTAL_VISIBLE_CAP


## Does a texture of `px` on a side fit the budget? PURE — the EffectLayer asserts its shared
## particle texture against this so an oversized sprite can't sneak in.
static func texture_ok(px: int) -> bool:
	return px > 0 and px <= MAX_TEX_PX


## Is a blend mode acceptable for a neon particle? Only ADD glows (the immediate/mix path never
## feeds the bloom), so the budget mandates additive. Takes the CanvasItemMaterial.BlendMode int.
static func blend_ok(blend_mode: int) -> bool:
	return blend_mode == CanvasItemMaterial.BLEND_MODE_ADD


## One-call policy for a burst request: returns the full plan as a Dict the EffectLayer can act on.
## PURE — composes select_kind + grant so a caller gets {kind, granted, capped} in one hop.
##   { "kind": String, "granted": int, "capped": bool }
static func plan(count: int, live_count: int) -> Dictionary:
	var granted: int = grant(live_count, count)
	return {
		"kind": select_kind(count),
		"granted": granted,
		"capped": granted < count,
	}
