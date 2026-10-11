class_name PlayerModel
extends Node3D
## Joueur de baseball CUBIQUE vu par les autres (GAME_CONCEPT.md § 3 : tous
## les joueurs incarnent le même personnage, distingués par leur couleur ;
## § 4.19 : cubes de 2,5 cm). Modèle tools/blender/player/player_voxel.py
## (assets/models/player/player_voxel.glb), chargé par ZombieGlb : un mesh
## skinné partagé (un draw call + l'arme), couleur par face de cube ; la zone
## d'équipe (casquette, sous-maillot, liserés, numéros, chaussettes) prend la
## couleur du joueur (player_voxel.gdshader, `team_color` par instance).
## Animations procédurales pilotées par l'état réseau : marche, course,
## accroupi, allongé, plongeon, visée (le buste suit le regard, arme épaulée
## plus haut en visée), tir, réanimation d'un coéquipier (accroupi, bras
## tendus vers le sol), à terre, mort.

const MODEL_PATH := "res://assets/models/player/player_voxel.glb"
## Yeux du modèle dans le repère de l'os de la tête (milieu des yeux, face
## avant du visage) : rangées 64-65 et avant du visage du script Blender.
const EYE_OFFSET := Vector3(0, 0.1, 0.15)

static var _material: ShaderMaterial
static var _skin: Skin
## Dimensions mesurées sur le modèle (voir dims()).
static var _dims := {}

var skel: Skeleton3D
var bones: Dictionary
var weapon_attach: BoneAttachment3D
var weapon_model: Node3D
var weapon_key := ""
var _phase := 0.0
var _recoil := 0.0
var _down_k := 0.0
var _prone_k := 0.0
## Réanime un coéquipier (0..1) : accroupi, bras vers le blessé.
var _revive_k := 0.0
## Visée (0..1) : arme montée à l'œil.
var _aim_k := 0.0
## Mort : couché sur le dos (0..1, après la pose à terre).
var _dead_k := 0.0
## À terre devant un mur ou une marche : genoux repliés (0..1).
var _tuck := 0.0
## Normale du sol sous le joueur à terre (repère du joueur, lissée).
var _floor_n := Vector3.UP
var _body_x := 0.0
## Sondes du sol à terre (_probe_ground) : requêtes gardées (aucune
## allocation par image, comme Zombie._floor_q), relancées seulement si le
## corps a bougé ou tourné, ou toutes les PROBE_INTERVAL s ; entre deux,
## les valeurs lissées tendent vers les dernières cibles mesurées.
const PROBE_INTERVAL := 0.25
var _ground_q: PhysicsRayQueryParameters3D
var _front_q: PhysicsRayQueryParameters3D
var _probe_xf := Transform3D()
var _probe_age := INF
var _floor_target := Vector3.UP
var _tuck_target := 0.0
## Mort et posé (pose finale atteinte, corps immobile) : plus rien à animer
## ni à sonder tant qu'il reste là (animate revient tout de suite).
var _dead_settled := false
var _settled_at := Vector3.INF

