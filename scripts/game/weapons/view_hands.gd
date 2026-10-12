class_name ViewHands
extends Node3D
## Mains et avant-bras de la vue FPS, en CUBES de 2,5 cm (GAME_CONCEPT §4.19) :
## ceux du joueur de baseball, personnage unique du jeu (§3), avec la palette
## de son modèle vu par les autres (PlayerModel) : gants de frappe sombres à
## paume de cuir, poignet nu, sous-maillot à manches longues, manche courte
## crème du maillot (équipe fictive, sans logo), bandage ensanglanté à
## l'avant-bras gauche. Bracelets des gants, sous-maillot et liseré de la
## manche forment la ZONE D'ÉQUIPE (matière « team ») : ils prennent la
## couleur du joueur (HudStyle.PLAYER_COLORS, WeaponModels.team_material),
## comme sur son modèle vu par les autres. Modèle :
## assets/models/weapons/voxel/hands.glb (tools/blender/weapons/weapons_voxel.py),
## une pièce par nœud « hand__<pièce> », chacune dans son repère :
##   * poings (grip : main droite, index sur la détente ; foregrip, knife :
##     main gauche) autour d'un manche vertical (axe Y, colonne x = 0,
##     z de -2,5 à +2,5 cm), poing sous y = 0 ;
##   * pistol_support : main gauche qui enveloppe le poing droit ;
##   * cradle : paume sous un garde-main (origine : milieu du dessous), doigts
##     sur le flanc droit, pouce à gauche ; cradle_narrow : le même pour le
##     garde-main étroit d'une arme fine (info « narrow_support ») ;
##   * throw_r / throw_l : main du lancer (grenade centrée) et pince ;
##   * bat_r / bat_l : poings serrés sur un manche d'un cube (batte) ;
##   * forearm / forearm_l (bandage) : du coude (z = 0) au poignet
##     (z = -ARM_LEN), manche du maillot derrière le coude.
## Chaque pièce est rigide (cubes) : elle se place et tourne librement, sans
## jamais être étirée. Pièces partagées par toutes les armes, placées par
## transformations selon les ancres de l'arme (WeaponModels).
##
## Main gauche mobile (rechargement) : `left_pose` (repère de l'arme) déplace
## la main ; son avant-bras suit, du coude (qui bouge en partie) au poignet.

## Coude gauche et droit en repère de l'arme, par rapport à la main.
const ELBOW_R := Vector3(0.11, -0.24, 0.34)
const ELBOW_L := Vector3(-0.16, -0.2, 0.3)
## Coudes en repère de la CAMÉRA (arme tenue de biais, info « elbows_cam » :
## batte) : ramenés dans le repère de l'arme par sa pose de repos.
const ELBOW_R_CAM := Vector3(0.14, -0.3, 0.2)
const ELBOW_L_CAM := Vector3(-0.06, -0.32, 0.22)
## Longueur de l'avant-bras, du coude au poignet (12 cubes).
const ARM_LEN := 0.3
## La manche continue derrière le coude (haut du bras) sur cette fraction de
## l'avant-bras : son bout sort toujours de l'écran (jamais un bras coupé
## qui flotte, même quand la main gauche descend au rechargement).
const SLEEVE_BACK := 0.9
## Pièces du modèle des mains.
const PIECES := ["grip", "pistol_support", "foregrip", "cradle", "cradle_narrow", "forearm", "forearm_l", "knife", "throw_r", "throw_l", "bat_r", "bat_l"]

var hand_r: Node3D
var hand_l: Node3D
var arm_l: Node3D
## Pose animée de la main gauche (repère de l'arme, appliquée au repos).
var left_pose := Transform3D.IDENTITY
var _wrist_l := Vector3.ZERO
var _elbow_l := Vector3.ZERO

## Couleur du joueur portée par la zone d'équipe des mains construites.
var team_color: Color = HudStyle.player_color(0)

## pièce -> {matériau: ArrayMesh} (partagés par tous les joueurs ; la couleur
## d'équipe est dans le matériau)
static var _cache: Dictionary = {}


