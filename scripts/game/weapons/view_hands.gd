class_name ViewHands
extends Node3D
## Mains, gants et avant-bras de la vue FPS (comme les « viewhands » de BO1) :
## la main droite enserre la poignée (index sur la détente, pouce par-dessus),
## la main gauche soutient le garde-main (doigts remontant sur le flanc droit,
## pouce le long du flanc gauche), tient la poignée avant, ou recouvre la main
## droite sur un pistolet.
##
## Géométrie en PIÈCES partagées par toutes les armes (poing, main d'appui,
## avant-bras de longueur unité...), construites une fois par tenue (au besoin
## hors du fil principal, voir WeaponModels.precompute_async) et placées par
## de simples transformations selon les ancres de l'arme.
##
## Main gauche mobile (rechargement) : `left_pose` (repère de l'arme) déplace
## la main ; son avant-bras suit, du coude (fixe) au poignet.

## Tenues des quatre joueurs (comme les quatre personnages de Kino der Toten).
## Couleurs sRGB.
const STYLES := [
	# Prisonnier de guerre américain : manches kaki retroussées, mains nues sales.
	{"sleeve": Color(0.29, 0.27, 0.18), "cuff": Color(0.24, 0.22, 0.15), "hand": Color(0.42, 0.3, 0.22), "tip": Color(0.42, 0.3, 0.22), "rolled": true, "skin": true},
	# Bagnard russe : veste matelassée gris sombre, mitaines de laine.
	{"sleeve": Color(0.17, 0.17, 0.16), "cuff": Color(0.12, 0.12, 0.11), "hand": Color(0.2, 0.18, 0.16), "tip": Color(0.5, 0.38, 0.29), "rolled": false, "quilt": true},
	# Soldat japonais : veste olive, mains nues.
	{"sleeve": Color(0.25, 0.27, 0.16), "cuff": Color(0.2, 0.22, 0.13), "hand": Color(0.46, 0.34, 0.24), "tip": Color(0.46, 0.34, 0.24), "rolled": false, "skin": true},
	# Savant en combinaison de protection : toile jaunâtre, gants de caoutchouc noir.
	{"sleeve": Color(0.5, 0.45, 0.22), "cuff": Color(0.08, 0.08, 0.08), "hand": Color(0.06, 0.06, 0.06), "tip": Color(0.06, 0.06, 0.06), "rolled": false, "rubber": true},
]

## Coude gauche et droit en repère de l'arme, par rapport à la main.
const ELBOW_R := Vector3(0.11, -0.2, 0.34)
const ELBOW_L := Vector3(-0.16, -0.2, 0.3)
## Longueur du maillage d'avant-bras (étiré à la longueur voulue).
const ARM_LEN := 0.3
## Bout de l'index (détente) dans le repère de la poignée.
const TRIGGER := Vector3(0, 0.046, -0.056)
## Pièces d'une tenue.
const PIECES := ["grip", "pistol_support", "foregrip", "cradle", "forearm", "knife", "throw_r", "throw_l"]
## Modèles à poignée avant verticale (main gauche en poing).
const FRONT_GRIP := {"mp5k": true, "aug": true, "pm63": true, "thunder": true}

var hand_r: Node3D
var hand_l: Node3D
var arm_l: Node3D
## Pose animée de la main gauche (repère de l'arme, appliquée au repos).
var left_pose := Transform3D.IDENTITY
var _wrist_l := Vector3.ZERO
var _elbow_l := Vector3.ZERO

## "style|pièce" -> {matériau: ArrayMesh}
static var _cache: Dictionary = {}
static var _mats: Dictionary = {}


static func material(c: Color, rough: float, fabric := 0.0, metal := 0.0) -> ShaderMaterial:
	var key := "%s_%s_%s_%s" % [c, rough, fabric, metal]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/weapon.gdshader")
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("metallic", metal)
	m.set_shader_parameter("viewmodel", 1.0)
	m.set_shader_parameter("wear", 0.22)
	m.set_shader_parameter("fabric", fabric)
	m.set_shader_parameter("tone_var", 0.1)
	_mats[key] = m
	return m