## Pose « à terre » (dernier recours de BO1) : assis sur les fesses, buste
## renversé en arrière et appuyé sur la main gauche posée au sol derrière,
## jambe droite allongée, genou gauche relevé, pistolet tenu à bout de bras
## droit dans l'axe du regard. Rotations autour de X (rad, repère du
## squelette, échelle 1) : négatif = buste vers l'arrière, membres vers
## l'avant. Bassin, dos, poitrine : relatifs ; membres : inclinaison ABSOLUE
## (le code en déduit les rotations relatives). La hauteur du bassin découle
## du point le plus bas du corps (_low_point) : posé au sol, jamais enfoncé.
const DOWN_PELVIS := -0.3
const DOWN_SPINE := -0.35
const DOWN_CHEST := -0.25
const DOWN_THIGH_R := -1.57
const DOWN_SHIN_R := -1.54
const DOWN_THIGH_L := -2.05
const DOWN_SHIN_L := -1.05
## Genou gauche relevé un peu écarté (rotation Z, vers l'extérieur).
const DOWN_SPREAD_L := 0.22
## Bras gauche d'appui (absolu) : main au sol, en arrière et sur le côté.
const DOWN_SUPPORT := 0.75
const DOWN_SUPPORT_OUT := 0.3
## Bras droit (absolu) à l'horizontale, pistolet vers le regard.
const DOWN_AIM := -1.62
## Genoux repliés (mur ou marche juste devant les pieds).
const TUCK_THIGH := -2.45
const TUCK_SHIN := -0.45
## Mort : couché sur le dos, jambes allongées, bras le long du corps.
const DEAD_PELVIS := -1.0
const DEAD_SPINE := -0.35
const DEAD_CHEST := -0.2
const DEAD_LEG := -1.56
## Mi-chemin de la chute (et du relevé) : accroupi, buste penché, genoux
## pliés (absolus).
const SQUAT_THIGH := -1.45
const SQUAT_SHIN := 0.65
const SQUAT_SPINE := 0.3
## Vitesse de la chute et du relevé (1/s : ~0,55 s, comme BO1).
const DOWN_RATE := 1.8
## Yeux du joueur à terre (m, échelle 1) : hauteur de la tête du modèle
## assis (caméra 1re personne, Player.downed_eye) ; le corps est avancé de
## DOWN_FWD pour que la tête soit au-dessus de la position du joueur (là où
## est sa caméra) : ce qu'il voit est ce que les autres voient.
const DOWN_EYE_Y := 0.7
const DOWN_FWD := 0.33
const TUCK_FWD := 0.12


## Matériau partagé des joueurs (la couleur d'équipe est un paramètre
## d'instance : un seul matériau pour tous).
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://assets/shaders/player_voxel.gdshader")
	return _material


## Modèle chargé ({mesh, overrides}) ; {} si le .glb manque.
static func model() -> Dictionary:
	return ZombieGlb.load_model(MODEL_PATH)


## Construit le joueur, zone d'équipe à la couleur `slot_color`
## (HudStyle.PLAYER_COLORS).
func build(slot_color: Color) -> void:
	var m := model()
	if m.is_empty():
		push_error("PlayerModel : %s introuvable" % MODEL_PATH)
		skel = RigBuilder.instantiate(ArrayMesh.new(), material())
	else:
		if _skin == null:
			var tmp := RigBuilder.build_skeleton(m.overrides)
			_skin = tmp.create_skin_from_rest_transforms()
			tmp.free()
		skel = RigBuilder.instantiate(m.mesh, material(), m.overrides, _skin)
	var mi := skel.get_node("Mesh") as MeshInstance3D
	mi.set_instance_shader_parameter("team_color", slot_color)
	# Le modèle regarde vers +Z ; le joueur vers -Z.
	skel.rotation.y = PI
	add_child(skel)
	bones = RigBuilder.bone_indices(skel)
	weapon_attach = BoneAttachment3D.new()
	weapon_attach.bone_name = "forearm_r"
	skel.add_child(weapon_attach)


## Couleur d'équipe affichée (tests, captures).
func team_color() -> Color:
	if skel == null:
		return Color.WHITE
	return (skel.get_node("Mesh") as MeshInstance3D).get_instance_shader_parameter("team_color")


