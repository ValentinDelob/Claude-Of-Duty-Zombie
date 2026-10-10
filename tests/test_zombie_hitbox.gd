extends TestCase
## Formes de collision des zombies : forme de DÉPLACEMENT (capsule du
## CharacterBody3D, rayon du navmesh, séparation) mesurée contre la largeur
## réelle du modèle (sommets skinnés de chaque look, en marche, course et
## sprint), avec et sans les bras ; zones de TOUCHE des tirs (corps, tête,
## avant-bras) hors du déplacement.

## Os des bras et des jambes (RigBuilder.BONES).
const ARM_BONES := ["arm_l", "forearm_l", "arm_r", "forearm_r"]
const LEG_BONES := ["thigh_l", "shin_l", "thigh_r", "shin_r"]
## Phases de démarche échantillonnées par pose (un cycle complet).
const PHASES := 8
## Zombie cubique : demi-largeur du torse au-delà de la capsule tolérée (m).
const RADIUS_SLACK := 0.11


## Mesure du modèle d'un zombie déjà posé : pour chaque partie (« corps » :
## bassin, tronc, cou, tête ; « bras » ; « jambes »), demi-largeur latérale
## (|x| max), avant (z max), arrière (-z min) et rayon horizontal max depuis
## l'axe de la capsule, dans le repère du zombie (le modèle regarde vers +Z).
## `step` : un sommet sur `step` (mesure plus rapide).
static func measure(z: Zombie, arr: Array, step := 1) -> Dictionary:
	var rest: Dictionary = RigBuilder._rest_globals(ZombieModel.rest_overrides())
	var mats := []
	for b in RigBuilder.BONES:
		var bi: int = z.bones[b[0]]
		mats.append(z.skel.get_bone_global_pose(bi) * (rest[b[0]] as Transform3D).affine_inverse())
	var cat := []
	for b in RigBuilder.BONES:
		cat.append(1 if ARM_BONES.has(b[0]) else (2 if LEG_BONES.has(b[0]) else 0))
	var to_z: Transform3D = z.skel.transform
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	@warning_ignore("integer_division")
	var per: int = bones.size() / verts.size()
	var out := {}
	for part in ["corps", "bras", "jambes"]:
		out[part] = {"x": 0.0, "front": -INF, "back": -INF, "r": 0.0, "top": 0.0}
	for i in range(0, verts.size(), step):
		var v := verts[i]
		var p := Vector3.ZERO
		var cw := [0.0, 0.0, 0.0]
		for k in per:
			var w := weights[i * per + k]
			if w <= 0.0:
				continue
			var bi := bones[i * per + k]
			p += (mats[bi] as Transform3D) * v * w
			cw[cat[bi]] += w
		p = to_z * p
		var c := 0
		if cw[1] > cw[c]:
			c = 1
		if cw[2] > cw[c]:
			c = 2
		var band := "%s@%d" % [["corps", "bras", "jambes"][c], clampi(int(p.y / 0.3), 0, 6)]
		if not out.has(band):
			out[band] = {"x": 0.0, "front": -INF, "back": -INF, "r": 0.0, "top": 0.0}
		var ob: Dictionary = out[band]
		ob.x = maxf(ob.x, absf(p.x))
		ob.front = maxf(ob.front, p.z)
		ob.back = maxf(ob.back, -p.z)
		ob.r = maxf(ob.r, Vector2(p.x, p.z).length())
		var o: Dictionary = out[["corps", "bras", "jambes"][c]]
		o.x = maxf(o.x, absf(p.x))
		o.front = maxf(o.front, p.z)
		o.back = maxf(o.back, -p.z)
		o.r = maxf(o.r, Vector2(p.x, p.z).length())
		o.top = maxf(o.top, p.y)
	return out


## Pire mesure (max de chaque valeur) sur tous les looks, aux classes de
## vitesse `classes`, sur un cycle de marche complet.
static func worst(host_node: Node, classes: Array, looks := ZombieModel.LOOK_COUNT, step := 3) -> Dictionary:
	var res := {}
	# Modèle cubique : un seul mesh pour tous les zombies.
	for key in (1 if ZombieModel.has_model() else looks):
		var arr := ZombieModel.mesh_arrays(key)
		for cls: int in classes:
			var z := Zombie.new()
			z.setup(90000 + key, key, cls, false)
			host_node.add_child(z)
			z.set_process(false)
			z.state = Zombie.State.CHASE
			z.anim_speed = Zombie.SPEEDS[cls]
			# Mélanges de course établis, puis un cycle de marche.
			for i in 90:
				z.anim.pose(1.0 / 30.0)
			for ph in PHASES:
				z.gait_phase = TAU * float(ph) / PHASES - 0.001
				z.anim.pose(0.001)
				var m := measure(z, arr, step)
				for part in m:
					if not res.has(part):
						res[part] = m[part].duplicate()
						continue
					for k in m[part]:
						res[part][k] = maxf(res[part][k], m[part][k])
			z.free()
	return res


