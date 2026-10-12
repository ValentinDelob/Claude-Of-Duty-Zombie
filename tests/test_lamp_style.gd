extends TestCase
## Rendu des lampes des cartes (LampStyle, LampPool, RenderQuality.apply_lamp)
## et réglages d'ambiance par préréglage (docs/ART_DIRECTION.md « Lumière et
## ambiance »).


func test_style_by_fixture() -> void:
	# Lampe automatique / de BUNKER K-7 : sous abat-jour, flaque vers le bas.
	assert_true(LampStyle.has_pool(LampStyle.of("")), "lampe de plafond : flaque")
	# Tout luminaire de plafond de l'éditeur en a une.
	for id in MapCatalog.LIGHTS:
		var d: Dictionary = MapCatalog.LIGHTS[id]
		if String(d.mount) == "plafond":
			assert_true(LampStyle.has_pool(LampStyle.of(id)), "%s (plafond) : flaque" % id)
	assert_true(LampStyle.has_pool(LampStyle.of("lampe_bureau")), "lampe de bureau : flaque")
	# Sans abat-jour : une seule lumière omnidirectionnelle.
	for id in ["applique", "bougies", "feu", "projecteur"]:
		assert_false(LampStyle.has_pool(LampStyle.of(id)), "%s : omni seule" % id)
	assert_false(LampStyle.has_pool(LampStyle.of("inconnu")), "type inconnu : omni seule")


func test_pool_carries_most_light() -> void:
	for id in ["", "neon", "lustre", "lampe_bureau"]:
		var s := LampStyle.of(id)
		assert_true(float(s.pool) > float(s.fill), "%s : la flaque éclaire plus que la lueur" % id)
		assert_true(float(s.fill) < 1.0 and float(s.angle) < 89.0, "%s : réglages bornés" % id)


## add_lamp : lueur faible + flaque (LampPool) qui recopie la lampe et porte
## l'ombre ; une applique reste une lumière seule.
func test_add_lamp_builds_pool() -> void:
	var parent := Node3D.new()
	host.add_child(parent)
	var props := MapProps.new()
	props._make_root(parent)
	var lamp := props.add_lamp(Vector3(0, 2.5, 0), 2.0, 10.0, false)
	var pool := lamp.get_node_or_null("Pool") as LampPool
	assert_true(pool != null, "lampe de plafond : flaque créée")
	var s := LampStyle.of("")
	assert_near(lamp.light_energy, 2.0 * float(s.fill), 0.001, "lueur de la lampe")
	pool.sync()
	assert_near(pool.light_energy, 2.0 * float(s.pool), 0.001, "énergie de la flaque")
	assert_true(pool.global_basis.z.normalized().is_equal_approx(Vector3.UP), "flaque dirigée vers le bas (-Z local = -Y)")
	# Courant coupé / grésillement : la flaque suit la lampe.
	lamp.light_energy = 0.0
	lamp.light_color = Color.RED
	pool.sync()
	assert_near(pool.light_energy, 0.0, 0.0001, "lampe éteinte : flaque éteinte")
	assert_eq(pool.light_color, Color.RED, "couleur recopiée")
	# Ombre : sur la flaque seulement (lampe d'index 0 : ombrée en MEDIUM).
	var med := RenderQuality.preset(Settings.Quality.MEDIUM)
	RenderQuality.apply_lamp(lamp, med)
	assert_true(pool.shadow_enabled and not lamp.shadow_enabled, "MEDIUM : ombre portée par la flaque")
	assert_true(RenderQuality.lamp_casts_shadow(lamp), "lamp_casts_shadow")
	RenderQuality.apply_lamp(lamp, RenderQuality.preset(Settings.Quality.LOW))
	assert_false(RenderQuality.lamp_casts_shadow(lamp), "LOW : aucune ombre")
	assert_true(pool.distance_fade_enabled, "fondu de la flaque")
	var wall := props.add_lamp(Vector3(3, 2, 0), 1.4, 7.0, false, PowerGrid.ON_COLOR, true, "applique")
	assert_true(wall.get_node_or_null("Pool") == null, "applique : pas de flaque")
	assert_near(wall.light_energy, 1.4, 0.001, "applique : énergie entière")
	parent.queue_free()


func test_quality_ambience_scaling() -> void:
	var low := RenderQuality.preset(Settings.Quality.LOW)
	var med := RenderQuality.preset(Settings.Quality.MEDIUM)
	var high := RenderQuality.preset(Settings.Quality.HIGH)
	assert_false(low.ssao or low.ssr or low.volumetric_fog, "LOW : ni SSAO, ni SSR, ni brume")
	assert_true(med.volumetric_fog and not med.ssao and not med.ssr, "MEDIUM : brume, sans SSAO ni SSR (GTX 1050)")
	assert_true(high.ssao and high.ssr and high.volumetric_fog, "HIGH : tout")


## Sols mouillés : seules des clés de sol connues, intensités 0..1.
func test_wet_surfaces() -> void:
	for key in WorldLook.WET_SURFACES:
		assert_true(PixelSurfaces.has(key), "%s : surface connue" % key)
		assert_eq(WorldLook.SURFACES.get(key, "sol"), "sol", "%s : un sol" % key)
		var w := float(WorldLook.WET_SURFACES[key])
		assert_true(w > 0.0 and w <= 1.0, "%s : intensité %.2f" % [key, w])
	assert_false(WorldLook.WET_SURFACES.has("wood"), "bois sec")
	assert_near(float(PixelSurfaces.material("tiles").get_shader_parameter("wet")), 1.0, 0.001, "carrelage mouillé")
	assert_near(float(PixelSurfaces.material("wood").get_shader_parameter("wet")), 0.0, 0.001, "parquet sec")
