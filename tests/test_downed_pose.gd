extends TestCase
## Pose « à terre » des joueurs vus par les autres (PlayerModel, dernier
## recours de BO1) pour les sept personnages : assis au sol (bassin posé,
## rien sous le sol), main gauche d'appui au sol, pistolet tendu devant, tête
## à la hauteur de la caméra du joueur à terre ; chute et relevé sans pieds
## dans le sol ; mort couché sur le dos. Mesuré sur les sommets skinnés.

const DT := 1.0 / 60.0


func _model(character: int) -> PlayerModel:
	var m := PlayerModel.new()
	m.build(Color.WHITE, character)
	host.add_child(m)
	return m


## Sommets skinnés (repère du joueur) groupés par os : {os: PackedVector3Array}.
## Les accessoires pendus au bassin sous la ceinture (sabre d'Arakawa) sont
## à part (« hips_acc ») : ils n'ont pas d'os propre et traversent le sol
## assis comme couché.
func _skinned(m: PlayerModel) -> Dictionary:
	var skel := m.skel
	var mi := skel.get_node("Mesh") as MeshInstance3D
	var arr := mi.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bi: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var bw: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var xf: Array[Transform3D] = []
	for b in skel.get_bone_count():
		xf.append(skel.get_bone_global_pose(b) * skel.get_bone_global_rest(b).affine_inverse())
	var out := {}
	for i in verts.size():
		var v := verts[i]
		var p := Vector3.ZERO
		var main := 0
		var best := -1.0
		for k in 4:
			var w := bw[i * 4 + k]
			if w <= 0.0:
				continue
			p += (xf[bi[i * 4 + k]] * v) * w
			if w > best:
				best = w
				main = bi[i * 4 + k]
		var bname := skel.get_bone_name(main)
		if bname == "hips" and v.y < 0.8:
			bname = "hips_acc"
		if not out.has(bname):
			out[bname] = []
		out[bname].append(skel.transform * p)
	return out


func _min_y(pts: Array) -> float:
	var y := INF
	for p in pts:
		y = minf(y, p.y)
	return y


func _min_y_of(sk: Dictionary, names: Array) -> float:
	var y := INF
	for n in names:
		if sk.has(n):
			y = minf(y, _min_y(sk[n]))
	return y


const BODY := ["hips", "spine", "chest", "neck", "head", "arm_l", "forearm_l", "arm_r", "forearm_r", "thigh_l", "shin_l", "thigh_r", "shin_r"]
const LEGS := ["thigh_l", "shin_l", "thigh_r", "shin_r"]


func _settle(m: PlayerModel, downed: bool, dead := false, pitch := 0.0, frames := 120) -> void:
	for i in frames:
		m.animate(DT, 0.0, pitch, 0, downed, dead)


## Yeux du modèle (repère du joueur) : lunettes d'Arakawa, au milieu du visage.
func _eyes(m: PlayerModel) -> Vector3:
	var skel := m.skel
	var head := skel.get_bone_global_pose(skel.find_bone("head"))
	return skel.transform * (head * Vector3(0, 0.15, 0.11))