static func style_materials(style: int) -> Dictionary:
	var s: Dictionary = STYLES[posmod(style, STYLES.size())]
	var hand_rough := 0.3 if s.get("rubber", false) else (0.7 if s.get("skin", false) else 0.85)
	return {
		"sleeve": material(s.sleeve, 0.95, 1.0),
		"cuff": material(s.cuff, 0.95, 0.6 if not s.get("rubber", false) else 0.0),
		"hand": material(s.hand, hand_rough, 0.0 if s.get("skin", false) or s.get("rubber", false) else 0.5),
		"tip": material(s.tip, 0.7),
	}


## Maillages d'une pièce (cache ; calculée ici si le préchargement ne l'a
## pas encore fournie).
static func piece(style: int, name: String) -> Dictionary:
	style = posmod(style, STYLES.size())
	var key := "%d|%s" % [style, name]
	if _cache.has(key):
		return _cache[key]
	var arr: Variant = WeaponModels.take_arrays("hand|" + key)
	if arr == null:
		arr = piece_arrays(style, name)
	var out := {}
	for mk in arr:
		out[mk] = WeaponMesh.Acc.make_mesh(arr[mk])
	_cache[key] = out
	return out


## Nœud d'une pièce, placé par `xf`.
static func piece_node(style: int, name: String, xf := Transform3D.IDENTITY) -> Node3D:
	var root := Node3D.new()
	root.name = name
	root.transform = xf
	var mats := style_materials(style)
	var meshes := piece(style, name)
	for mk in meshes:
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[mk]
		mi.material_override = mats[mk]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 1.0
		root.add_child(mi)
	return root


## Transformation qui étire le maillage d'avant-bras du coude au poignet.
static func arm_xf(elbow: Vector3, wrist: Vector3) -> Transform3D:
	var d := wrist - elbow
	if d.length() < 0.01:
		return Transform3D(Basis.IDENTITY, elbow)
	var up := Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT
	return Transform3D(Basis.looking_at(d, up).scaled_local(Vector3(1, 1, d.length() / ARM_LEN)), elbow)


## Construit les mains pour le modèle `mid` et la tenue `style`.
func setup(mid: String, style: int) -> void:
	for c in get_children():
		c.queue_free()
	var grip := WeaponModels.anchor(mid, "grip")
	var support := WeaponModels.anchor(mid, "support")
	var ga := float(WeaponModels.info(mid, "grip_angle", -14.0))
	# Main droite : poing fermé sur la poignée, avant-bras vers le bas-droite.
	var gxf := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(ga)), grip)
	hand_r = Node3D.new()
	hand_r.name = "HandR"
	add_child(hand_r)
	hand_r.add_child(piece_node(style, "grip", gxf))
	hand_r.add_child(piece_node(style, "forearm", arm_xf(grip + ELBOW_R, gxf * Vector3(0.008, -0.022, 0.05))))
	# Main gauche : sur le garde-main, la poignée avant ou la main droite.
	var lxf: Transform3D
	var pname := "cradle"
	var pistol := support.z > grip.z - 0.08
	if pistol:
		lxf = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(ga)), grip + Vector3(-0.004, -0.008, -0.004))
		pname = "pistol_support"
		_wrist_l = lxf * Vector3(-0.012, -0.02, 0.05)
	elif FRONT_GRIP.has(mid):
		lxf = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-8.0)), support + Vector3(0, 0.02, 0))
		pname = "foregrip"
		_wrist_l = lxf * Vector3(-0.01, -0.025, 0.045)
	else:
		lxf = Transform3D(Basis.IDENTITY, support)
		_wrist_l = support + Vector3(-0.03, -0.022, 0.055)
	_elbow_l = _wrist_l + (ELBOW_L - Vector3(-0.03, -0.022, 0.055)) * (0.8 if pistol else 1.0)
	hand_l = Node3D.new()
	hand_l.name = "HandL"
	add_child(hand_l)
	hand_l.add_child(piece_node(style, pname, lxf))
	arm_l = piece_node(style, "forearm")
	arm_l.name = "ArmL"
	add_child(arm_l)
	left_pose = Transform3D.IDENTITY
	update_arm()