## Dimensions du corps mesurées sur le modèle, dans le repère de repos de
## chaque os (y le long de l'os, z vers l'avant), pour poser le corps au sol
## (_low_point) : boîtes [y0, y1, z0, z1] du bassin, de la cuisse, du tibia
## (au-dessus de la cheville) et du pied (chaussure : moins de 10 cm du sol
## au repos), hauteur de la hanche sous le bassin et longueur de la cuisse.
## Repli : valeurs du soldat low-poly d'avant (modèle absent).
static func dims() -> Dictionary:
	if not _dims.is_empty():
		return _dims
	var d := {"hips": [-0.1, 0.1, -0.105, 0.105], "thigh": [-0.45, 0.01, -0.08, 0.08],
		"leg": [-0.44, 0.0, -0.065, 0.065], "foot": [-0.49, -0.41, -0.085, 0.165], "hip": -0.02, "thigh_len": 0.45}
	var m := model()
	if m.is_empty():
		_dims = d
		return _dims
	var rest := RigBuilder._rest_globals(m.overrides)
	var a := (m.mesh as ArrayMesh).surface_get_arrays(0)
	var pos: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var bi: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var box := {}
	for v in pos.size():
		var bname: String = RigBuilder.BONES[bi[v * 4]][0]
		var key := ""
		match bname:
			"hips":
				key = "hips"
			"thigh_l":
				key = "thigh"
			"shin_l":
				key = "foot" if pos[v].y < 0.1 else "leg"
		if key == "":
			continue
		var bone := "shin_l" if key in ["leg", "foot"] else ("thigh_l" if key == "thigh" else "hips")
		var p: Vector3 = pos[v] - (rest[bone] as Transform3D).origin
		if box.has(key):
			box[key] = [minf(box[key][0], p.y), maxf(box[key][1], p.y), minf(box[key][2], p.z), maxf(box[key][3], p.z)]
		else:
			box[key] = [p.y, p.y, p.z, p.z]
	for k in box:
		d[k] = box[k]
	d.hip = (m.overrides.get("thigh_l", Vector3(0, -0.02, 0)) as Vector3).y
	d.thigh_len = -(m.overrides.get("shin_l", Vector3(0, -0.45, 0)) as Vector3).y
	_dims = d
	return _dims


## Affiche l'arme tenue (id + amélioration). Ne reconstruit que si elle change.
func set_weapon(id: String, pap: bool) -> void:
	var key := "%s_%s" % [id, pap]
	if key == weapon_key:
		return
	weapon_key = key
	if weapon_model:
		weapon_model.queue_free()
		weapon_model = null
	if id == "" or not WeaponDB.exists(id):
		return
	weapon_model = WeaponModels.build(WeaponDB.stats(id).model, false, pap)
	# Dans la main : le canon suit l'avant-bras tendu vers l'avant.
	weapon_model.position = Vector3(0, -0.3, 0.05)
	weapon_model.rotation = Vector3(-PI * 0.5, PI, 0)
	weapon_attach.add_child(weapon_model)


func fire_kick() -> void:
	_recoil = 1.0


func _q(x: float, y := 0.0, z := 0.0) -> Quaternion:
	return Quaternion.from_euler(Vector3(x, y, z))


