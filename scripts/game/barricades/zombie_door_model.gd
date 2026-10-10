class_name ZombieDoorModel
extends RefCounted
## Modèle d'une porte à zombies (format 8 des cartes ; docs/MAP_OBJECTS.md
## § 9) : bâti (montants, traverse, chambranle, seuil) et battant(s) cassé(s)
## à mi-hauteur — seule la moitié basse reste sur ses gonds, planches aux
## bouts éclatés en dents de cubes, le haut vide : les zombies l'enjambent
## comme l'allège d'une fenêtre — dans le plan de la face INTÉRIEURE du mur.
## Les planches de la barricade (Barricade, animées) sont clouées devant,
## dans la même tranche.
##
## Règle « vraie porte » : tout l'assemblage (bâti, battants, planches) tient
## dans une tranche de 10 cm (ENVELOPE) ; le reste de l'épaisseur du mur est
## l'embrasure, côté dehors (la cour des zombies). Vue de la salle, la porte
## est presque à fleur du mur, pas au fond d'un trou.
##
## CUBIQUE (cubes de 5 cm, VoxelBuild ; GAME_CONCEPT.md § 4.19) : la tranche
## fait deux couches de cubes. Couche de derrière : bâti et battants ; couche
## de devant : chambranle (autour de l'ouverture) et planches de la
## barricade (dans l'ouverture, Barricade.DOOR_PLANK_Z). Barres et pentures
## du battant peintes sur ses faces ; penture du haut arrachée en cubes.
##
## Repère local de la Barricade : +Z vers l'intérieur, X le long du mur, Y en
## haut, origine au sol au milieu du mur. Construit par le jeu (aucun fichier
## importé) ; aspect déterministe (graine de la fenêtre) sur toutes les
## machines.

## Tranche de l'assemblage (z local) : de l'arrière du bâti au chambranle.
const Z_BACK := 0.16
const Z_FRONT := 0.26
const ENVELOPE := Z_FRONT - Z_BACK
## Planches de la barricade : couche de cubes de devant.
const BOARD_Z := Vector2(0.21, 0.26)
## Haut moyen des battants cassés à mi-hauteur (bouts éclatés à ±5 cm) :
## hauteur de l'allège d'une fenêtre, que les zombies enjambent pareil.
const LEAF_TOP := 0.95
## Montants du bâti et chambranle (cubes).
const POST := 2
const CASING := 2

@warning_ignore_start("integer_division")

## Assemblage complet (nœud « DoorAssembly ») d'une porte de type `kind`
## (BarricadeRules.DOOR / DOUBLE_DOOR), de largeur `width` (m) et de hauteur
## `height` (haut de l'ouverture), graine `seed_v`. Un maillage cubique par
## partie : « Door_frame », « Door_casing », « Door_leaf_a », « Door_leaf_b »
## (planches paires et impaires du battant), « Door_metal » (penture).
static func build(kind: String, width: float, height: float, seed_v: int) -> Node3D:
	var root := Node3D.new()
	root.name = "DoorAssembly"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v + 101
	var nw := VoxelBuild.cubes(width, 2 * POST + 4)
	var nh := VoxelBuild.cubes(height, 24)
	var parts := {}
	for key in ["frame", "casing", "leaf_a", "leaf_b", "metal"]:
		parts[key] = VoxelBuild.new()
	var frame: VoxelBuild = parts.frame
	var casing: VoxelBuild = parts.casing
	var wood_frame := VoxelBuild.col("door_frame")
	# --- Bâti (couche de derrière) : montants, traverse ; seuil sur les deux couches.
	for x in nw:
		for y in nh:
			if x < POST or x >= nw - POST or y >= nh - POST:
				frame.put(x, y, 0, VoxelBuild.grain(x, y, 0, wood_frame, 41, 0.07, 3))
	for x in range(POST, nw - POST):
		for z in 2:
			frame.put(x, 0, z, VoxelBuild.grain(x, 0, z, wood_frame, 42, 0.07, 3))
	# --- Chambranle (couche de devant, autour de l'ouverture) et plinthes.
	var moulding := VoxelBuild.col("door_frame", 1.3)
	for x in range(-CASING, nw + CASING):
		for y in nh + CASING:
			if x >= 0 and x < nw and y < nh:
				continue
			var c := VoxelBuild.grain(x, y, 1, moulding, 43, 0.06, 3)
			if y < 3:
				c = VoxelBuild.grain(x, y, 1, wood_frame, 44, 0.05, 2)
			casing.put(x, y, 1, c)
	# Corniche un cube plus large en haut.
	for x in [-CASING - 1, nw + CASING]:
		for y in range(nh, nh + CASING):
			casing.put(x, y, 1, VoxelBuild.grain(x, y, 1, moulding, 43, 0.06, 3))
	# --- Battant(s) cassé(s) à mi-hauteur (couche de derrière).
	var top_hinge := nh - POST - 6
	if kind == BarricadeRules.DOUBLE_DOOR:
		var half := nw / 2
		_half_leaf(parts, rng, POST, half, 1)
		_half_leaf(parts, rng, nw - POST - 1, half, -1)
		_torn_strap(parts.metal, POST, top_hinge, 1)
		_torn_strap(parts.metal, nw - POST - 1, top_hinge, -1)
	else:
		_half_leaf(parts, rng, POST, nw - POST, 1)
		_torn_strap(parts.metal, POST, top_hinge, 1)
	var offset := Vector3(-nw * VoxelBuild.CUBE * 0.5, 0.0, Z_BACK)
	for key in parts:
		var vb: VoxelBuild = parts[key]
		if vb.cells.is_empty():
			continue
		var mi := vb.node("Door_" + key, offset, false)
		mi.visibility_range_end = 40.0
		root.add_child(mi)
	return root


