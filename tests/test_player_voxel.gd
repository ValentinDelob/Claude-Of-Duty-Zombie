extends TestCase
## Joueur de baseball CUBIQUE vu par les autres (PlayerModel,
## assets/models/player/player_voxel.glb) : modèle chargé, 1,80 m, budget de
## triangles, mesh partagé, zone d'équipe teintée par la couleur du joueur,
## ossature aux positions de l'animation, poses de visée et de réanimation.

const DT := 1.0 / 60.0


func _model(col := Color.RED) -> PlayerModel:
	var m := PlayerModel.new()
	m.build(col)
	host.add_child(m)
	return m


func _arrays() -> Array:
	return (PlayerModel.model().mesh as ArrayMesh).surface_get_arrays(0)


func test_model_loads_at_player_height() -> void:
	assert_false(PlayerModel.model().is_empty(), "player_voxel.glb chargé")
	var pos: PackedVector3Array = _arrays()[Mesh.ARRAY_VERTEX]
	var lo := INF
	var hi := -INF
	for p in pos:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	assert_near(lo, 0.0, 0.001, "pieds au sol")
	assert_near(hi, 1.8, 0.001, "1,80 m (72 cubes de 2,5 cm)")


func test_triangle_budget() -> void:
	var idx: PackedInt32Array = _arrays()[Mesh.ARRAY_INDEX]
	@warning_ignore("integer_division")
	var tris := idx.size() / 3
	assert_true(tris > 2000 and tris < 9000, "budget < 9 000 triangles (%d)" % tris)


func test_team_zone_present() -> void:
	var uv2: PackedVector2Array = _arrays()[Mesh.ARRAY_TEX_UV2]
	var n := 0
	for u in uv2:
		if roundi(u.y) == RigBuilder.MAT_TEAM:
			n += 1
	assert_true(n > uv2.size() / 10, "zone d'équipe étendue (%d sommets sur %d)" % [n, uv2.size()])


func test_team_colour_per_player_and_shared_mesh() -> void:
	var a := _model(HudStyle.player_color(0))
	var b := _model(HudStyle.player_color(1))
	assert_eq(a.team_color(), HudStyle.player_color(0), "ambre")
	assert_eq(b.team_color(), HudStyle.player_color(1), "cyan")
	var ma := (a.skel.get_node("Mesh") as MeshInstance3D)
	var mb := (b.skel.get_node("Mesh") as MeshInstance3D)
	assert_true(ma.mesh == mb.mesh, "mesh partagé (un seul en mémoire)")
	assert_true(ma.material_override == mb.material_override, "matériau partagé")
	assert_eq(ma.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "ombres portées")
	a.free()
	b.free()


func test_skeleton_matches_animation() -> void:
	var o: Dictionary = PlayerModel.model().overrides
	assert_near((o.hips as Vector3).y, 0.95, 0.001, "bassin à 0,95 m")
	assert_near(-(o.shin_l as Vector3).y, 0.45, 0.001, "cuisse de 0,45 m")
	assert_near(-(o.forearm_r as Vector3).y, 0.3, 0.001, "bras de 0,30 m (point d'attache de l'arme)")
	var d := PlayerModel.dims()
	assert_true(d.foot[3] > 0.12, "pied mesuré vers l'avant (%.3f m)" % d.foot[3])


func test_aim_raises_the_weapon() -> void:
	var m := _model()
	for i in 30:
		m.animate(DT, 0.0, 0.0, 0, false, false)
	var low := m.skel.get_bone_pose_rotation(m.bones.arm_r).get_euler().x
	for i in 30:
		m.animate(DT, 0.0, 0.0, Player.FLAG_AIM, false, false)
	var high := m.skel.get_bone_pose_rotation(m.bones.arm_r).get_euler().x
	assert_true(high < low - 0.1, "arme montée en visée (%.2f -> %.2f)" % [low, high])
	m.free()


func test_revive_pose_kneels_and_reaches_down() -> void:
	var m := _model()
	for i in 60:
		m.animate(DT, 0.0, 0.0, 0, false, false, true)
	var hips := m.skel.get_bone_pose_position(m.bones.hips).y
	assert_true(hips < 0.7, "accroupi pour réanimer (bassin %.2f m)" % hips)
	var hand := m.skel.transform * (m.skel.get_bone_global_pose(m.bones.forearm_r) * Vector3(0, -0.3, 0))
	assert_true(hand.y < 0.6 and hand.z < -0.2, "main tendue vers le sol devant (%s)" % hand)
	for i in 60:
		m.animate(DT, 0.0, 0.0, 0, false, false, false)
	assert_true(m.skel.get_bone_pose_position(m.bones.hips).y > 0.9, "se relève après")
	m.free()
