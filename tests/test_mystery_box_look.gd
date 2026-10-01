extends TestCase
## Apparence de la boîte mystère (BoxModel) : le modèle Blender garde
## l'empreinte et le point d'interaction de la boîte, le couvercle pivote sur
## sa charnière, la colonne de lumière et la lampe restent discrètes.

var _parent: Node3D


func after_each() -> void:
	if _parent:
		_parent.free()
		_parent = null


func _box() -> MysteryBox:
	_parent = Node3D.new()
	host.add_child(_parent)
	var markers: Array[MapMarker] = []
	for i in 2:
		var m := MapMarker.new()
		m.id = "box_%d" % i
		m.pos = Vector3(2.0 + i * 6.0, 0.0, 3.0)
		m.wall = Vector3(0, 0, -1)
		markers.append(m)
	var box := MysteryBox.new()
	box.setup_spots(markers, 0)
	_parent.add_child(box)
	# Tas de planches des emplacements vides : ajoutés en différé.
	await wait_frames(1)
	return box


func test_collision_et_point_d_interaction_inchanges() -> void:
	var box := await _box()
	var shape: BoxShape3D = null
	var cs_y := 0.0
	for c in box._root.get_children():
		if c is StaticBody3D:
			var cs := c.get_child(0) as CollisionShape3D
			shape = cs.shape as BoxShape3D
			cs_y = cs.position.y
	assert_true(shape != null, "collision de la boîte")
	assert_eq(shape.size, Vector3(1.8, 0.85, 0.85), "empreinte de collision")
	assert_near(cs_y, 0.425, 0.0001, "collision posée au sol")
	# Emplacement : centre à SPOT_WALL_GAP du mur (z = 2,5) ; point d'interaction 0,7 m devant, à 0,9 m.
	assert_true(box.global_position.is_equal_approx(Vector3(2.0, 0.0, 3.07)), "boîte posée à l'emplacement (%s)" % box.global_position)
	assert_true(box.interact_point().is_equal_approx(Vector3(2.0, 0.9, 3.77)), "point d'interaction (%s)" % box.interact_point())
	assert_eq(box.interact_range, 2.0, "portée d'interaction")


func test_modele_dans_l_empreinte() -> void:
	var box := await _box()
	assert_true(ResourceLoader.exists(BoxModel.MODEL_PATH), "modèle .glb présent")
	assert_true(box._open_meshes.size() >= 2, "fond lumineux et intérieur du modèle")
	assert_true(box._root.get_node_or_null("Model") != null, "modèle Blender chargé (pas le repli en boîtes)")
	var inv := box._root.global_transform.affine_inverse()
	var aabb := AABB()
	var first := true
	var lid_meshes := 0
	for mi: MeshInstance3D in box._root.find_children("*", "MeshInstance3D", true, false):
		if mi == box._beam or mi == box._haze:
			continue
		if box._lid.is_ancestor_of(mi):
			lid_meshes += 1
		var b := (inv * mi.global_transform) * mi.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	assert_true(lid_meshes >= 2, "bois et ferrures du couvercle sous le pivot (%d)" % lid_meshes)
	# Petits détails (poignées, charnières, moraillon) : 5 cm au plus hors collision.
	var lo := aabb.position
	var hi := aabb.end
	assert_true(lo.x > -0.95 and hi.x < 0.95, "largeur %.3f..%.3f" % [lo.x, hi.x])
	assert_true(lo.z > -0.46 and hi.z < 0.46, "profondeur %.3f..%.3f" % [lo.z, hi.z])
	assert_true(lo.y > -0.01 and hi.y < 0.87, "hauteur %.3f..%.3f" % [lo.y, hi.y])
	assert_true(hi.x > 0.85 and hi.y > 0.8, "le modèle occupe l'empreinte (%s)" % aabb)


func test_couvercle_pivote_sur_la_charniere() -> void:
	var box := await _box()
	assert_eq(box._lid.position, MysteryBox.LID_HINGE, "pivot sur l'arête arrière haute")
	assert_true(MysteryBox.LID_OPEN_ANGLE < -1.3 and MysteryBox.LID_OPEN_ANGLE > -1.65,
			"ouvert presque à la verticale (%.2f rad)" % MysteryBox.LID_OPEN_ANGLE)


## Bug joueur : couvercle ouvert qui entrait dans le mur. Ouvert en grand,
## toutes ses pièces restent devant le mur (à SPOT_WALL_GAP derrière le centre).
func test_couvercle_ouvert_hors_du_mur() -> void:
	var box := await _box()
	box._lid.rotation.x = MysteryBox.LID_OPEN_ANGLE
	var inv := box._root.global_transform.affine_inverse()
	var back := 0.0
	for mi: MeshInstance3D in box._lid.find_children("*", "MeshInstance3D", true, false):
		var b := (inv * mi.global_transform) * mi.get_aabb()
		back = minf(back, b.position.z)
	assert_true(back < -0.5, "le couvercle bascule bien derrière le coffre (%.3f)" % back)
	assert_true(back > -MysteryBox.SPOT_WALL_GAP + 0.02, "2 cm au moins devant le mur (arrière %.3f, mur %.3f)" % [back, -MysteryBox.SPOT_WALL_GAP])
	var wall_z := 2.5
	assert_near(box.global_position.z - MysteryBox.SPOT_WALL_GAP, wall_z, 0.0001, "mur à SPOT_WALL_GAP du centre")