## Poignet de la pièce `piece_name` dans son repère (m) : là où l'avant-bras
## s'attache.
static func wrist(piece_name: String) -> Vector3:
	return WeaponModels.anchor(WeaponModels.HANDS, "wrist_" + piece_name)


## Maillages d'une pièce (cache ; calculée ici si le préchargement ne l'a
## pas encore fournie).
static func piece(piece_name: String) -> Dictionary:
	if _cache.has(piece_name):
		return _cache[piece_name]
	var arr: Variant = WeaponModels.take_arrays("hand|" + piece_name)
	if arr == null:
		WeaponModels.raw(WeaponModels.HANDS)
		arr = piece_arrays(piece_name)
	var out := {}
	for mk in arr:
		out[mk] = WeaponMesh.Acc.make_mesh(arr[mk])
	_cache[piece_name] = out
	return out


## Nœud d'une pièce, placé par `xf`, zone d'équipe à la couleur `team`.
static func piece_node(piece_name: String, team: Color, xf := Transform3D.IDENTITY) -> Node3D:
	var root := Node3D.new()
	root.name = piece_name
	root.transform = xf
	var meshes := piece(piece_name)
	for mk in meshes:
		var mi := MeshInstance3D.new()
		mi.name = mk
		mi.mesh = meshes[mk]
		mi.material_override = WeaponModels.team_material(team, true) if mk == "team" else WeaponModels.material(mk, true)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 1.0
		root.add_child(mi)
	return root


## Transformation de l'avant-bras RIGIDE (cubes jamais étirés) : son poignet
## (z = -ARM_LEN du maillage) sur `wrist`, orienté du coude `elbow` vers le
## poignet ; le coude réel est donc à ARM_LEN du poignet sur cette droite.
static func arm_xf(elbow: Vector3, wrist_at: Vector3) -> Transform3D:
	var d := wrist_at - elbow
	if d.length() < 0.01:
		return Transform3D(Basis.IDENTITY, wrist_at + Vector3(0, 0, ARM_LEN))
	var dn := d.normalized()
	var up := Vector3.UP if absf(dn.y) < 0.95 else Vector3.RIGHT
	return Transform3D(Basis.looking_at(dn, up), wrist_at - dn * ARM_LEN)


## Construit les mains pour le modèle `mid`, zone d'équipe à la couleur
## `team` (couleur du joueur).
func setup(mid: String, team: Color) -> void:
	team_color = team
	for c in get_children():
		c.queue_free()
	var grip := WeaponModels.anchor(mid, "grip")
	var support := WeaponModels.anchor(mid, "support")
	var ga := float(WeaponModels.info(mid, "grip_angle", 0.0))
	var elbow_r := grip + ELBOW_R
	var elbow_l_off := ELBOW_L
	if WeaponModels.info(mid, "elbows_cam", false):
		# Arme tenue de biais (batte) : coudes posés dans le repère de la caméra.
		var inv := ViewModel.rest_transform(mid, 0.0).basis.inverse()
		elbow_r = grip + inv * ELBOW_R_CAM
		elbow_l_off = inv * ELBOW_L_CAM
	# Arme à manche fin tenue à deux poings (batte) : poings « bat_r » / « bat_l ».
	var stick: bool = WeaponModels.info(mid, "support_fist", false)
	# Main droite : poing fermé sur la poignée, avant-bras vers le bas-droite.
	var gxf := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(ga)), grip)
	var rname := "bat_r" if stick else "grip"
	hand_r = Node3D.new()
	hand_r.name = "HandR"
	add_child(hand_r)
	hand_r.add_child(piece_node(rname, team, gxf))
	hand_r.add_child(piece_node("forearm", team, arm_xf(elbow_r, gxf * wrist(rname))))
	# Main gauche : sur le garde-main, la poignée avant ou la main droite.
	var lxf: Transform3D
	var pname := "cradle"
	var pistol: bool = support.z > grip.z - 0.08 and not stick
	if pistol:
		lxf = gxf
		pname = "pistol_support"
	elif stick:
		lxf = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(ga)), support)
		pname = "bat_l"
	elif WeaponModels.info(mid, "front_grip", false):
		lxf = Transform3D(Basis.IDENTITY, support)
		pname = "foregrip"
	else:
		lxf = Transform3D(Basis.IDENTITY, support)
		# Garde-main étroit d'une arme fine (3,75 cm) : berceau de deux cubes.
		if WeaponModels.info(mid, "narrow_support", false):
			pname = "cradle_narrow"
	_wrist_l = lxf * wrist(pname)
	if WeaponModels.info(mid, "elbows_cam", false):
		_elbow_l = support + elbow_l_off
	else:
		_elbow_l = _wrist_l + (elbow_l_off - Vector3(-0.03, -0.022, 0.055)) * (0.8 if pistol else 1.0)
	hand_l = Node3D.new()
	hand_l.name = "HandL"
	add_child(hand_l)
	hand_l.add_child(piece_node(pname, team, lxf))
	arm_l = piece_node("forearm_l", team)
	arm_l.name = "ArmL"
	add_child(arm_l)
	left_pose = Transform3D.IDENTITY
	update_arm()


