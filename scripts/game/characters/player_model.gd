class_name PlayerModel
extends Node3D
## Soldat low-poly des joueurs vus par les autres (1 draw call + l'arme).
## Animations procédurales pilotées par l'état réseau : marche, course,
## accroupi, visée (le buste suit le regard), tir, joueur à terre.

const SKIN := Color(0.52, 0.4, 0.32)
## Peau claire (Berg, cohérente avec ses mains en vue FPS).
const SKIN_FAIR := Color(0.62, 0.48, 0.41)
const UNIFORM := Color(0.2, 0.22, 0.15)
const PANTS := Color(0.16, 0.17, 0.12)
const VEST := Color(0.12, 0.13, 0.1)
const HELMET := Color(0.17, 0.19, 0.13)
const BOOTS := Color(0.06, 0.05, 0.04)

static var _material: ShaderMaterial

var skel: Skeleton3D
var bones: Dictionary
var weapon_attach: BoneAttachment3D
var weapon_model: Node3D
var weapon_key := ""
var _phase := 0.0
var _recoil := 0.0
var _down_k := 0.0
var _prone_k := 0.0


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://assets/shaders/character.gdshader")
		_material.set_shader_parameter("grime", 0.25)
		_material.set_shader_parameter("stain_amount", 0.12)
		_material.set_shader_parameter("emission_energy", 0.0)
	return _material


## Tenues des sept personnages (CharacterDB, docs/CHARACTERS.md), cohérentes
## avec leurs mains en vue FPS (ViewHands.STYLES) :
## [veste, pantalon, manches (avant-bras), mains, coiffe].
const OUTFITS := [
	# Callahan : chemise kaki aux manches retroussées, casque M1 cabossé.
	[Color(0.42, 0.37, 0.25), Color(0.24, 0.25, 0.17), SKIN, SKIN, Color(0.2, 0.22, 0.15)],
	# Orlov : veste matelassée grise, mitaines de laine, chapka.
	[Color(0.27, 0.28, 0.27), Color(0.2, 0.2, 0.19), Color(0.27, 0.28, 0.27), Color(0.33, 0.3, 0.26), Color(0.3, 0.22, 0.14)],
	# Arakawa : veste olive boutonnée, mains nues, casquette à couvre-nuque.
	[Color(0.33, 0.32, 0.19), Color(0.3, 0.29, 0.18), Color(0.33, 0.32, 0.19), SKIN, Color(0.31, 0.3, 0.18)],
	# Weissmann : combinaison de protection jaunâtre, gants de caoutchouc noirs.
	[Color(0.55, 0.5, 0.32), Color(0.5, 0.46, 0.3), Color(0.55, 0.5, 0.32), Color(0.04, 0.04, 0.04), Color(0.55, 0.55, 0.55)],
	# Mercer : treillis olive à chevrons, manches retroussées (avant-bras nus),
	# casquette de treillis à huit pans.
	[Color(0.27, 0.3, 0.19), Color(0.24, 0.27, 0.17), SKIN, SKIN, Color(0.25, 0.28, 0.17)],
	# Berg : veste de terrain bleu canard sombre, pantalon taille haute,
	# peau claire ; « coiffe » = cheveux blond platine relevés.
	[Color(0.12, 0.3, 0.31), Color(0.25, 0.22, 0.18), Color(0.12, 0.3, 0.31), SKIN_FAIR, Color(0.94, 0.88, 0.7)],
	# Jojo : maillot de corps gris-blanc taché, pantalon de laine brun,
	# manches roulées (avant-bras nus), casquette plate en laine.
	[Color(0.72, 0.68, 0.58), Color(0.22, 0.18, 0.14), SKIN, SKIN, Color(0.3, 0.27, 0.22)],
]
## Taille de Berg (petite et mince) par rapport aux autres.
const BERG_SCALE := 0.92
## Taille de Jojo (une grosse brute d'une centaine de kilos).
const JOJO_SCALE := 1.1


