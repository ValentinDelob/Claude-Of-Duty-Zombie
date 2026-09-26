extends TestCase
## Préréglages de qualité graphique (RenderQuality).

const KEYS := ["name", "lamp_shadows", "shadow_atlas", "shadow_filter", "light_fade_begin",
	"light_fade_length", "shadow_fade", "glow", "glow_bicubic", "ssao", "scale_3d", "msaa",
	"decal_fade", "decals", "particles"]


func test_one_preset_per_settings_quality() -> void:
	assert_eq(RenderQuality.PRESETS.size(), Settings.Quality.size())
	assert_eq(RenderQuality.preset(Settings.Quality.LOW).name, "low")
	assert_eq(RenderQuality.preset(Settings.Quality.MEDIUM).name, "medium")
	assert_eq(RenderQuality.preset(Settings.Quality.HIGH).name, "high")
	for q in RenderQuality.PRESETS:
		for k in KEYS:
			assert_true(q.has(k), "%s : clé %s" % [q.name, k])


func test_parse_names() -> void:
	assert_eq(RenderQuality.parse("LOW"), Settings.Quality.LOW)
	assert_eq(RenderQuality.parse("high"), Settings.Quality.HIGH)
	assert_eq(RenderQuality.parse("ultra"), -1)


func test_presets_are_ordered_by_cost() -> void:
	var low: Dictionary = RenderQuality.preset(Settings.Quality.LOW)
	var med: Dictionary = RenderQuality.preset(Settings.Quality.MEDIUM)
	var high: Dictionary = RenderQuality.preset(Settings.Quality.HIGH)
	assert_true(low.lamp_shadows <= med.lamp_shadows and med.lamp_shadows <= high.lamp_shadows, "ombres")
	assert_true(low.light_fade_begin <= med.light_fade_begin and med.light_fade_begin <= high.light_fade_begin, "fondu")
	assert_true(low.scale_3d <= med.scale_3d and med.scale_3d <= high.scale_3d, "résolution 3D")
	assert_true(low.particles <= med.particles, "particules")
	assert_eq(low.lamp_shadows, 0, "LOW : aucune ombre de lampe")


func test_lamp_shadow_selection() -> void:
	var counts := []
	for q in RenderQuality.PRESETS:
		var n := 0
		for i in 24:
			if RenderQuality.lamp_has_shadow(i, q):
				n += 1
		counts.append(n)
	assert_eq(counts, [0, 8, 16])
	# Les lampes à ombre de MEDIUM gardent leur ombre en HIGH (même ambiance).
	for i in 24:
		if RenderQuality.lamp_has_shadow(i, RenderQuality.preset(Settings.Quality.MEDIUM)):
			assert_true(RenderQuality.lamp_has_shadow(i, RenderQuality.preset(Settings.Quality.HIGH)), "lampe %d" % i)