## Anime le squelette. `speed` m/s, `pitch` regard (rad), `flags` =
## Player.FLAG_* ; `reviving` : réanime un coéquipier à terre.
func animate(delta: float, speed: float, pitch: float, flags: int, downed: bool, dead: bool, reviving := false) -> void:
	if skel == null:
		return
	# Mort et déjà posé au même endroit : pose finale inchangée (elle ne
	# dépend plus du regard ni de la vitesse), aucun calcul ni rayon.
	if dead and _dead_settled and is_inside_tree() and global_position.is_equal_approx(_settled_at):
		return
	_dead_settled = false
	var crouch := flags & Player.FLAG_CROUCH != 0
	var sprint := flags & Player.FLAG_SPRINT != 0
	_down_k = move_toward(_down_k, 1.0 if (downed or dead) else 0.0, delta * DOWN_RATE)
	_dead_k = move_toward(_dead_k, 1.0 if dead else 0.0, delta * 1.5)
	var move_k := clampf(speed / 4.0, 0.0, 1.6)
	_phase += delta * (2.0 + speed * 1.7)
	var s := sin(_phase)
	var c := cos(_phase)
	var leg := (0.45 if not sprint else 0.8) * move_k
	var hips_drop := 0.35 if crouch else 0.0
	_recoil = maxf(_recoil - delta * 8.0, 0.0)

	# Allongé / plongeon : le corps bascule à plat ventre, tête vers l'avant.
	var flat := flags & (Player.FLAG_PRONE | Player.FLAG_DIVE) != 0 and not (downed or dead)
	var dive := flags & Player.FLAG_DIVE != 0
	_prone_k = move_toward(_prone_k, 1.0 if flat else 0.0, delta * (7.0 if dive else 3.5))
	var pk := _prone_k
	if pk > 0.0:
		crouch = false
		leg *= 0.3
		hips_drop = 0.0

	# Debout (marche, course, accroupi, allongé) : rotations relatives.
	var hips_y := 0.95 - hips_drop + absf(c) * 0.03 * move_k * (1.0 - pk)
	var knee := 0.6 if crouch else 0.0
	var kick := 0.5 if dive else 0.0  # jambes repliées en plein vol
	var pelvis := 0.0
	var thigh_l := s * leg - knee - kick * 0.3
	var thigh_r := -s * leg - knee - kick * 0.2
	var shin_l := -maxf(0.0, -c) * leg * 1.2 + knee * 1.8 + kick
	var shin_r := -maxf(0.0, c) * leg * 1.2 + knee * 1.8 + kick * 0.6
	var spread_l := 0.0
	var spread_r := 0.0
	var lean := lerpf(0.05 + (0.3 if sprint else 0.0), 0.0, pk)
	var spine := lean - pitch * 0.3 * (1.0 - pk)
	var chest := -pitch * 0.35 * (1.0 - pk)
	# Allongé, la tête se redresse pour regarder devant.
	var head := lerpf(-pitch * 0.35, -1.15 - pitch * 0.3, pk)
	# Bras : arme épaulée (tendue vers l'avant), balancée en sprint ; allongé,
	# bras tendus dans l'axe du corps.
	# Visée : arme épaulée, bras tendus, tête penchée sur la crosse ; sinon
	# arme tenue plus bas, coudes pliés, canon à l'horizontale (prête à
	# tirer ; des bras tendus à l'arrêt rappelleraient un zombie).
	_aim_k = move_toward(_aim_k, 1.0 if flags & Player.FLAG_AIM != 0 else 0.0, delta * 6.0)
	var ak := _aim_k * (1.0 - pk)
	var aim_arm := lerpf(-1.0, -1.5, _aim_k) - pitch * 0.3 + _recoil * 0.25
	var bend := lerpf(-0.45, -0.05, _aim_k)
	head += 0.12 * ak
	if sprint:
		aim_arm = -0.7 + s * 0.3
	aim_arm = lerpf(aim_arm, -2.75 - pitch * 0.2 + _recoil * 0.2, pk)
	bend = lerpf(bend, -0.1, pk)
	var arm_r := Vector3(aim_arm, 0.0, 0.1)
	var forearm_r := bend
	var arm_l := Vector3(aim_arm + 0.1, 0.0, lerpf(-0.55, -0.35, pk))
	var forearm_l := Vector3(-0.8 + bend * 0.6, 0.0, 0.3)
	# Réanimation d'un coéquipier : accroupi, buste penché vers le blessé,
	# bras tendus vers le sol devant soi (arme baissée).
	_revive_k = move_toward(_revive_k, 1.0 if reviving and not (downed or dead) else 0.0, delta * 4.0)
	var rk := smoothstep(0.0, 1.0, _revive_k) * (1.0 - pk)
	if rk > 0.0:
		hips_y = lerpf(hips_y, 0.95 - 0.38, rk)
		thigh_l = lerpf(thigh_l, -1.2, rk)
		thigh_r = lerpf(thigh_r, -0.25, rk)
		shin_l = lerpf(shin_l, 1.2, rk)
		shin_r = lerpf(shin_r, 1.75, rk)
		spine = lerpf(spine, 0.45, rk)
		chest = lerpf(chest, 0.2, rk)
		head = lerpf(head, -0.2, rk)
		arm_r = arm_r.lerp(Vector3(-0.55, 0.0, 0.15), rk)
		arm_l = arm_l.lerp(Vector3(-0.6, 0.0, -0.2), rk)
		forearm_r = lerpf(forearm_r, -0.3, rk)
		forearm_l = forearm_l.lerp(Vector3(-0.3, 0.0, 0.0), rk)

	var dk := _down_k
	if dk > 0.0:
		# À terre : chute en deux temps (debout -> accroupi -> assis).
		if is_visible_in_tree():
			_probe_ground(delta)
		var dd := _dead_k
		var tk := _tuck * (1.0 - dd)
		var e := smoothstep(0.0, 1.0, dk)
		# En rampant, les jambes poussent tour à tour.
		var sv := s * clampf(speed / 0.6, 0.0, 1.0) * (1.0 - dd)
		var d_spine := lerpf(DOWN_SPINE, DEAD_SPINE, dd)
		var d_chest := lerpf(DOWN_CHEST, DEAD_CHEST, dd)
		var d_tr := lerpf(lerpf(DOWN_THIGH_R - 0.35 * maxf(sv, 0.0), TUCK_THIGH, tk), DEAD_LEG, dd)
		var d_sr := lerpf(lerpf(DOWN_SHIN_R + 0.7 * maxf(sv, 0.0), TUCK_SHIN, tk), DEAD_LEG, dd)
		var d_tl := lerpf(lerpf(DOWN_THIGH_L + 0.35 * maxf(-sv, 0.0), TUCK_THIGH, tk), DEAD_LEG, dd)
		var d_sl := lerpf(lerpf(DOWN_SHIN_L - 0.5 * maxf(-sv, 0.0), TUCK_SHIN, tk), DEAD_LEG, dd)
		var d_pel := lerpf(DOWN_PELVIS, DEAD_PELVIS, dd)
		var d_chest_abs := d_pel + d_spine + d_chest
		# Inclinaisons absolues -> rotations relatives (le bassin porte les cuisses).
		pelvis = _blend3(0.0, 0.0, d_pel, dk)
		spine = _blend3(spine, SQUAT_SPINE, d_spine, dk)
		chest = _blend3(chest, 0.0, d_chest, dk)
		thigh_l = _blend3(thigh_l, SQUAT_THIGH, d_tl - d_pel, dk)
		thigh_r = _blend3(thigh_r, SQUAT_THIGH, d_tr - d_pel, dk)
		shin_l = _blend3(shin_l, SQUAT_SHIN - SQUAT_THIGH, d_sl - d_tl, dk)
		shin_r = _blend3(shin_r, SQUAT_SHIN - SQUAT_THIGH, d_sr - d_tr, dk)
		spread_l = DOWN_SPREAD_L * (1.0 - dd) * e
		spread_r = -0.06 * e
		# Tête dans l'axe du regard (mort : face au ciel).
		var d_head := lerpf(clampf(-pitch * 0.85, -0.8, 0.9) - d_chest_abs, -0.1, dd)
		head = lerpf(head, d_head, e)
		# Bras droit tendu vers le regard (le pistolet relève au tir) ; mort :
		# le long du corps.
		var d_aim := clampf(DOWN_AIM - pitch * 0.95, -2.6, -0.85) - _recoil * 0.2 - d_chest_abs
		arm_r = arm_r.lerp(Vector3(lerpf(d_aim, 0.15, dd), 0.0, lerpf(0.2, -0.35, dd)), e)
		forearm_r = lerpf(forearm_r, lerpf(-0.12, 0.0, dd), e)
		# Bras gauche : appui, main à plat au sol derrière la hanche.
		var d_sup := lerpf(DOWN_SUPPORT - d_chest_abs, 0.15, dd)
		arm_l = arm_l.lerp(Vector3(d_sup, 0.0, lerpf(DOWN_SUPPORT_OUT, 0.35, dd)), e)
		forearm_l = forearm_l.lerp(Vector3(-0.05, 0.0, 0.0), e)
		# Bassin posé : le point le plus bas du corps touche le sol (passage
		# rapide depuis la hauteur debout pour ne pas sauter d'un coup).
		var contact := -_low_point(pelvis, pelvis + thigh_l, pelvis + thigh_l + shin_l, pelvis + thigh_r, pelvis + thigh_r + shin_r)
		hips_y = lerpf(hips_y, contact, clampf(dk * 5.0, 0.0, 1.0))
	else:
		_tuck = 0.0
		_floor_n = Vector3.UP
		_tuck_target = 0.0
		_floor_target = Vector3.UP
		_probe_age = INF  # prochaine chute : mesure dès la première image

	skel.set_bone_pose_position(bones.hips, Vector3(0, hips_y, 0))
	skel.set_bone_pose_rotation(bones.hips, _q(pelvis))
	skel.set_bone_pose_rotation(bones.thigh_l, _q(thigh_l, 0.0, spread_l))
	skel.set_bone_pose_rotation(bones.thigh_r, _q(thigh_r, 0.0, spread_r))
	skel.set_bone_pose_rotation(bones.shin_l, _q(shin_l))
	skel.set_bone_pose_rotation(bones.shin_r, _q(shin_r))
	skel.set_bone_pose_rotation(bones.spine, _q(spine))
	skel.set_bone_pose_rotation(bones.chest, _q(chest))
	skel.set_bone_pose_rotation(bones.head, _q(head))
	skel.set_bone_pose_rotation(bones.arm_r, _q(arm_r.x, arm_r.y, arm_r.z))
	skel.set_bone_pose_rotation(bones.forearm_r, _q(forearm_r))
	skel.set_bone_pose_rotation(bones.arm_l, _q(arm_l.x, arm_l.y, arm_l.z))
	skel.set_bone_pose_rotation(bones.forearm_l, _q(forearm_l.x, forearm_l.y, forearm_l.z))
	var body_x := PI * 0.5 * pk if pk > 0.0 else 0.0
	_body_x = lerpf(_body_x, body_x, 1.0 - exp(-delta * (30.0 if pk > 0.0 else 6.0)))
	# Allongé : pivot aux pieds, on recentre le corps sur la position du
	# joueur. À terre : corps avancé, tête au-dessus de la position (et de la
	# caméra) du joueur ; en pente, le corps épouse le sol.
	var fwd := lerpf(DOWN_FWD, TUCK_FWD, _tuck) * smoothstep(0.0, 1.0, dk)
	var pos := Vector3(0.0, 0.16 * pk, 0.85 * pk - fwd)
	var tilt := Basis.IDENTITY
	if dk > 0.0:
		tilt = Basis(Quaternion(Vector3.UP, Vector3.UP.lerp(_floor_n, dk).normalized()))
	skel.transform = Transform3D(tilt * Basis.from_euler(Vector3(_body_x, PI, 0.0)), tilt * pos)
	# Mort, pose finale atteinte (chute finie, sol et jambes stabilisés) : les
	# images suivantes n'ont plus rien à faire (voir le début d'animate).
	if dead and _dead_k >= 1.0 and _down_k >= 1.0 and is_inside_tree() and is_settled(_floor_n, _floor_target, _tuck, _tuck_target, _body_x):
		_dead_settled = true
		_settled_at = global_position