func build(slot_color: Color, character := 0) -> void:
	var o: Array = OUTFITS[posmod(character, OUTFITS.size())]
	var jacket: Color = o[0]
	var pants: Color = o[1]
	var sleeve: Color = o[2]
	var hand: Color = o[3]
	var hat: Color = o[4]
	var fem := character == 5
	var fat := character == 6
	# Orlov : un gabarit au-dessus ; Mercer : trapu ; Berg : mince (et
	# plus petite : BERG_SCALE), épaules étroites, taille marquée ; Jojo :
	# énorme (et plus grand : JOJO_SCALE), gros ventre, cou de taureau.
	var big := 1.12 if character == 1 else (1.06 if character == 4 else (0.86 if fem else (1.2 if fat else 1.0)))
	var skin := SKIN_FAIR if fem else SKIN
	var p: Array = []
	p.append(["hips", Vector3(0.34 * (1.0 if fem else big), 0.2, 0.21), Vector3.ZERO, pants, 0.0])
	p.append(["spine", Vector3((0.28 if fem else 0.33 * big), 0.27, 0.21 * big), Vector3(0, 0.12, 0), jacket, 0.0])
	p.append(["chest", Vector3(0.42 * big, 0.3, 0.25 * big), Vector3(0, 0.1, 0), jacket, 0.0])
	p.append(["neck", Vector3(0.1 * (0.85 if fem else 1.0), 0.1, 0.1 * (0.85 if fem else 1.0)), Vector3(0, 0.03, 0), skin, 0.0])
	p.append(["head", Vector3(0.21 * (0.95 if fem else 1.0), 0.24, 0.22), Vector3(0, 0.13, 0), skin, 0.0])
	p.append(["head", Vector3(0.16, 0.03, 0.02), Vector3(0, 0.15, 0.112), Color(0.05, 0.05, 0.05), 0.0])
	match character:
		0:  # Callahan : casque, bandoulière, cigare, barbe de trois jours
			p.append(["head", Vector3(0.27, 0.13, 0.28), Vector3(0, 0.25, -0.01), hat, 0.0, Vector3(0, 0, 4)])
			p.append(["head", Vector3(0.29, 0.03, 0.31), Vector3(0, 0.19, 0.0), hat.darkened(0.2), 0.0])
			p.append(["chest", Vector3(0.07, 0.5, 0.03), Vector3(0, 0.08, 0.135), Color(0.3, 0.22, 0.12), 0.0, Vector3(0, 0, 38)])
			p.append(["head", Vector3(0.012, 0.012, 0.07), Vector3(0.04, 0.06, 0.14), Color(0.25, 0.16, 0.09), 0.0, Vector3(0, 20, 0)])
			p.append(["head", Vector3(0.18, 0.06, 0.02), Vector3(0, 0.05, 0.108), SKIN.darkened(0.25), 0.0])
		1:  # Orlov : chapka à rabats, barbe épaisse, piqûres de la veste matelassée
			p.append(["head", Vector3(0.28, 0.12, 0.27), Vector3(0, 0.27, -0.01), hat, 0.0])
			for side in [-1.0, 1.0]:
				p.append(["head", Vector3(0.04, 0.14, 0.13), Vector3(side * 0.125, 0.15, -0.01), hat, 0.0])
			p.append(["head", Vector3(0.2, 0.1, 0.06), Vector3(0, 0.04, 0.1), Color(0.18, 0.12, 0.08), 0.0])
			for y in [0.0, 0.1, 0.2]:
				p.append(["chest", Vector3(0.43 * big, 0.012, 0.26 * big), Vector3(0, y, 0), jacket.darkened(0.3), 0.0])
		2:  # Arakawa : casquette à couvre-nuque, lunettes rondes, sabre au côté
			p.append(["head", Vector3(0.23, 0.08, 0.24), Vector3(0, 0.27, 0.0), hat, 0.0])
			p.append(["head", Vector3(0.2, 0.02, 0.08), Vector3(0, 0.23, 0.14), hat.darkened(0.25), 0.0])
			p.append(["head", Vector3(0.22, 0.12, 0.02), Vector3(0, 0.18, -0.12), hat.lightened(0.1), 0.0])
			for side in [-1.0, 1.0]:
				p.append(["head", Vector3(0.05, 0.04, 0.012), Vector3(side * 0.045, 0.15, 0.116), Color(0.08, 0.08, 0.08), 0.0])
			p.append(["hips", Vector3(0.03, 0.8, 0.04), Vector3(0.2, -0.15, 0.05), Color(0.08, 0.07, 0.06), 0.0, Vector3(-55, 0, 8)])
			for y in [0.02, 0.12, 0.22]:
				p.append(["chest", Vector3(0.02, 0.02, 0.01), Vector3(0, y, 0.13), Color(0.6, 0.5, 0.25), 0.0])
		3:  # Weissmann : lunettes de labo sur le front, cheveux gris, sacoche, brassard de l'Institut
			p.append(["head", Vector3(0.23, 0.08, 0.23), Vector3(0, 0.26, -0.02), hat, 0.0])
			p.append(["head", Vector3(0.2, 0.05, 0.03), Vector3(0, 0.22, 0.11), Color(0.1, 0.1, 0.1), 0.0])
			for side in [-1.0, 1.0]:
				p.append(["head", Vector3(0.06, 0.045, 0.02), Vector3(side * 0.05, 0.22, 0.125), Color(0.55, 0.42, 0.16), 0.3])
			p.append(["hips", Vector3(0.16, 0.16, 0.08), Vector3(-0.2, -0.02, 0.06), Color(0.26, 0.17, 0.09), 0.0])
			p.append(["arm_l", Vector3(0.125, 0.07, 0.125), Vector3(0, -0.2, 0), Color(0.75, 0.72, 0.62), 0.0])
		4:  # Mercer : casquette à huit pans, tempes et barbe grises, plaques, poches de poitrine, manches roulées
			var grey := Color(0.5, 0.49, 0.47)
			p.append(["head", Vector3(0.235, 0.1, 0.24), Vector3(0, 0.27, 0.0), hat, 0.0])
			p.append(["head", Vector3(0.25, 0.025, 0.25), Vector3(0, 0.325, 0.0), hat.darkened(0.1), 0.0])
			p.append(["head", Vector3(0.2, 0.02, 0.07), Vector3(0, 0.23, 0.14), hat.darkened(0.25), 0.0])
			for side in [-1.0, 1.0]:
				p.append(["head", Vector3(0.014, 0.06, 0.05), Vector3(side * 0.106, 0.18, 0.02), grey, 0.0])
				p.append(["chest", Vector3(0.1, 0.08, 0.015), Vector3(side * 0.1, 0.13, 0.13 * big), jacket.darkened(0.15), 0.0])
			p.append(["head", Vector3(0.22, 0.05, 0.2), Vector3(0, 0.2, -0.03), grey, 0.0])
			p.append(["head", Vector3(0.18, 0.06, 0.02), Vector3(0, 0.05, 0.108), grey.darkened(0.2), 0.0])
			p.append(["chest", Vector3(0.03, 0.045, 0.01), Vector3(0, 0.2, 0.135 * big), Color(0.62, 0.62, 0.6), 0.3])
			for side in ["l", "r"]:
				p.append(["forearm_" + side, Vector3(0.1 * big, 0.05, 0.1 * big), Vector3(0, -0.01, 0), jacket.darkened(0.1), 0.0])
		5:  # Berg : cheveux platine en « victory rolls », rouge à lèvres, chemisier crème, sacoche, crayon
			var cream := Color(0.86, 0.82, 0.7)
			# Chevelure : calotte, deux rouleaux sur le dessus, chignon relevé à l'arrière.
			p.append(["head", Vector3(0.215, 0.07, 0.23), Vector3(0, 0.255, -0.01), hat, 0.0])
			p.append(["head", Vector3(0.21, 0.13, 0.05), Vector3(0, 0.17, -0.105), hat, 0.0])
			for side in [-1.0, 1.0]:
				p.append(["head", Vector3(0.075, 0.07, 0.15), Vector3(side * 0.055, 0.29, 0.03), hat.lightened(0.08), 0.0, Vector3(0, 0, side * -18.0)])
				p.append(["head", Vector3(0.02, 0.1, 0.12), Vector3(side * 0.104, 0.2, -0.03), hat, 0.0])
				# Petites boucles d'oreilles rondes (dorées).
				p.append(["head", Vector3(0.016, 0.016, 0.016), Vector3(side * 0.112, 0.085, 0.0), Color(0.8, 0.63, 0.25), 0.0])
			p.append(["head", Vector3(0.12, 0.08, 0.06), Vector3(0, 0.25, -0.12), hat.darkened(0.06), 0.0])
			# Racine des cheveux sur le front.
			p.append(["head", Vector3(0.2, 0.035, 0.02), Vector3(0, 0.235, 0.105), hat, 0.0])
			# Rouge à lèvres.
			p.append(["head", Vector3(0.05, 0.014, 0.012), Vector3(0, 0.06, 0.11), Color(0.62, 0.06, 0.08), 0.0])
			# Crayon derrière l'oreille droite.
			p.append(["head", Vector3(0.012, 0.012, 0.09), Vector3(0.122, 0.15, -0.01), Color(0.85, 0.66, 0.15), 0.0, Vector3(25, 0, 0)])
			# Chemisier crème dans l'encolure de la veste.
			p.append(["chest", Vector3(0.11, 0.16, 0.012), Vector3(0, 0.14, 0.126 * big + 0.002), cream, 0.0])
			# Taille haute : ceinture du pantalon au-dessus des hanches.
			p.append(["spine", Vector3(0.29, 0.05, 0.22 * big), Vector3(0, 0.0, 0), pants, 0.0])
			# Sacoche de cuir sur la hanche gauche, bandoulière en travers.
			p.append(["hips", Vector3(0.05, 0.17, 0.2), Vector3(-0.2, -0.04, 0.02), Color(0.36, 0.22, 0.12), 0.0])
			p.append(["chest", Vector3(0.04, 0.48, 0.02), Vector3(0, 0.05, 0.128 * big + 0.004), Color(0.3, 0.18, 0.1), 0.0, Vector3(0, 0, -38)])
		6:  # Jojo : casquette plate, barbe de trois jours, nez cassé, dent en or,
			# cou épais, gros ventre, bretelles, col ouvert, chaîne en or, valise.
			var gold := Color(0.85, 0.65, 0.2)
			var braces := Color(0.36, 0.13, 0.1)
			var front := 0.125 * big
			# Casquette plate : calotte aplatie qui avance sur le front, visière courte.
			p.append(["head", Vector3(0.235, 0.06, 0.26), Vector3(0, 0.27, 0.015), hat, 0.0, Vector3(-6, 0, 0)])
			p.append(["head", Vector3(0.2, 0.02, 0.07), Vector3(0, 0.245, 0.15), hat.darkened(0.2), 0.0, Vector3(-10, 0, 0)])
			# Barbe de trois jours, nez cassé (de travers), bouche et dent en or.
			p.append(["head", Vector3(0.2, 0.075, 0.025), Vector3(0, 0.05, 0.103), SKIN.darkened(0.35), 0.0])
			p.append(["head", Vector3(0.035, 0.05, 0.035), Vector3(0.008, 0.115, 0.118), SKIN.darkened(0.08), 0.0, Vector3(0, 0, 12)])
			p.append(["head", Vector3(0.07, 0.014, 0.012), Vector3(0, 0.068, 0.116), Color(0.12, 0.05, 0.05), 0.0])
			p.append(["head", Vector3(0.014, 0.014, 0.012), Vector3(0.016, 0.069, 0.119), gold, 0.4])
			# Cou de taureau.
			p.append(["neck", Vector3(0.17, 0.1, 0.15), Vector3(0, 0.03, 0.0), SKIN, 0.0])
			# Gros ventre sous le maillot, avec ses taches.
			p.append(["spine", Vector3(0.38, 0.28, 0.22), Vector3(0, 0.07, 0.12), jacket, 0.0])
			p.append(["hips", Vector3(0.36, 0.1, 0.17), Vector3(0, 0.08, 0.11), jacket, 0.0])
			p.append(["spine", Vector3(0.07, 0.05, 0.01), Vector3(-0.06, 0.1, 0.232), jacket.darkened(0.3), 0.0])
			p.append(["chest", Vector3(0.05, 0.04, 0.01), Vector3(0.08, 0.03, front + 0.002), jacket.darkened(0.25), 0.0])
			# Col ouvert (peau) et chaîne en or avec sa médaille.
			p.append(["chest", Vector3(0.12, 0.08, 0.012), Vector3(0, 0.19, front + 0.002), SKIN, 0.0])
			p.append(["chest", Vector3(0.13, 0.012, 0.012), Vector3(0, 0.2, front + 0.008), gold, 0.4])
			p.append(["chest", Vector3(0.022, 0.026, 0.01), Vector3(0, 0.18, front + 0.01), gold, 0.4])
			# Bretelles : par-dessus les épaules, sur la poitrine puis sur le ventre.
			for side in [-1.0, 1.0]:
				p.append(["chest", Vector3(0.035, 0.32, 0.012), Vector3(side * 0.11, 0.06, front + 0.006), braces, 0.0])
				p.append(["chest", Vector3(0.035, 0.012, 0.27 * big), Vector3(side * 0.11, 0.215, 0.0), braces, 0.0])
				p.append(["spine", Vector3(0.035, 0.27, 0.012), Vector3(side * 0.11, 0.07, 0.233), braces, 0.0])
				p.append(["chest", Vector3(0.035, 0.32, 0.012), Vector3(side * 0.08, 0.06, -front - 0.006), braces, 0.0])
			# Valise de contrebande sanglée dans le dos.
			p.append(["chest", Vector3(0.34, 0.26, 0.1), Vector3(0, 0.03, -front - 0.06), Color(0.33, 0.2, 0.11), 0.0])
			p.append(["chest", Vector3(0.35, 0.02, 0.105), Vector3(0, 0.1, -front - 0.06), Color(0.2, 0.12, 0.07), 0.0])
			p.append(["chest", Vector3(0.02, 0.02, 0.02), Vector3(0, 0.16, -front - 0.115), gold.darkened(0.3), 0.3])
	for side in ["l", "r"]:
		p.append(["arm_" + side, Vector3(0.11 * big, 0.3, 0.11 * big), Vector3(0, -0.14, 0), jacket, 0.0])
		# Brassard à la couleur du joueur (repérage des coéquipiers).
		p.append(["arm_" + side, Vector3(0.12 * big, 0.06, 0.12 * big), Vector3(0, -0.06, 0), slot_color, 0.0])
		p.append(["forearm_" + side, Vector3(0.09 * big, 0.27, 0.09 * big), Vector3(0, -0.13, 0), sleeve, 0.0])
		p.append(["forearm_" + side, Vector3(0.08, 0.1, 0.06), Vector3(0, -0.3, 0.01), hand, 0.0])
		p.append(["thigh_" + side, Vector3(0.15 * big, 0.46, 0.16), Vector3(0, -0.22, 0), pants, 0.0])
		p.append(["shin_" + side, Vector3(0.13, 0.44, 0.13), Vector3(0, -0.22, 0), pants, 0.0])
		p.append(["shin_" + side, Vector3(0.13, 0.08, 0.25), Vector3(0, -0.45, 0.04), BOOTS, 0.0])
	skel = RigBuilder.build(p, material())
	# Le modèle regarde vers +Z ; le joueur vers -Z.
	skel.rotation.y = PI
	if fem:
		skel.scale = Vector3.ONE * BERG_SCALE
	elif fat:
		skel.scale = Vector3.ONE * JOJO_SCALE
	add_child(skel)
	bones = RigBuilder.bone_indices(skel)
	weapon_attach = BoneAttachment3D.new()
	weapon_attach.bone_name = "forearm_r"
	skel.add_child(weapon_attach)


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


