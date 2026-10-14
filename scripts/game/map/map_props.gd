class_name MapProps
extends RefCounted
## Décor d'une carte vu par le jeu : courant (PowerGrid), grésillement des
## lampes (LightFlicker) et matériaux à shader dédié à préchauffer. Commun aux
## cartes grille (PropBuilder) et aux cartes en maillage (MeshMapBuilder).
## Ambiance des pièces (MoodZones, RoomMood) et poussière dans les cônes des
## lampes (LampDust) : posées ici aussi, pour les deux sortes de cartes.

var root: Node3D
var flicker: LightFlicker
var power: PowerGrid
## Ambiances des pièces (null : aucune) : à poser AVANT les lampes
## (add_moods), qui prennent la couleur de leur pièce.
var moods: MoodZones
## Poussière des cônes de lampes (un système par carte, finish_lamps).
var dust: LampDust
## Matériaux à shader dédié, montrés pendant le préchauffage (Warmup).
var warmup_materials: Array[Material] = []
var _lamp_i := 0


## Nœud racine du décor, avec le grésillement et le réseau électrique.
func _make_root(parent: Node3D, root_name := "Props") -> void:
	root = Node3D.new()
	root.name = root_name
	parent.add_child(root)
	flicker = LightFlicker.new()
	flicker.name = "LightFlicker"
	root.add_child(flicker)
	power = PowerGrid.new()
	power.name = "PowerGrid"
	power.setup(flicker)
	root.add_child(power)


## Ambiances des pièces : `areas` = [[préréglage, [AABB...]]...] (préréglage
## « » ou inconnu : ignoré). Lumières de remplissage et brume liées au courant.
func add_moods(areas: Array) -> void:
	var mz := MoodZones.new()
	mz.name = "Moods"
	for a in areas:
		mz.add_area(String(a[0]), a[1])
	if mz.areas.is_empty():
		mz.free()
		return
	moods = mz
	root.add_child(mz)
	mz.build(power)


## Lampe de la carte : groupe RenderQuality (ombres et fondu selon la
## qualité), reliée au courant (sinon toujours allumée : bougies, feu),
## grésillante si `flickers`. `color` : couleur une fois le courant rétabli
## (luminaires de l'éditeur ; par défaut l'ampoule chaude des lampes BO1).
## `fixture` : type de luminaire de l'éditeur (« » : lampe de plafond
## automatique ou de BUNKER K-7) ; il choisit le rendu (LampStyle) : sous un
## abat-jour, faible lueur de la lampe + flaque dirigée vers le bas (LampPool)
## + rebond vers le plafond ; source d'appoint colorée (gyrophare, écran...) :
## lumière courte sans ombre (+ faisceaux tournants du gyrophare).
## Ambiance de la pièce (moods) : couleur mélangée à la sienne si `tint`
## (lampe automatique, luminaire laissé à sa couleur du catalogue) et énergie
## réglée ; lampes du réseau électrique seulement (`powered`), jamais pour une
## source d'appoint.
func add_lamp(pos: Vector3, energy: float, light_range: float, flickers: bool, color := PowerGrid.ON_COLOR, powered := true, fixture := "", tint := true) -> OmniLight3D:
	var style := LampStyle.of(fixture)
	var accent := LampStyle.accent_of(style)
	# Seules les lampes du réseau électrique : flammes (bougies, feu) et
	# sources d'appoint gardent leur couleur et leur énergie.
	if moods and accent == "" and powered:
		var ce := RoomMood.lamp(moods.mood_at(pos), color, energy, tint)
		color = ce[0]
		energy = ce[1]
	var light := OmniLight3D.new()
	light.name = "Lamp%d" % _lamp_i
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.omni_attenuation = float(style.get("att", 1.3))
	light.light_volumetric_fog_energy = float(style.get("fog", 1.0))
	if LampStyle.has_pool(style):
		var fill := float(style.fill)
		light.light_energy = energy * fill
		light.omni_range = light_range * float(style.fill_range)
		light.omni_attenuation = float(style.fill_att)
		light.light_volumetric_fog_energy = float(style.fill_fog)
		var pool := LampPool.new()
		pool.name = "Pool"
		pool.ratio = float(style.pool) / fill
		pool.rotation.x = -PI * 0.5
		pool.spot_range = light_range * float(style.range_k)
		pool.spot_angle = float(style.angle)
		pool.spot_angle_attenuation = float(style.angle_att)
		pool.spot_attenuation = 1.0
		pool.light_volumetric_fog_energy = float(style.fog)
		pool.shadow_bias = 0.04
		pool.shadow_normal_bias = 1.2
		light.add_child(pool)
		if LampStyle.has_bounce(style):
			pool.bounce = _bounce(style)
			pool.bounce_ratio = float(style.bounce)
			light.add_child(pool.bounce)
		if dust == null:
			# Dans l'arbre tout de suite (jamais orphelin, même sans finish_lamps).
			dust = LampDust.new()
			root.add_child(dust)
		dust.add_cone(pos, float(style.angle), minf(pool.spot_range, pos.y - _floor_below(pos)))
	if accent != "":
		# Pas de reflet ponctuel vif sur les sols mouillés (point vert flottant).
		light.light_specular = float(LampStyle.ACCENT.specular)
	if accent == "beacon":
		light.add_child(BeaconSpin.make(LampStyle.BEACON))
	if style.get("no_shadow", false):
		light.set_meta("no_shadow", true)
	# Ombres et distances de fondu : réglées par RenderQuality.
	light.set_meta("lamp_index", _lamp_i)
	light.add_to_group(RenderQuality.LAMP_GROUP)
	RenderQuality.apply_lamp(light, RenderQuality.current())
	root.add_child(light)
	if flickers:
		flicker.add(light)
	if powered:
		power.add(light, color)
	_lamp_i += 1
	return light


## Rebond vers le plafond d'une lampe de plafond (LampStyle) : projecteur
## sans ombre ni brume, `bounce_drop` m sous la lampe, dirigé vers le haut.
static func _bounce(style: Dictionary) -> SpotLight3D:
	var b := SpotLight3D.new()
	b.name = "Bounce"
	b.position = Vector3(0, -float(style.bounce_drop), 0)
	b.rotation.x = PI * 0.5
	b.spot_angle = float(style.bounce_angle)
	b.spot_range = float(style.bounce_range)
	b.spot_attenuation = 0.8
	b.spot_angle_attenuation = 1.2
	b.light_specular = 0.0
	b.light_volumetric_fog_energy = 0.0
	b.shadow_enabled = false
	return b


## Hauteur du sol sous une lampe (pour la poussière de son cône) : sol de la
## pièce d'ambiance qui la contient, sinon 0 (cartes à un seul niveau) ou
## 3 m sous la lampe (pièces en hauteur).
func _floor_below(pos: Vector3) -> float:
	if moods:
		for a in moods.areas:
			for b: AABB in a.boxes:
				if b.grow(0.1).has_point(pos):
					return b.position.y
	return 0.0 if pos.y < 4.5 else pos.y - 3.0


## Fin de la pose des lampes : poussière des cônes (un seul système).
func finish_lamps() -> void:
	if dust:
		dust.finish()
