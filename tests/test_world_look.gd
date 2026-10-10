extends TestCase
## Étalonnage BO1 (WorldLook.grade_color / grade_lut) et post-traitement.

## Étalonnage propre à une carte (surcharge partielle de GRADE_DEFAULT) :
## reprend celui de l'ancien théâtre de KINO (carte retirée).
const WARM_GRADE := {
	"shadow_tint": Color(0.84, 0.98, 1.08),
	"highlight_tint": Color(1.06, 1.0, 0.9),
	"toe": 1.22,
	"desat": 0.16,
}

func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func test_black_is_lifted_but_dense() -> void:
	var g := WorldLook.grade_params()
	var b := WorldLook.grade_color(Color.BLACK, g)
	assert_true(_lum(b) > 0.005 and _lum(b) < 0.04, "noir relevé mais dense (%.3f)" % _lum(b))
	# Noirs bleu-vert (zones éteintes froides), pas rouges.
	assert_true(b.b > b.r and b.g > b.r, "noir froid %s" % b)


func test_mid_tones_not_darker() -> void:
	# « Sombre mais lisible » : les tons moyens ne sont pas assombris.
	var g := WorldLook.grade_params()
	for v in [0.3, 0.45, 0.6]:
		var o := WorldLook.grade_color(Color(v, v, v), g)
		assert_true(_lum(o) >= v * 0.98, "gris %.2f -> %.3f" % [v, _lum(o)])


func test_split_toning() -> void:
	var g := WorldLook.grade_params()
	var dark := WorldLook.grade_color(Color(0.12, 0.12, 0.12), g)
	var light := WorldLook.grade_color(Color(0.85, 0.85, 0.85), g)
	assert_true(dark.g > dark.r and dark.b > dark.r, "ombres vert-de-gris %s" % dark)
	assert_true(light.r > light.b, "hautes lumières chaudes %s" % light)


func test_vivid_colors_desaturated() -> void:
	var g := WorldLook.grade_params()
	var red := Color(0.8, 0.1, 0.1)
	var o := WorldLook.grade_color(red, g)
	assert_true(o.r - o.g < red.r - red.g, "rouge vif délavé %s" % o)
	assert_true(o.r > o.g, "reste rouge %s" % o)


func test_map_override() -> void:
	var g := WorldLook.grade_params(WARM_GRADE)
	assert_eq(g.highlight_tint, WARM_GRADE.highlight_tint)
	assert_eq(g.lift, WorldLook.GRADE_DEFAULT.lift, "clés non surchargées conservées")


func test_lut_is_cached_3d_texture() -> void:
	var a := WorldLook.grade_lut()
	var b := WorldLook.grade_lut({})
	assert_true(a == b, "même table en cache")
	assert_eq(a.get_width(), WorldLook.LUT_SIZE)
	assert_eq(a.get_depth(), WorldLook.LUT_SIZE)
	assert_true(WorldLook.grade_lut(WARM_GRADE) != a, "table propre à la carte")


func test_presets_post_keys() -> void:
	for q in RenderQuality.PRESETS:
		for k in ["volumetric_fog", "fog_volume", "post_screen", "aberration"]:
			assert_true(q.has(k), "%s : clé %s" % [q.name, k])
	var low: Dictionary = RenderQuality.preset(Settings.Quality.LOW)
	assert_false(low.volumetric_fog, "LOW : pas de brume volumétrique")
	assert_false(low.post_screen, "LOW : aucune lecture d'écran")


## Contour noir : créé avec l'environnement de la partie (pas pour l'aperçu
## de l'éditeur), quad plein écran en tête des transparents, affiché selon
## l'option et le moteur de rendu.
func test_outline_pass() -> void:
	var keep := Settings.outline
	var root := Node3D.new()
	host.add_child(root)
	WorldLook.setup_environment(root, {})
	var o := root.get_node_or_null("ScreenOutline") as ScreenOutline
	assert_true(o != null, "passe de contour créée")
	if o:
		assert_eq(o.material.shader, ScreenOutline.SHADER)
		assert_eq(o.material.render_priority, Material.RENDER_PRIORITY_MIN, "avant particules et brume")
		assert_eq(o.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		Settings.outline = true
		Settings.changed.emit()
		assert_eq(o.visible, ScreenOutline.supported(), "option activée : visible si Forward+")
		Settings.outline = false
		Settings.changed.emit()
		assert_false(o.visible, "option désactivée : masquée")
	root.free()
	var editor_root := Node3D.new()
	host.add_child(editor_root)
	WorldLook.setup_environment(editor_root, {}, false)
	assert_true(editor_root.get_node_or_null("ScreenOutline") == null, "aperçu de l'éditeur : pas de contour")
	editor_root.free()
	Settings.outline = keep
	Settings.changed.emit()


func test_grain_setting() -> void:
	var keep := Settings.film_grain
	Settings.film_grain = 0.0
	assert_near(FilmPost.grain_amount(), 0.0)
	Settings.film_grain = 1.0
	assert_near(FilmPost.grain_amount(), FilmPost.GRAIN_MAX)
	Settings.film_grain = 3.0
	assert_near(FilmPost.grain_amount(), FilmPost.GRAIN_MAX, 0.001, "borné")
	Settings.film_grain = keep