## Anime le squelette. `speed` m/s, `pitch` regard (rad), `flags` = Player.FLAG_*.
func animate(delta: float, speed: float, pitch: float, flags: int, downed: bool, dead: bool) -> void:
	if skel == null:
		return
	var crouch := flags & Player.FLAG_CROUCH != 0
	var sprint := flags & Player.FLAG_SPRINT != 0
	_down_k = move_toward(_down_k, 1.0 if (downed or dead) else 0.0, delta * 3.0)
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

	skel.set_bone_pose_position(bones.hips, Vector3(0, 0.95 - hips_drop - _down_k * 0.55 + absf(c) * 0.03 * move_k * (1.0 - pk), 0))
	var knee := 0.6 if crouch else 0.0
	var kick := 0.5 if dive else 0.0  # jambes repliées en plein vol
	skel.set_bone_pose_rotation(bones.thigh_l, _q(s * leg - knee - _down_k * 1.3 - kick * 0.3))
	skel.set_bone_pose_rotation(bones.thigh_r, _q(-s * leg - knee - _down_k * 1.1 - kick * 0.2, 0.0, 0.2 * _down_k))
	skel.set_bone_pose_rotation(bones.shin_l, _q(-maxf(0.0, -c) * leg * 1.2 + knee * 1.8 + _down_k * 1.4 + kick))
	skel.set_bone_pose_rotation(bones.shin_r, _q(-maxf(0.0, c) * leg * 1.2 + knee * 1.8 + _down_k * 0.4 + kick * 0.6))
	var lean := lerpf(0.05 + (0.3 if sprint else 0.0) - _down_k * 0.35, 0.0, pk)
	skel.set_bone_pose_rotation(bones.spine, _q(lean - pitch * 0.3 * (1.0 - pk)))
	skel.set_bone_pose_rotation(bones.chest, _q(-pitch * 0.35 * (1.0 - pk)))
	# Allongé, la tête se redresse pour regarder devant.
	skel.set_bone_pose_rotation(bones.head, _q(lerpf(-pitch * 0.35, -1.15 - pitch * 0.3, pk)))
	# Bras : arme épaulée (tendue vers l'avant), balancée en sprint ; allongé,
	# bras tendus dans l'axe du corps.
	var aim_arm := -1.45 - pitch * 0.3 + _recoil * 0.25
	if sprint:
		aim_arm = -0.7 + s * 0.3
	aim_arm = lerpf(aim_arm, -2.75 - pitch * 0.2 + _recoil * 0.2, pk)
	skel.set_bone_pose_rotation(bones.arm_r, _q(aim_arm, 0.0, 0.1))
	skel.set_bone_pose_rotation(bones.forearm_r, _q(-0.1))
	skel.set_bone_pose_rotation(bones.arm_l, _q(aim_arm + 0.1, 0.0, lerpf(-0.55, -0.35, pk)))
	skel.set_bone_pose_rotation(bones.forearm_l, _q(-0.8, 0.0, 0.3))
	var body_x := 0.0
	if dead:
		body_x = -PI * 0.47
	elif pk > 0.0:
		body_x = PI * 0.5 * pk
	skel.rotation.x = lerpf(skel.rotation.x, body_x, 1.0 - exp(-delta * (30.0 if pk > 0.0 else 6.0)))
	# Pivot aux pieds : on recentre le corps allongé sur la position du joueur.
	skel.position = Vector3(0.0, 0.16 * pk, 0.85 * pk)