func test_seated_on_the_ground_for_every_character() -> void:
	for ch in CharacterDB.IDS.size():
		var m := _model(ch)
		_settle(m, true)
		var sk := _skinned(m)
		var id: String = CharacterDB.IDS[ch]
		var low := _min_y_of(sk, BODY)
		assert_true(low > -0.025 and low < 0.02, "%s : corps posé au sol, ni enfoncé ni en lévitation (point le plus bas %.3f m)" % [id, low])
		var butt := _min_y(sk.hips)
		assert_true(butt < 0.04, "%s : assis sur les fesses (bas du bassin à %.3f m)" % [id, butt])
		var hips_y := m.skel.transform * m.skel.get_bone_global_pose(m.bones.hips).origin
		assert_true(hips_y.y < 0.2 * m.body_scale, "%s : bassin au ras du sol (%.2f m), pas à mi-hauteur" % [id, hips_y.y])
		# Main gauche d'appui à plat au sol.
		var hand_l := _min_y(sk.forearm_l)
		assert_true(hand_l > -0.03 and hand_l < 0.08, "%s : main d'appui au sol (%.3f m)" % [id, hand_l])
		# Les jambes partent vers l'avant (repère du joueur : -Z), jamais
		# derrière le bassin ni dans le buste.
		for b in LEGS:
			for p in sk[b]:
				if p.z > hips_y.z + 0.16 * m.body_scale:
					failures.append("%s : %s derrière le bassin (z %.2f > %.2f)" % [id, b, p.z, hips_y.z])
					break
		# Pistolet devant, à hauteur de poitrine, au-dessus des jambes.
		var skel := m.skel
		var hand_r := skel.transform * (skel.get_bone_global_pose(m.bones.forearm_r) * Vector3(0, -0.3, 0))
		var chest := skel.transform * skel.get_bone_global_pose(m.bones.chest).origin
		assert_true(hand_r.z < chest.z - 0.35, "%s : pistolet tendu devant (main %.2f, poitrine %.2f)" % [id, hand_r.z, chest.z])
		assert_true(hand_r.y > 0.3 and hand_r.y < 0.9, "%s : pistolet à hauteur de poitrine (%.2f m)" % [id, hand_r.y])
		# Tête à la hauteur de la caméra du joueur à terre, au-dessus de sa position.
		var eyes := _eyes(m)
		assert_true(absf(eyes.y - m.downed_eye_height()) < 0.06,
			"%s : yeux du modèle à %.2f m, caméra à %.2f m" % [id, eyes.y, m.downed_eye_height()])
		assert_true(Vector2(eyes.x, eyes.z).length() < 0.15, "%s : tête au-dessus de la position du joueur (%.2f m)" % [id, Vector2(eyes.x, eyes.z).length()])
		assert_true(m.downed_eye_height() > 0.6 and m.downed_eye_height() < 0.9, "%s : caméra d'un homme assis" % id)
		m.free()


func test_aim_follows_pitch_without_going_into_the_ground() -> void:
	var m := _model(0)
	for pitch in [-1.2, -0.6, 0.0, 0.6, 1.2]:
		_settle(m, true, false, pitch, 60)
		var sk := _skinned(m)
		var low := _min_y_of(sk, ["arm_r", "forearm_r"])
		assert_true(low > 0.05, "bras du pistolet au-dessus du sol (regard %.1f : %.2f m)" % [pitch, low])
		var skel := m.skel
		var sh := skel.transform * skel.get_bone_global_pose(m.bones.arm_r).origin
		var hand := skel.transform * (skel.get_bone_global_pose(m.bones.forearm_r) * Vector3(0, -0.3, 0))
		var up := (hand - sh).normalized().y
		if pitch > 0.3:
			assert_true(up > 0.2, "regard vers le haut : bras levé (%.2f)" % up)
		elif pitch < -0.3:
			assert_true(up < -0.2, "regard vers le bas : bras baissé (%.2f)" % up)
	m.free()


func test_fall_and_get_up_keep_feet_above_the_ground() -> void:
	for ch in [0, 5, 6]:
		var m := _model(ch)
		_settle(m, false, false, 0.0, 10)
		var worst := INF
		var hips_prev := INF
		var jump := 0.0
		for phase in [true, false]:
			for i in 60:
				m.animate(DT, 0.0, 0.0, 0, phase, false)
				var sk := _skinned(m)
				worst = minf(worst, _min_y_of(sk, BODY))
				var hy := m.skel.get_bone_pose_position(m.bones.hips).y
				if hips_prev != INF:
					jump = maxf(jump, absf(hy - hips_prev))
				hips_prev = hy
		var id: String = CharacterDB.IDS[ch]
		assert_true(worst > -0.04, "%s : chute et relevé sans traverser le sol (%.3f m)" % [id, worst])
		assert_true(jump < 0.08, "%s : bassin sans à-coup (%.3f m par image)" % [id, jump])
		var sk2 := _skinned(m)
		var low := _min_y_of(sk2, LEGS)
		assert_true(absf(low) < 0.04, "%s : de nouveau debout (%.3f m)" % [id, low])
		m.free()