## Place la main gauche (left_pose) et oriente son avant-bras du coude au poignet.
func update_arm() -> void:
	if hand_l == null:
		return
	hand_l.transform = left_pose
	# Le coude suit en partie la main (le bras entier descend vers la
	# cartouchière) : le bout de la manche reste hors champ.
	arm_l.transform = arm_xf(_elbow_l + left_pose.origin * 0.8, left_pose * _wrist_l)


## Main gauche serrée sur le manche d'un couteau (axe Z, lame vers -Z, origine
## au manche) et son avant-bras, pour le coup de couteau.
static func knife_hand(team: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "KnifeHand"
	var xf := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-90.0)), Vector3.ZERO)
	root.add_child(piece_node("knife", team, xf))
	root.add_child(piece_node("forearm_l", team, arm_xf(Vector3(-0.06, -0.14, 0.34), xf * wrist("knife"))))
	return root


## Main du lancer (repère de ThrowView) : droite refermée sur la grenade
## (centrée à l'origine), ou gauche en pince (goupille).
static func throw_hand(team: Color, left: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "ThrowHand"
	if left:
		var xf := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-60.0)), Vector3(0, -0.02, 0.02))
		root.add_child(piece_node("throw_l", team, xf))
		root.add_child(piece_node("forearm_l", team, arm_xf(Vector3(-0.12, -0.26, 0.3), xf * wrist("throw_l"))))
	else:
		var xf := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-20.0)), Vector3.ZERO)
		root.add_child(piece_node("throw_r", team, xf))
		root.add_child(piece_node("forearm", team, arm_xf(Vector3(0.1, -0.22, 0.3), xf * wrist("throw_r"))))
	return root


# --------------------------------------------------------------------------
# Géométrie (données pures : peut tourner hors du fil principal, une fois
# WeaponModels.raw(HANDS) lu)

## Tableaux {matériau: [sommets, normales, couleurs]} d'une pièce, en repère
## local (poing : manche d'axe Y à l'origine ; avant-bras : du coude en 0 au
## poignet en -Z, longueur ARM_LEN). Avant-bras découpé en tranches (joue de
## visée : ViewModel.bend, voir WeaponMesh.slice_z).
static func piece_arrays(piece_name: String) -> Dictionary:
	if not ThreadGuard.worker():
		WeaponModels.raw(WeaponModels.HANDS)
	var src: Dictionary = WeaponModels._raw_cache.get(WeaponModels.HANDS, {}).get(piece_name, {})
	var out := {}
	for k in src:
		out[k] = src[k]
		if piece_name.begins_with("forearm"):
			out[k] = WeaponMesh.slice_z(src[k], -ARM_LEN - 0.01, 0.02)
	return out
