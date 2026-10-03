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
## Échelle du personnage (Berg, Jojo) : les poses sont écrites pour 1.
var body_scale := 1.0
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
const DOWN_SUPPORT := 0.52
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
const DOWN_EYE_Y := 0.8
const DOWN_FWD := 0.33
const TUCK_FWD := 0.12


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
		body_scale = BERG_SCALE
	elif fat:
		body_scale = JOJO_SCALE
	skel.scale = Vector3.ONE * body_scale
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
	var aim_arm := -1.45 - pitch * 0.3 + _recoil * 0.25
	if sprint:
		aim_arm = -0.7 + s * 0.3
	aim_arm = lerpf(aim_arm, -2.75 - pitch * 0.2 + _recoil * 0.2, pk)
	var arm_r := Vector3(aim_arm, 0.0, 0.1)
	var forearm_r := -0.1
	var arm_l := Vector3(aim_arm + 0.1, 0.0, lerpf(-0.55, -0.35, pk))
	var forearm_l := Vector3(-0.8, 0.0, 0.3)

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
		var d_head := lerpf(clampf(-pitch * 0.85, -0.8, 0.9) - d_chest_abs, 0.2, dd)
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
	var fwd := lerpf(DOWN_FWD, TUCK_FWD, _tuck) * smoothstep(0.0, 1.0, dk) * body_scale
	var pos := Vector3(0.0, 0.16 * pk, 0.85 * pk - fwd)
	var tilt := Basis.IDENTITY
	if dk > 0.0:
		tilt = Basis(Quaternion(Vector3.UP, Vector3.UP.lerp(_floor_n, dk).normalized()))
	skel.transform = Transform3D(tilt * Basis.from_euler(Vector3(_body_x, PI, 0.0)).scaled(Vector3.ONE * body_scale), tilt * pos)
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
	return DOWN_EYE_Y * body_scale


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


## Point le plus bas du corps sous l'os du bassin (repère du squelette,
## échelle 1) : bassin incliné de `p`, cuisses et tibias d'inclinaisons
## absolues `tl`, `sl`, `tr`, `sr` (dimensions des pièces de build()).
static func _low_point(p: float, tl: float, sl: float, tr: float, sr: float) -> float:
	var low := _box_low(-0.1, 0.1, -0.105, 0.105, p)
	var hip := -0.02 * cos(p)
	# Deux jambes, sans tableau temporaire (appelé à chaque image à terre).
	return minf(low, minf(_leg_low(hip, tl, sl), _leg_low(hip, tr, sr)))


## Point le plus bas d'une jambe (cuisse `t`, tibia et pied `sh`) sous la
## hanche à la hauteur `hip`.
static func _leg_low(hip: float, t: float, sh: float) -> float:
	var knee_y := hip - 0.45 * cos(t)
	var low := hip + _box_low(-0.45, 0.01, -0.08, 0.08, t)
	low = minf(low, knee_y + _box_low(-0.44, 0.0, -0.065, 0.065, sh))
	return minf(low, knee_y + _box_low(-0.49, -0.41, -0.085, 0.165, sh))


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
	var reach := 1.45 * body_scale
	_front_q.to = _front_q.from + f * reach
	var hit2 := space.intersect_ray(_front_q)
	var d := reach if hit2.is_empty() else _front_q.from.distance_to(hit2.position)
	_tuck_target = clampf((reach - 0.05 - d) / 0.6, 0.0, 1.0)
