extends TestCase
## Style ILLUSTRÉ (IllustratedStyle, prototype) : variantes de shader
## générées, inscription et changement de style des matériaux, passe de
## trait (ScreenOutline) et préréglages de qualité (encrage intérieur).

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


func test_variant_code_adds_kind_and_cel_light() -> void:
	var base := "shader_type spatial;\nrender_mode cull_back;\nvoid fragment() {\n\tALBEDO = vec3(1.0);\n}\n"
	var archi := IllustratedStyle.variant_code(base, IllustratedStyle.Kind.ARCHI)
	assert_true(archi.begins_with("shader_type spatial;"), "shader_type en tête")
	assert_true(archi.contains("#define STYLE_CEL") and archi.contains("#define CEL_ARCHI"), "sorte définie")
	assert_true(archi.strip_edges().ends_with("#include \"%s\"" % IllustratedStyle.CEL_INCLUDE), "light() ajoutée à la fin")
	assert_false(archi.contains("stencil_mode"), "architecture : pas de marque de stencil")
	var chr := IllustratedStyle.variant_code(base, IllustratedStyle.Kind.CHAR)
	assert_true(chr.contains("#define CEL_CHAR"))
	assert_true(chr.contains("stencil_mode write, compare_always, %d;" % IllustratedStyle.STENCIL_OBJECT), "objets marqués")
	assert_eq(IllustratedStyle.variant_code("// pas un shader spatial", 0), "// pas un shader spatial")


func test_variants_cached_per_shader_and_kind() -> void:
	var sh := preload("res://assets/shaders/voxel_prop.gdshader")
	var a := IllustratedStyle.variant(sh, IllustratedStyle.Kind.PROP)
	assert_true(a == IllustratedStyle.variant(sh, IllustratedStyle.Kind.PROP), "même variante")
	assert_true(a != IllustratedStyle.variant(sh, IllustratedStyle.Kind.CHAR), "une variante par sorte")
	assert_false(sh.code.contains("cel_light"), "shader d'origine intact")


## Les variantes des shaders du jeu se compilent (aucune erreur du
## préprocesseur ni du langage) : leurs paramètres sont listés.
func test_game_variants_compile() -> void:
	for path in IllustratedStyle.KIND_BY_SHADER:
		var sh := load(path) as Shader
		var v := IllustratedStyle.variant(sh, IllustratedStyle.KIND_BY_SHADER[path])
		assert_true(v.get_shader_uniform_list().size() >= sh.get_shader_uniform_list().size(),
				"%s : variante compilée, paramètres gardés" % path)


func test_bind_follows_style() -> void:
	var sh := preload("res://assets/shaders/voxel_prop.gdshader")
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("glow_energy", 2.0)
	Settings.art_style = Settings.ArtStyle.CLASSIC
	Settings.changed.emit()
	IllustratedStyle.bind(m)
	assert_eq(m.get_meta("style_kind"), IllustratedStyle.Kind.PROP, "sorte déduite du shader")
	assert_true(m.shader == sh, "CLASSIQUE : shader d'origine")
	Settings.art_style = Settings.ArtStyle.ILLUSTRATED
	Settings.changed.emit()
	assert_true(m.shader == IllustratedStyle.variant(sh, IllustratedStyle.Kind.PROP), "ILLUSTRÉ : variante")
	assert_eq(m.get_shader_parameter("glow_energy"), 2.0, "paramètre gardé")
	assert_true(IllustratedStyle.base_shader(m) == sh)
	# Copie d'un matériau inscrit (matériaux d'équipe des mains) : inscrite à son tour.
	var dup := m.duplicate() as ShaderMaterial
	IllustratedStyle.bind(dup)
	Settings.art_style = Settings.ArtStyle.CLASSIC
	Settings.changed.emit()
	assert_true(m.shader == sh and dup.shader == sh, "retour en CLASSIQUE (copie comprise)")


func test_debug_force_overrides_setting() -> void:
	Settings.art_style = Settings.ArtStyle.CLASSIC
	IllustratedStyle.debug_force = Settings.ArtStyle.ILLUSTRATED
	assert_true(IllustratedStyle.active())
	IllustratedStyle.debug_force = -1
	assert_false(IllustratedStyle.active())


## Préréglages : chaque qualité dit si l'encrage trace les arêtes
## intérieures ; la passe de trait suit le style et le préréglage.
func test_outline_follows_style_and_preset() -> void:
	for q in RenderQuality.PRESETS:
		assert_true(q.has("ink_inner") and q.ink_inner is bool, "%s : ink_inner" % q.name)
	assert_true(RenderQuality.preset(Settings.Quality.HIGH).ink_inner, "HAUTE : arêtes intérieures")
	assert_true(RenderQuality.preset(Settings.Quality.MEDIUM).ink_inner, "MOYENNE : arêtes intérieures")
	if not ScreenOutline.supported():
		return  # tests sans rendu : pas de pré-passe de profondeur
	var root := Node3D.new()
	Engine.get_main_loop().root.add_child(root)
	var o := ScreenOutline.new()
	root.add_child(o)
	await wait_frames(1)
	assert_true(o.key_light != null and o.key_light.get_parent() == root, "lumière de modelé sœur du contour")
	Settings.art_style = Settings.ArtStyle.CLASSIC
	Settings.changed.emit()
	assert_true(o.material.shader == ScreenOutline.SHADER and o.material.next_pass == null, "CLASSIQUE : contour seul")
	assert_false(o.key_light.visible, "CLASSIQUE : pas de lumière de modelé")
	Settings.art_style = Settings.ArtStyle.ILLUSTRATED
	for qi in Settings.Quality.size():
		Settings.quality = qi as Settings.Quality
		Settings.changed.emit()
		var want := 1.0 if RenderQuality.preset(qi).ink_inner else 0.0
		assert_eq(o.material.get_shader_parameter("inner"), want, "qualité %d : arêtes intérieures" % qi)
		assert_eq(o.ink_objects.get_shader_parameter("inner"), want)
	assert_true(o.material.shader == ScreenOutline.ink_shader(false), "ILLUSTRÉ : encrage de l'architecture")
	assert_true(o.material.next_pass == o.ink_objects and o.ink_objects.shader == ScreenOutline.ink_shader(true), "puis des objets")
	assert_true(o.key_light.visible, "ILLUSTRÉ : lumière de modelé")
	root.queue_free()
	await wait_frames(1)