## Place la main gauche (left_pose) et tend son avant-bras du coude au poignet.
func update_arm() -> void:
	if hand_l == null:
		return
	hand_l.transform = left_pose
	# Le coude suit en partie la main (le bras entier descend vers la
	# cartouchière) : le bout de la manche reste hors champ.
	arm_l.transform = arm_xf(_elbow_l + left_pose.origin * 0.8, left_pose * _wrist_l)


## Main gauche serrée sur le manche d'un couteau (axe Z, lame vers -Z, origine
## au milieu du manche) et son avant-bras, pour le coup de couteau.
static func knife_hand(style: int) -> Node3D:
	var root := Node3D.new()
	root.name = "KnifeHand"
	var xf := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-90.0)), Vector3(0, 0, 0.01))
	root.add_child(piece_node(style, "knife", xf))
	root.add_child(piece_node(style, "forearm", arm_xf(Vector3(-0.06, -0.14, 0.34), xf * Vector3(-0.012, -0.05, 0.01))))
	return root


## Main du lancer (repère de ThrowView) : droite refermée sur la grenade
## (centrée à l'origine), ou gauche en pince (goupille, clé du singe).
static func throw_hand(style: int, left: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "ThrowHand"
	if left:
		var xf := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-60.0)), Vector3(0, -0.02, 0.02))
		root.add_child(piece_node(style, "throw_l", xf))
		root.add_child(piece_node(style, "forearm", arm_xf(Vector3(-0.12, -0.26, 0.3), xf * Vector3(-0.012, -0.05, 0.02))))
	else:
		var xf := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-20.0)), Vector3(0.004, -0.012, 0.012))
		root.add_child(piece_node(style, "throw_r", xf))
		root.add_child(piece_node(style, "forearm", arm_xf(Vector3(0.1, -0.22, 0.3), xf * Vector3(0.012, -0.045, 0.04))))
	return root


# --------------------------------------------------------------------------
# Géométrie (données pures : peut tourner hors du fil principal)

## Tableaux {matériau: [sommets, normales, couleurs]} d'une pièce, en repère
## local (poing : manche d'axe Y à l'origine ; avant-bras : du coude en 0 au
## poignet en -Z, longueur ARM_LEN).
static func piece_arrays(style: int, name: String) -> Dictionary:
	var s: Dictionary = STYLES[posmod(style, STYLES.size())]
	var accs := {}
	for k in ["sleeve", "cuff", "hand", "tip"]:
		var a := WeaponMesh.Acc.new()
		a.seg = 10
		accs[k] = a
	match name:
		"grip": _fist(accs, 1.0, 0.018, 0.024, s, TRIGGER)
		"pistol_support": _fist(accs, -1.0, 0.03, 0.035, s, Vector3.ZERO)
		"foregrip": _fist(accs, -1.0, 0.017, 0.017, s, Vector3.ZERO)
		"cradle": _cradle(accs, 0.034, s)
		"forearm": _forearm(accs, Vector3.ZERO, Vector3(0, 0, -ARM_LEN), s)
		"knife": _fist(accs, -1.0, 0.013, 0.016, s, Vector3.ZERO)
		"throw_r": _fist(accs, 1.0, 0.024, 0.026, s, Vector3.ZERO)
		"throw_l": _fist(accs, -1.0, 0.008, 0.01, s, Vector3.ZERO)
	var out := {}
	for k in accs:
		if not accs[k].is_empty():
			out[k] = accs[k].arrays()
	return out