## Réapparition : pose debout immédiate (aucune transition depuis la pose à
## terre ou « mort ») ; la prochaine image d'animate pose le squelette.
func reset_pose() -> void:
	_down_k = 0.0
	_dead_k = 0.0
	_prone_k = 0.0
	_revive_k = 0.0
	_aim_k = 0.0
	_body_x = 0.0
	_recoil = 0.0
	_tuck = 0.0
	_tuck_target = 0.0
	_floor_n = Vector3.UP
	_floor_target = Vector3.UP
	_probe_age = INF
	_dead_settled = false
	if skel:
		animate(0.0, 0.0, 0.0, 0, false, false)


## Valeurs lissées arrivées à leurs cibles (pose figée). Pure (tests).
static func is_settled(floor_n: Vector3, floor_target: Vector3, tuck: float, tuck_target: float, body_x: float) -> bool:
	return floor_n.dot(floor_target) > 0.99999 and absf(tuck - tuck_target) < 0.001 and absf(body_x) < 0.0001


## Hauteur des yeux du joueur à terre (m, repère du joueur) : celle de la
## tête du modèle assis.
func downed_eye_height() -> float:
	return DOWN_EYE_Y


## Chute à terre en deux temps : `a` (debout) -> `b` (accroupi) à mi-course,
## puis -> `c` (assis) ; le relevé fait le chemin inverse.
static func _blend3(a: float, b: float, c: float, k: float) -> float:
	if k < 0.5:
		return lerpf(a, b, smoothstep(0.0, 0.5, k))
	return lerpf(b, c, smoothstep(0.5, 1.0, k))