## Zombie posé au repos (look `key`), dans l'arbre du test.
func _standing(key: int) -> Zombie:
	var z := Zombie.new()
	z.setup(90000 + key, key, 0, false)
	host.add_child(z)
	z.set_process(false)
	z.state = Zombie.State.IDLE
	z.anim_speed = 0.0
	for i in 30:
		z.anim.pose(1.0 / 30.0)
	return z


func test_movement_capsule_is_the_torso_without_arms() -> void:
	# Tronc (bassin à poitrine, 0,6 à 1,2 m) en marche, course et sprint, sur
	# tous les looks : dans la capsule. Épaules et bras : en dehors.
	var w := worst(host, [0, 2, 3], ZombieModel.LOOK_COUNT, 6)
	var torso := maxf(w["corps@2"].x, w["corps@3"].x)
	print("[hitbox] demi-largeur : tronc %.2f m, épaules %.2f m, bras %.2f m (avant %.2f m) ; capsule %.2f m" % [torso, w["corps@4"].x, w.bras.x, w.bras.front, Zombie.RADIUS])
	if ZombieModel.has_model():
		# Zombie cubique : torse et blouse larges (0,25 m de demi-largeur, 0,32 m
		# aux coins quand le buste vrille) ; la capsule garde le rayon réglé
		# pour la navigation et la horde (couloirs, goulets, places aux
		# fenêtres) : deux voisins se frôlent du tissu, au plus RADIUS_SLACK de
		# chaque côté.
		assert_true(torso <= Zombie.RADIUS + RADIUS_SLACK, "tronc cubique (%.2f m) à moins de %.2f m de la capsule (%.2f m)" % [torso, RADIUS_SLACK, Zombie.RADIUS])
		assert_true(torso >= Zombie.RADIUS, "capsule dans le tronc (%.2f m)" % torso)
	else:
		assert_true(torso <= Zombie.RADIUS, "tronc (%.2f m) dans la capsule (%.2f m)" % [torso, Zombie.RADIUS])
		assert_true(Zombie.RADIUS - torso < 0.05, "capsule au plus près du tronc (%.2f m de marge)" % (Zombie.RADIUS - torso))
	assert_true(w["corps@4"].x > Zombie.RADIUS + 0.05, "épaules hors de la capsule (%.2f m)" % w["corps@4"].x)
	assert_true(w.bras.r > Zombie.RADIUS + 0.3, "bras tendus bien hors de la capsule (%.2f m de l'axe)" % w.bras.r)


func test_shoulder_radius_matches_the_model() -> void:
	# Demi-largeur aux épaules au repos, look par look (moyenne).
	var sum := 0.0
	var looks := 1 if ZombieModel.has_model() else ZombieModel.LOOK_COUNT
	for key in looks:
		var z := _standing(key)
		var m := measure(z, ZombieModel.mesh_arrays(key), 2)
		sum += maxf(m.get("corps@4", {}).get("x", 0.0), m.get("bras@4", {}).get("x", 0.0))
		z.free()
	var mean := sum / looks
	if ZombieModel.has_model():
		# Zombie cubique : bras pendants écartés du torse (0,375 m de l'axe,
		# manches à 0,45 m). SHOULDER_RADIUS reste la place réservée par la
		# navigation et les fenêtres (règle de jeu) : plus étroite que le
		# modèle, jamais plus large que son torse.
		print("[hitbox] épaules du modèle cubique %.2f m, SHOULDER_RADIUS %.2f m" % [mean, Zombie.SHOULDER_RADIUS])
		assert_true(mean > Zombie.SHOULDER_RADIUS, "épaules du modèle %.2f m au-delà de SHOULDER_RADIUS %.2f m" % [mean, Zombie.SHOULDER_RADIUS])
	else:
		assert_true(absf(mean - Zombie.SHOULDER_RADIUS) < 0.04, "épaules du modèle %.2f m ~ SHOULDER_RADIUS %.2f m" % [mean, Zombie.SHOULDER_RADIUS])
	assert_true(Zombie.SHOULDER_RADIUS > Zombie.RADIUS, "épaules plus larges que le tronc")
	# Navmesh : aucun chemin par une fente plus étroite que les épaules.
	assert_true(StairGen.AGENT_RADIUS >= Zombie.SHOULDER_RADIUS, "couloirs d'escalier aux épaules")
	assert_true(Spawner.WINDOW_SPAWN_CLEARANCE >= 2.0 * Zombie.SHOULDER_RADIUS - 0.001, "apparitions aux fenêtres : épaules contre épaules")


