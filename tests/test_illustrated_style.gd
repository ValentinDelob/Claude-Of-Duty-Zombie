extends TestCase
## Style ILLUSTRÉ (IllustratedStyle / IllustratedPost, prototype) :
## post-traitement plein écran seul, rayon du filtre de Kuwahara par
## préréglage, tables d'étalonnage mesurées sur la planche cible.

const GRADE_PATH := "res://assets/shaders/illustrated_grade.gdshader"
const TARGET := "res://docs/art/gemini_target.webp"

var _keep_style: int
var _keep_quality: int


func before_each() -> void:
	_keep_style = Settings.art_style
	_keep_quality = Settings.quality
	IllustratedStyle.debug_force = -1


func after_each() -> void:
	Settings.art_style = _keep_style as Settings.ArtStyle
	Settings.quality = _keep_quality as Settings.Quality
	IllustratedStyle.debug_force = -1
	Settings.changed.emit()


func test_active_follows_setting_and_debug_force() -> void:
	Settings.art_style = Settings.ArtStyle.CLASSIC
	assert_false(IllustratedStyle.active())
	Settings.art_style = Settings.ArtStyle.ILLUSTRATED
	assert_true(IllustratedStyle.active())
	IllustratedStyle.debug_force = Settings.ArtStyle.CLASSIC
	assert_false(IllustratedStyle.active(), "forçage des tests")


## Préréglages : rayon du filtre (0 en BASSE : passe coupée), croissant.
func test_kuwahara_radius_per_preset() -> void:
	var r := []
	for q in RenderQuality.PRESETS:
		assert_true(q.has("illustrated_radius"), "%s : illustrated_radius" % q.name)
		r.append(IllustratedPost.radius_for(q))
	assert_eq(r[Settings.Quality.LOW], 0.0, "BASSE : pas de filtre de Kuwahara")
	assert_true(r[Settings.Quality.MEDIUM] > 0.0 and r[Settings.Quality.HIGH] >= r[Settings.Quality.MEDIUM], "MOYENNE <= HAUTE")


func test_post_follows_style_and_preset() -> void:
	var root := Node3D.new()
	Engine.get_main_loop().root.add_child(root)
	var film := FilmPost.new()
	root.add_child(film)
	var o := ScreenOutline.new()
	root.add_child(o)
	await wait_frames(2)
	var post := root.get_node_or_null("IllustratedPost") as IllustratedPost
	assert_true(post != null, "post-traitement voisin du contour")
	if post == null:
		root.queue_free()
		return
	assert_eq(post.layer, IllustratedPost.GAME_LAYER, "en partie : sous le grain de film")
	assert_true(post.layer < FilmPost.LAYER)
	Settings.art_style = Settings.ArtStyle.CLASSIC
	Settings.changed.emit()
	assert_false(post.visible, "CLASSIQUE : masqué")
	assert_true(o.material.shader == ScreenOutline.SHADER, "contour noir d'origine")
	Settings.art_style = Settings.ArtStyle.ILLUSTRATED
	for qi in Settings.Quality.size():
		Settings.quality = qi as Settings.Quality
		Settings.changed.emit()
		var r := IllustratedPost.radius_for(RenderQuality.preset(qi))
		assert_eq(post.kuwahara.get_shader_parameter("radius"), r, "qualité %d : rayon" % qi)
		assert_eq(post._kuwahara_rect.visible, r > 0.0, "qualité %d : passe de Kuwahara" % qi)
	assert_true(post.visible, "ILLUSTRÉ : affiché")
	assert_true(o.material.shader == ScreenOutline.SHADER, "ILLUSTRÉ : contour noir inchangé")
	root.queue_free()
	await wait_frames(1)
	# Sans grain de film voisin (fond du menu) : sous l'interface.
	var menu_root := Node3D.new()
	Engine.get_main_loop().root.add_child(menu_root)
	var o2 := ScreenOutline.new()
	menu_root.add_child(o2)
	await wait_frames(2)
	var post2 := menu_root.get_node_or_null("IllustratedPost") as IllustratedPost
	assert_true(post2 != null and post2.layer == IllustratedPost.MENU_LAYER, "menu : couche sous l'interface")
	menu_root.queue_free()
	await wait_frames(1)


## La carte de couleurs de illustrated_grade.gdshader est bien la couleur
## moyenne de la planche cible par tranche de luminance (recalculée ici).
func test_grade_map_measured_on_target() -> void:
	if not FileAccess.file_exists(TARGET):
		return
	var img := Image.load_from_file(ProjectSettings.globalize_path(TARGET))
	img.convert(Image.FORMAT_RGBF)
	var acc := []
	var cnt := []
	for i in 12:
		acc.append(Vector3.ZERO)
		cnt.append(0)
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			var b := clampi(int((0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * 12.0), 0, 11)
			acc[b] += Vector3(c.r, c.g, c.b)
			cnt[b] += 1
	var code := FileAccess.get_file_as_string(GRADE_PATH)
	var re := RegEx.create_from_string("vec3\\(([0-9.]+), ([0-9.]+), ([0-9.]+)\\)")
	var table := code.substr(code.find("TARGET_MAP[12]"))
	var found := re.search_all(table)
	assert_true(found.size() >= 12, "12 couleurs dans la table")
	for i in mini(12, found.size()):
		if cnt[i] < 100:
			continue
		var m: Vector3 = acc[i] / float(cnt[i])
		var t := Vector3(float(found[i].get_string(1)), float(found[i].get_string(2)), float(found[i].get_string(3)))
		assert_true(m.distance_to(t) < 0.03, "tranche %d : %s mesuré, %s dans le shader" % [i, m, t])