## Point le plus bas d'une pièce rectangulaire (repère de son os : y de y0 à
## y1 le long de l'os, z de z0 à z1) inclinée de `a` autour de X.
static func _box_low(y0: float, y1: float, z0: float, z1: float, a: float) -> float:
	var ca := cos(a)
	var sa := sin(a)
	return minf(minf(y0 * ca - z0 * sa, y0 * ca - z1 * sa), minf(y1 * ca - z0 * sa, y1 * ca - z1 * sa))


## Point le plus bas du corps sous l'os du bassin (repère du squelette) :
## bassin incliné de `p`, cuisses et tibias d'inclinaisons absolues `tl`,
## `sl`, `tr`, `sr` (boîtes mesurées sur le modèle : dims()).
static func _low_point(p: float, tl: float, sl: float, tr: float, sr: float) -> float:
	var d := dims()
	var hb: Array = d.hips
	var low := _box_low(hb[0], hb[1], hb[2], hb[3], p)
	var hip: float = d.hip * cos(p)
	# Deux jambes, sans tableau temporaire (appelé à chaque image à terre).
	return minf(low, minf(_leg_low(d, hip, tl, sl), _leg_low(d, hip, tr, sr)))


## Point le plus bas d'une jambe (cuisse `t`, tibia et pied `sh`) sous la
## hanche à la hauteur `hip`.
static func _leg_low(d: Dictionary, hip: float, t: float, sh: float) -> float:
	var knee_y: float = hip - d.thigh_len * cos(t)
	var th: Array = d.thigh
	var lg: Array = d.leg
	var ft: Array = d.foot
	var low := hip + _box_low(th[0], th[1], th[2], th[3], t)
	low = minf(low, knee_y + _box_low(lg[0], lg[1], lg[2], lg[3], sh))
	return minf(low, knee_y + _box_low(ft[0], ft[1], ft[2], ft[3], sh))


