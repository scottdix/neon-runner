extends Node
## Sprite Atlas (#36) — an AtlasTexture region map that packs the small projectile / effect / gate
## sprites onto ONE shared source texture so they draw from a single texture binding (fewer texture
## swaps → fewer draw calls when many sprites share the page). This file owns the PURE region map
## (name → Rect2) and the atlas-build math; handing out an AtlasTexture per region is the only
## engine-touching step and is built lazily from a source texture the EffectLayer supplies.
##
## The REAL draw-call reduction is device-only (the Intel UHD 630 here can't profile it), so the
## headless surface is the LOGIC: the region layout packs without overlap inside the page, and a
## name→region lookup round-trips exactly. Everything the verify reads is PURE + STATIC.
##
## DESIGN / GOTCHA notes:
##   - Regions are laid out in a fixed grid on a power-of-two page so the packing is deterministic
##     and the verify can assert exact Rect2s. CELL is small (mobile particle/gate sprites are tiny).
##   - This never replaces the EffectLayer's runtime emitters — it's the static atlas a sprite-based
##     draw path (gate glyphs, projectile dots) would pull from. Pure region defs mean no GPU here.

# The named sprites packed onto the page, in row-major order. Adding one here re-derives its region
# deterministically (region_for / build_regions), so the verify stays a layout round-trip.
const SPRITES := [
	"projectile_orb",   # the fleet bullet dot
	"projectile_lance", # LANCE-tier elongated shot
	"effect_spark",     # small kill spark
	"effect_ring",      # collect ring
	"gate_add",         # gate "+" glyph
	"gate_multiply",    # gate "×" glyph
	"gate_subtract",    # gate "−" glyph
	"gate_divide",      # gate "÷" glyph
	"token_chip",       # economy token (#78) chip sprite
]

# Grid geometry. CELL is the per-sprite cell (px); COLS sets the page width; the page height grows
# in whole CELL rows to fit SPRITES. Power-of-two-friendly (64px cells, 4 cols → 256px wide).
const CELL := 64
const COLS := 4


## PURE: the grid (col, row) for the i-th sprite, row-major. Foundation the region math builds on.
static func cell_of(index: int) -> Vector2i:
	return Vector2i(index % COLS, index / COLS)


## PURE: the pixel Rect2 region for the i-th sprite on the page. Deterministic packing — no overlap
## because each index maps to a distinct grid cell. The verify asserts exact rects + non-overlap.
static func region_at(index: int) -> Rect2:
	var c: Vector2i = cell_of(index)
	return Rect2(float(c.x * CELL), float(c.y * CELL), float(CELL), float(CELL))


## PURE: the region for a NAMED sprite (the lookup the draw path uses). Returns a zero-size Rect2
## for an unknown name so a caller can detect the miss without an out-of-range crash.
static func region_for(sprite_name: String) -> Rect2:
	var idx: int = SPRITES.find(sprite_name)
	if idx < 0:
		return Rect2(0, 0, 0, 0)
	return region_at(idx)


## PURE: the full {name: Rect2} map — the whole packed layout in one call. The verify round-trips
## this against region_for and checks no two regions overlap.
static func build_regions() -> Dictionary:
	var out := {}
	for i in SPRITES.size():
		out[SPRITES[i]] = region_at(i)
	return out


## PURE: the page size (px) needed to hold every sprite — COLS wide, ceil(count/COLS) rows tall.
static func page_size() -> Vector2i:
	var rows: int = int(ceil(float(SPRITES.size()) / float(COLS)))
	return Vector2i(COLS * CELL, maxi(rows, 1) * CELL)


## PURE: does a region for the named sprite exist on the page?
static func has_sprite(sprite_name: String) -> bool:
	return SPRITES.has(sprite_name)


# --- Engine-touching: hand out an AtlasTexture (lazy; not exercised headless) --

## Build an AtlasTexture for a named sprite, backed by `source` (the packed page texture the
## EffectLayer supplies). Returns null for an unknown name. The PURE region_for owns the rect;
## this only wraps it in the engine type, so headless tests never need a real texture.
static func atlas_for(source: Texture2D, sprite_name: String) -> AtlasTexture:
	if source == null or not has_sprite(sprite_name):
		return null
	var at := AtlasTexture.new()
	at.atlas = source
	at.region = region_for(sprite_name)
	return at