## Poing fermé autour d'un manche d'axe Y (section ±hx, ±hz) : dos de la main
## du côté `side` (1 : droite), doigts qui passent devant (-Z) et reviennent
## sur l'autre flanc, pouce par-dessus. `trig` : bout de l'index (ZERO : index
## replié avec les autres).
static func _fist(accs: Dictionary, side: float, hx: float, hz: float, s: Dictionary, trig: Vector3) -> void:
	var h: WeaponMesh.Acc = accs.hand
	var t: WeaponMesh.Acc = accs.tip
	var quilt: bool = s.get("quilt", false)
	# Paume et dos de la main : bloc arrondi sur le flanc et l'arrière du manche.
	h.xf = Transform3D(Basis.IDENTITY, Vector3(side * (hx + 0.006), 0.0, hz * 0.2))
	WeaponMesh.prism(h, WeaponMesh.round_rect(0.075, 0.078, 0.02, 3), 0.024, 0.009)
	# Talon de la main derrière le manche.
	h.xf = Transform3D(Basis.IDENTITY, Vector3(side * hx * 0.2, -0.012, hz + 0.008))
	WeaponMesh.prism(h, WeaponMesh.round_rect(0.022, 0.055, 0.009, 2), hx * 2.0 + 0.012, 0.008)
	h.xf = Transform3D.IDENTITY
	# Doigts : trois (ou quatre) phalanges qui enserrent le manche.
	var rows := [0.012, -0.007, -0.025, -0.042] if trig != Vector3.ZERO else [0.018, 0.0, -0.018, -0.036]
	var first := 1 if trig != Vector3.ZERO else 0
	for k in range(first, 4):
		var yy: float = rows[k]
		var r := 0.0079 - k * 0.0005
		var knuckle := Vector3(side * (hx + 0.012), yy, -hz * 0.35)
		var p1 := Vector3(side * (hx + 0.002), yy - 0.002, -hz - 0.012)
		var p2 := Vector3(-side * hx * 0.35, yy - 0.004, -hz - 0.013)
		var tip := Vector3(-side * (hx + 0.002), yy - 0.005, -hz * 0.35)
		WeaponMesh.capsule(h, knuckle, p1, r * 1.05, r)
		WeaponMesh.capsule(t if quilt else h, p1, p2, r, r * 0.95)
		WeaponMesh.capsule(t if quilt else h, p2, tip, r * 0.95, r * 0.85)
	# Index sur la détente.
	if trig != Vector3.ZERO:
		var knuckle := Vector3(side * (hx + 0.012), rows[0] + 0.012, -hz * 0.3)
		var p1 := Vector3(side * (hx + 0.006), rows[0] + 0.016, -hz - 0.018)
		var p2 := trig + Vector3(side * 0.012, 0.004, 0.004)
		WeaponMesh.capsule(h, knuckle, p1, 0.0082, 0.0078)
		WeaponMesh.capsule(t if quilt else h, p1, p2, 0.0078, 0.0072)
		WeaponMesh.capsule(t if quilt else h, p2, trig + Vector3(0.0, -0.002, 0.004), 0.0072, 0.0064)
	# Pouce : de la base de la paume, passe au-dessus et longe l'autre flanc.
	var tb := Vector3(side * (hx + 0.004), 0.03, hz * 0.7)
	var t1 := Vector3(side * hx * 0.2, 0.045, hz * 0.2)
	var t2 := Vector3(-side * (hx + 0.004), 0.04, -hz * 0.4)
	WeaponMesh.capsule(h, tb, t1, 0.0105, 0.009)
	WeaponMesh.capsule(t if quilt else h, t1, t2, 0.009, 0.0078)