## À terre : normale du sol sous le joueur (le corps assis épouse une pente)
## et obstacle devant les pieds (mur, marche : genoux repliés).
func _probe_ground(delta: float) -> void:
	var world := get_world_3d()
	if world == null:
		return
	var xf := global_transform
	_probe_age += delta
	if needs_probe(_probe_xf, xf, _probe_age):
		_measure_ground(world.direct_space_state, xf)
	_floor_n = _floor_n.slerp(_floor_target, 1.0 - exp(-delta * 8.0)).normalized()
	_tuck = move_toward(_tuck, _tuck_target, delta * 2.5)


## Faut-il relancer les rayons ? Corps déplacé (2 cm) ou tourné (~2,5°)
## depuis la dernière mesure `last`, ou mesure plus vieille que
## PROBE_INTERVAL (porte qui s'ouvre, barricade...). Pure (tests).
static func needs_probe(last: Transform3D, now: Transform3D, age: float) -> bool:
	return age >= PROBE_INTERVAL or last.origin.distance_squared_to(now.origin) > 0.0004 \
		or last.basis.z.normalized().dot(now.basis.z.normalized()) < 0.999


## Mesure : normale du sol sous le joueur, obstacle devant les pieds.
func _measure_ground(space: PhysicsDirectSpaceState3D, xf: Transform3D) -> void:
	_probe_xf = xf
	_probe_age = 0.0
	if _ground_q == null:
		var ex: Array[RID] = []
		var body := get_parent() as CollisionObject3D
		if body:
			ex.append(body.get_rid())
		_ground_q = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.DOWN, 1, ex)
		_front_q = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.FORWARD, 1, ex)
	var o := xf.origin
	_ground_q.from = o + Vector3.UP * 0.4
	_ground_q.to = o + Vector3.DOWN * 0.5
	var hit := space.intersect_ray(_ground_q)
	var n := Vector3.UP
	if not hit.is_empty() and (hit.normal as Vector3).angle_to(Vector3.UP) < 0.6:
		n = hit.normal
	_floor_target = (xf.basis.orthonormalized().inverse() * n).normalized()
	# Devant les pieds, parallèlement au sol, à hauteur de mollet (une marche
	# d'escalier de 12 cm et plus replie les jambes).
	var f := -xf.basis.z.normalized()
	f = (f - n * f.dot(n)).normalized()
	_front_q.from = o + n * 0.1
	var reach := 1.45
	_front_q.to = _front_q.from + f * reach
	var hit2 := space.intersect_ray(_front_q)
	var d := reach if hit2.is_empty() else _front_q.from.distance_to(hit2.position)
	_tuck_target = clampf((reach - 0.05 - d) / 0.6, 0.0, 1.0)