## Moitié basse d'un battant cassé à mi-hauteur : planches debout de 3 cubes
## du seuil à LEAF_TOP environ, bouts du haut éclatés en dents (hauteur par
## colonne de cubes), une planche plus courte ; barres (côté dehors) et
## pentures (côté salle) peintes. `hinge` : colonne côté gonds ; `side` = +1 :
## le battant s'étend vers +X jusqu'à `end` (exclu), -1 : vers -X.
static func _half_leaf(parts: Dictionary, rng: RandomNumberGenerator, hinge: int, end: int, side: int) -> void:
	var span := absi(end - hinge) if side > 0 else absi(hinge - end) + 1
	var boards := maxi(3, span / 3)
	var short := rng.randi() % boards
	var top0 := roundi(LEAF_TOP / VoxelBuild.CUBE)
	var bar := top0 - 6
	for i in boards:
		var key := "leaf_a" if i % 2 == 0 else "leaf_b"
		var vb: VoxelBuild = parts[key]
		var base := VoxelBuild.col("leaf_green" if i % 2 == 0 else "wood", 0.95 + 0.1 * rng.randf())
		var u0 := i * span / boards
		var u1 := (i + 1) * span / boards
		# Cassée un peu plus bas côté libre (là où les coups ont porté).
		var top := top0 + rng.randi_range(-1, 1) - i * 2 / boards
		if i == short:
			top -= rng.randi_range(2, 4)
		for u in range(u0, u1):
			var x := hinge + u * side
			# Dents : chaque colonne de cubes cassée à sa hauteur.
			var t := top + (rng.randi_range(-1, 1) if u != u0 else 0)
			for y in range(1, mini(t, top0 + 2)):
				var c := VoxelBuild.grain(x, y, 0, base, 45 + i, 0.08, 3)
				# Peinture écaillée : bois nu par endroits.
				if VoxelBuild.noise(x, y, 0, 46) > 0.82:
					c = VoxelBuild.col("wood", 0.9)
				vb.put(x, y, 0, c)
				# Barres du battant (dehors, -z) : celle du bas entière, celle du haut cassée.
				if (y >= 3 and y < 6) or (y >= bar and y < bar + 3 and u < span * 4 / 5):
					vb.paint(x, y, 0, VoxelBuild.NZ, VoxelBuild.col("wood_dark", 0.9))
				# Pentures en fer (côté salle, +z) près des gonds.
				if u < 7 and (y == 4 or y == bar + 1):
					vb.paint(x, y, 0, VoxelBuild.PZ, VoxelBuild.col("metal_dark", 1.3))


## Penture du haut restée sur le bâti sans son battant, arrachée : quatre
## cubes de fer en escalier qui pendent du montant (`side` comme _half_leaf).
static func _torn_strap(vb: VoxelBuild, x0: int, y: int, side: int) -> void:
	var c := VoxelBuild.col("metal_dark", 1.25)
	for k in 4:
		vb.put(x0 + k * side, y - k / 2, 0, VoxelBuild.tone(c, 1.0 - 0.05 * k))