## Main d'appui sous un garde-main (axe Z, appui à l'origine) : paume dessous,
## doigts qui remontent sur le flanc droit, pouce le long du flanc gauche.
static func _cradle(accs: Dictionary, hw: float, s: Dictionary) -> void:
	var h: WeaponMesh.Acc = accs.hand
	var t: WeaponMesh.Acc = accs.tip
	var quilt: bool = s.get("quilt", false)
	# Paume : dalle arrondie sous le garde-main, inclinée vers la gauche.
	h.xf = Transform3D(Basis(Vector3.BACK, deg_to_rad(-18.0)), Vector3(-0.006, 0.004, 0.0))
	WeaponMesh.prism(h, WeaponMesh.round_rect(0.08, 0.026, 0.011, 3), hw * 1.35, 0.01)
	h.xf = Transform3D.IDENTITY
	var zs := [-0.03, -0.011, 0.008, 0.026]
	for k in 4:
		var r := 0.0078 - absf(k - 1.2) * 0.0005
		var base := Vector3(hw * 0.55, 0.006, zs[k])
		var p1 := Vector3(hw + 0.006, 0.024, zs[k] - 0.002)
		var p2 := Vector3(hw + 0.002, 0.044, zs[k] - 0.004)
		var tip := Vector3(hw * 0.55, 0.058, zs[k] - 0.005)
		WeaponMesh.capsule(h, base, p1, r * 1.05, r)
		WeaponMesh.capsule(t if quilt else h, p1, p2, r, r * 0.95)
		WeaponMesh.capsule(t if quilt else h, p2, tip, r * 0.95, r * 0.85)
	# Pouce le long du flanc gauche, vers l'avant.
	WeaponMesh.capsule(h, Vector3(-hw * 0.8, 0.0, 0.03), Vector3(-hw - 0.006, 0.018, 0.0), 0.0105, 0.009)
	WeaponMesh.capsule(t if quilt else h, Vector3(-hw - 0.006, 0.018, 0.0), Vector3(-hw - 0.004, 0.03, -0.03), 0.009, 0.0078)


## Avant-bras du coude au poignet : poignet et manchette (gant), bras nu ou
## manche retroussée, puis manche.
static func _forearm(accs: Dictionary, elbow: Vector3, wrist: Vector3, s: Dictionary) -> void:
	var d := wrist - elbow
	var rolled: bool = s.get("rolled", false)
	var bare: bool = s.get("skin", false)
	# Profils [t (0 : coude, 1 : poignet), rayon].
	var sleeve_end := 0.45 if rolled else 0.78
	var fore := [[sleeve_end - 0.02, 0.036], [0.8, 0.031], [0.93, 0.024], [1.0, 0.021]]
	WeaponMesh.limb(accs.tip if bare else accs.hand, elbow, wrist, fore, 10, 0.85)
	# Manchette de gant (sauf mains nues) au poignet.
	if not bare:
		WeaponMesh.limb(accs.cuff if s.get("rubber", false) else accs.hand, elbow, elbow + d * 1.0,
			[[0.86, 0.029], [0.88, 0.031], [0.97, 0.027], [0.99, 0.024]], 10, 0.85)
	# Manche : ample, qui se resserre sur le bord (retroussée : gros bourrelet).
	var sl := [[0.0, 0.052], [sleeve_end - 0.1, 0.047], [sleeve_end - 0.02, 0.044], [sleeve_end, 0.038]]
	WeaponMesh.limb(accs.sleeve, elbow + d * -0.2, elbow + d * 1.0, _stretch(sl, -0.2), 10, 0.9)
	var cuff := [[sleeve_end - 0.09, 0.05], [sleeve_end - 0.07, 0.054], [sleeve_end - 0.01, 0.05], [sleeve_end + 0.005, 0.043]] if rolled \
		else [[sleeve_end - 0.04, 0.047], [sleeve_end - 0.03, 0.049], [sleeve_end + 0.005, 0.046], [sleeve_end + 0.01, 0.04]]
	WeaponMesh.limb(accs.cuff, elbow + d * -0.2, elbow + d * 1.0, _stretch(cuff, -0.2), 10, 0.9)
	if s.get("quilt", false):
		# Veste matelassée : bourrelets réguliers.
		for i in 4:
			var tq := 0.1 + i * 0.14
			WeaponMesh.limb(accs.sleeve, elbow + d * -0.2, elbow + d * 1.0, _stretch([[tq, 0.05], [tq + 0.02, 0.055], [tq + 0.06, 0.055], [tq + 0.08, 0.05]], -0.2), 10, 0.9)


## Profil exprimé de 0 (coude) à 1 (poignet) réexprimé sur un segment qui
## commence en t = `t0` (avant le coude).
static func _stretch(prof: Array, t0: float) -> Array:
	var out := []
	for q in prof:
		out.append([(float(q[0]) - t0) / (1.0 - t0), q[1]])
	return out