## Bug joueur : sur l'hôte, `state` et `location` sont déjà changés quand
## l'état diffusé revient (call_local) ; après l'envol, la boîte doit
## réapparaître quand même, au même endroit ou ailleurs.
func test_boite_reapparait_apres_l_ours_sur_l_hote() -> void:
	for target in [0, 1]:
		var box := await _box()
		box.state = MysteryBox.State.MOVING
		box.apply_state(box.get_state(), false)
		box._root.position.y = 6.0
		box._root.visible = false
		# Comme _process puis _close côté serveur.
		box.location = target
		box.state = MysteryBox.State.IDLE
		box.apply_state(box.get_state(), true)
		assert_true(box._root.visible, "boîte visible après l'envol (emplacement %d)" % target)
		assert_eq(box._root.position.y, 0.0, "posée au sol")
		assert_true(box.global_position.is_equal_approx(box.spots[target].pos), "à l'emplacement %d" % target)
		assert_false(box._markers[target].visible, "pas de tas de planches sous la boîte")
		after_each()


func test_jamais_d_ours_avec_un_seul_emplacement() -> void:
	for use in [1, 4, 8, 13, 40]:
		assert_eq(MysteryBox.skull_chance(use, 0, 1), 0.0, "un seul emplacement : pas d'ours (tirage %d)" % use)
	assert_near(MysteryBox.skull_chance(8, 0, 2), 1.0, 0.001, "deux emplacements : règles de BO1")


## Colonne de lumière et lampe « discrètes » (demande des joueurs : l'ancien
## cône orange était beaucoup trop visible).
func test_lumiere_discrete() -> void:
	var box := await _box()
	assert_true(MysteryBox.BEAM_INTENSITY > 0.02 and MysteryBox.BEAM_INTENSITY <= 0.08, "intensité de la colonne")
	assert_true(MysteryBox.BEAM_BOTTOM + MysteryBox.BEAM_HEIGHT <= 3.3, "sommet sous les plafonds")
	assert_true(MysteryBox.BEAM_RADIUS <= 0.4, "colonne fine")
	assert_true(MysteryBox.BEAM_COLOR.b >= MysteryBox.BEAM_COLOR.r, "teinte froide, jamais orange")
	var mat := box._beam.material_override as ShaderMaterial
	assert_true(mat != null and mat.shader == BoxModel.BEAM_SHADER, "shader de colonne douce")
	assert_near(float(mat.get_shader_parameter("intensity")), MysteryBox.BEAM_INTENSITY, 0.0001, "intensité appliquée")
	assert_eq(box._beam.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "colonne sans ombre")
	assert_true(MysteryBox.HAZE_INTENSITY <= 0.25, "halo d'ouverture doux")
	assert_true(MysteryBox.LIGHT_IDLE_ENERGY <= 0.5 and MysteryBox.LIGHT_OPEN_ENERGY <= 1.5, "lampe faible")
	assert_true(MysteryBox.LIGHT_RANGE <= 3.5, "portée courte (pas de tache sur les murs)")
	assert_true(box._light.light_volumetric_fog_energy <= 0.3, "presque rien dans la brume")
	assert_true(not box._light.shadow_enabled, "lampe sans ombre (coût)")


## Ouverture : le fond s'allume et la lampe passe au doré, puis tout revient.
func test_ouverture_allume_le_fond() -> void:
	var box := await _box()
	box.state = MysteryBox.State.ROLLING
	box._timer = 100.0
	for i in 120:
		box._animate(1.0 / 60.0)
	assert_true(box._open_amount > 0.95, "ouverture suivie (%.2f)" % box._open_amount)
	assert_near(float(box._open_meshes[0].get_instance_shader_parameter("open")), box._open_amount, 0.001, "fond allumé")
	assert_true(box._haze.visible, "halo au-dessus du coffre ouvert")
	assert_true(box._light.light_energy > MysteryBox.LIGHT_IDLE_ENERGY, "lampe plus forte ouverte")
	box.state = MysteryBox.State.IDLE
	for i in 240:
		box._animate(1.0 / 60.0)
	assert_eq(box._open_amount, 0.0, "refermée")
	assert_false(box._haze.visible, "halo éteint")
	assert_near(box._light.light_energy, MysteryBox.LIGHT_IDLE_ENERGY, 0.0001, "lampe au repos")