func test_dead_lies_on_the_back() -> void:
	for ch in [0, 6]:
		var m := _model(ch)
		_settle(m, true, true, 0.0, 150)
		var sk := _skinned(m)
		var id: String = CharacterDB.IDS[ch]
		var low := _min_y_of(sk, BODY)
		assert_true(low > -0.06 and low < 0.03, "%s : mort, posé au sol (%.3f m)" % [id, low])
		var top := -INF
		for b in ["hips", "spine", "chest", "head", "thigh_l", "thigh_r", "shin_l", "shin_r"]:
			for p in sk[b]:
				top = maxf(top, p.y)
		assert_true(top < 0.5 * m.body_scale + 0.06, "%s : couché (plus haut %.2f m)" % [id, top])
		m.free()


func test_camera_and_capsule_values() -> void:
	assert_true(Player.DOWNED_HEIGHT >= Player.RADIUS * 2.0, "capsule valide")
	assert_true(Player.DOWNED_HEIGHT > PlayerModel.DOWN_EYE_Y * PlayerModel.JOJO_SCALE, "la capsule couvre la tête assise")
	assert_true(Player.DOWNED_EYE_HEIGHT > 0.6 and Player.DOWNED_EYE_HEIGHT < 0.85, "yeux d'un homme assis")


## Mort et posé : la pose finale est figée, animate ne recalcule plus rien
## (ni os ni rayons) tant que le corps ne bouge pas ; elle reprend dès qu'il
## bouge ou n'est plus mort.
func test_dead_settled_stops_animating() -> void:
	var m := _model(0)
	_settle(m, true, true, 0.0, 300)
	assert_true(m._dead_settled, "mort et posé : pose figée")
	var hips_before := m.skel.get_bone_pose_position(m.bones.hips)
	# Os bougé à la main : un appel figé ne le remet pas.
	m.skel.set_bone_pose_position(m.bones.hips, Vector3(0, 5, 0))
	m.animate(DT, 3.0, 0.8, 0, false, true)
	assert_eq(m.skel.get_bone_pose_position(m.bones.hips), Vector3(0, 5, 0), "aucun calcul une fois posé")
	# Corps déplacé (téléporté) : l'animation reprend.
	m.position += Vector3(1, 0, 0)
	m.animate(DT, 0.0, 0.0, 0, false, true)
	assert_true(m._settled_at.is_equal_approx(m.global_position), "corps déplacé : animation reprise (posé au nouvel endroit)")
	assert_true(m.skel.get_bone_pose_position(m.bones.hips).distance_to(hips_before) < 0.01, "pose recalculée : même pose couchée")
	m.free()


## Sondes du sol : relancées seulement si le corps bouge ou tourne, ou à
## intervalle ; requêtes gardées d'une image à l'autre.
func test_ground_probe_only_when_needed() -> void:
	var xf := Transform3D.IDENTITY
	assert_false(PlayerModel.needs_probe(xf, xf, 0.0), "immobile, mesure fraîche : pas de rayon")
	assert_true(PlayerModel.needs_probe(xf, xf.translated(Vector3(0.05, 0, 0)), 0.0), "déplacé de 5 cm")
	assert_true(PlayerModel.needs_probe(xf, xf.rotated(Vector3.UP, 0.1), 0.0), "tourné")
	assert_true(PlayerModel.needs_probe(xf, xf, PlayerModel.PROBE_INTERVAL), "intervalle écoulé")
	var m := _model(0)
	_settle(m, true, false, 0.0, 10)
	var q := m._ground_q
	assert_true(q != null, "requête créée à la première mesure")
	_settle(m, true, false, 0.0, 30)
	assert_true(m._ground_q == q, "requête réutilisée")
	m.free()


## Réapparition après la mort : debout tout de suite, sans se relever depuis
## la pose couchée sous les yeux des autres.
func test_respawn_stands_up_at_once() -> void:
	var fresh := _model(0)
	_settle(fresh, false, false, 0.0, 2)
	var standing := fresh.skel.get_bone_pose_position(fresh.bones.hips)
	var m := _model(0)
	_settle(m, true, true, 0.0, 200)
	m.reset_pose()
	assert_true(m.skel.get_bone_pose_position(m.bones.hips).distance_to(standing) < 0.01, "debout dès la réapparition")
	m.animate(DT, 0.0, 0.0, 0, false, false)
	assert_true(m.skel.get_bone_pose_position(m.bones.hips).distance_to(standing) < 0.01, "et le reste (pas de relevé)")
	assert_true(m.skel.transform.basis.y.normalized().dot(Vector3.UP) > 0.999, "corps droit")
	fresh.free()
	m.free()