func test_separation_range_follows_the_bodies() -> void:
	assert_true(Zombie.SEPARATION_RANGE > 2.0 * Zombie.RADIUS, "séparation au-delà du contact de deux troncs")
	assert_true(Zombie.SEPARATION_RANGE <= 2.0 * Zombie.RADIUS + 0.35, "séparation courte : pas de horde qui se repousse contre les bords d'un goulet")
	assert_true(Hellhound.SEPARATION_DOG > 2.0 * Hellhound.RADIUS_DOG, "chiens : séparation au-delà du contact")
	for r in [Zombie.SEPARATION_RANGE, Hellhound.SEPARATION_DOG]:
		assert_true(r <= ZombieManager.GRID_CELL, "portée %.2f m dans les 9 cases de la grille" % r)


func test_shot_zones_are_not_movement_shapes() -> void:
	var z := _standing(3)
	# Déplacement : une seule forme, la capsule du tronc, sur la couche zombies.
	var shapes := z.get_children().filter(func(n): return n is CollisionShape3D)
	assert_eq(shapes.size(), 1, "une seule forme de déplacement")
	var cap := z.body_shape.shape as CapsuleShape3D
	assert_near(cap.radius, Zombie.RADIUS, 0.0001, "capsule au rayon du tronc")
	assert_near(cap.height, Zombie.HEIGHT, 0.0001)
	assert_eq(z.collision_mask & Zombie.HITBOX_LAYER, 0, "le déplacement ignore les zones de touche")
	# Touche : tête, corps, avant-bras et hauts de bras (BO1 : un tir au bras
	# compte ; les épaules du zombie cubique dépassent de la capsule).
	var zones := {}
	for a: Area3D in [z.hit_body, z.hit_head] + z.hit_arms + z.hit_upper_arms:
		assert_eq(a.collision_layer, Zombie.HITBOX_LAYER, "%s : couche des tirs" % a.name)
		assert_eq(a.collision_mask, 0, "%s : ne heurte rien" % a.name)
		assert_false(a.monitoring or a.monitorable, "%s : pas de détection de contact" % a.name)
		zones[int(a.get_meta("zone"))] = zones.get(int(a.get_meta("zone")), 0) + 1
	assert_eq(zones, {0: 1, 1: 1, 2: 4}, "corps, tête, deux avant-bras, deux hauts de bras")
	# Le corps s'arrête au haut du torse : il ne mord pas dans le bas de la
	# tête (tir au menton ou sur une tête rejetée en arrière = tir à la tête).
	var bb := ZombieModel.bone_bounds()
	if not bb.is_empty():
		var hc := z.hit_body.get_child(0).shape as CapsuleShape3D
		var top := z.hit_body.position.y + hc.height * 0.5
		assert_true(top <= (bb.chest as AABB).end.y + 0.001, "corps sous la tête (haut %.2f m, torse %.2f m)" % [top, (bb.chest as AABB).end.y])
	z.free()


func test_arms_stay_shootable_outside_the_capsule() -> void:
	# Marcheur bras tendus : les zones des avant-bras dépassent de la capsule,
	# un tir au bras touche le bras (pas le vide, pas le corps).
	var z: Zombie
	for v in 60:
		z = Zombie.new()
		z.setup(91000, v, 0, false)
		host.add_child(z)
		if z.anim.arm_style == ZombieAnim.Arms.REACH:
			break
		z.free()
	z.set_process(false)
	z.state = Zombie.State.CHASE
	z.anim_speed = Zombie.SPEEDS[0]
	for i in 60:
		z.anim.pose(1.0 / 30.0)
	for side in ["l", "r"]:
		# Milieu de la zone de l'avant-bras (os + HitArm.position), repère du zombie.
		var ha: Area3D = z.hit_arms[0 if side == "l" else 1]
		var p := z.skel.transform * z.skel.get_bone_global_pose(z.bones["forearm_" + side]) * ha.position
		assert_true(Vector2(p.x, p.z).length() > Zombie.RADIUS + 0.15, "avant-bras %s hors de la capsule (%.2f m de l'axe)" % [side, Vector2(p.x, p.z).length()])
	z.free()
