class_name Door
extends Interactable
## Porte blindée payante entre deux zones. Construite de façon déterministe à
## partir des cellules d'un marqueur chiffré de la carte.
##
## Serveur : l'achat débite les points, débloque la navigation et active les
## zones d'apparition de l'autre côté. Toutes les machines animent l'ouverture.
##
## Visuel CUBIQUE (cubes de 5 cm, GAME_CONCEPT.md § 4.19 ; VoxelBuild, à la
## largeur de l'ouverture) sous le battant « Slab » ; la collision (pavé
## largeur × hauteur × 0,9 m) et l'ouverture ne changent pas.

const SLAB_THICKNESS := 0.22
const OPEN_TIME := 1.6

var door_id := ""
## Cellules de la porte (cartes grille seulement).
var cells: Array = []
## Bloqueur de navigation levé à l'ouverture (MapLayout.set_blocked).
var block := ""
## Porte ouverte par le courant (non achetable).
var power_door := false
## Porte liée : un seul achat ouvre les deux (escaliers à deux portes).
var link_id := ""
## Rideau de scène (velours, ouvert par le courant).
var curtain := false
## Tas de débris à dégager (BO1) au lieu d'une porte : planches et gravats
## qui s'enfoncent et disparaissent à l'achat.
var debris := false
## Aspect choisi dans l'éditeur de cartes (format 5, MapCatalog.VARIANTS) :
## porte « blindee » (défaut), « bois », « grille » ; débris « planches »
## (défaut), « gravats ». Valeur inconnue : l'aspect par défaut. Seul le
## visuel change (même collision, même ouverture, même prix).
var variant := ""
var cost := 0
var is_open := false
## Zones reliées par la porte.
var zones: Array = []

var _slab: Node3D
var _body: StaticBody3D
var _size := Vector3.ONE


func setup(id: String, door_cells: Array, door_cost: int, data: MapData) -> void:
	setup_marker(GridMapLayout.door_marker(id, door_cells, door_cost, data))


## Porte décrite par la carte : `m.pos` au sol au milieu de l'ouverture,
## data = {cost, width, height, depth, yaw, zones}, `m.block` = bloqueur.
func setup_marker(m: MapMarker) -> void:
	door_id = m.id
	interact_id = "door_" + m.id
	cells = m.data.get("cells", [])
	cost = int(m.data.cost)
	block = m.block
	name = "Door" + m.id
	_size = Vector3(float(m.data.width), float(m.data.height), SLAB_THICKNESS)
	position = m.pos
	rotation.y = float(m.data.yaw)
	interact_range = 1.6 + float(m.data.depth) * 0.5
	# Zones de part et d'autre.
	zones = m.data.zones.duplicate()
	power_door = bool(m.data.get("power", false))
	link_id = String(m.data.get("link", ""))
	curtain = bool(m.data.get("curtain", false))
	debris = bool(m.data.get("debris", false))
	variant = String(m.data.get("variant", ""))


## Aspect réellement construit (variante connue, sinon celle par défaut).
func look() -> String:
	if debris:
		return "gravats" if variant == "gravats" else "planches"
	if power_door or curtain:
		return ""
	return variant if variant in ["bois", "grille"] else "blindee"


func _ready() -> void:
	_slab = Node3D.new()
	_slab.name = "Slab"
	add_child(_slab)
	match look():
		"planches":
			_build_debris()
		"gravats":
			_build_rubble()
		"bois":
			_build_wood()
		"grille":
			_build_gate()
		_:
			_build_steel()
	_build_body()
	if power_door and multiplayer.is_server() and Game.instance:
		Game.instance.power_changed.connect(func(on: bool):
			if on and not is_open:
				srv_open())


@warning_ignore_start("integer_division")
## Visuel CUBIQUE (cubes de 5 cm, VoxelBuild ; GAME_CONCEPT.md § 4.19) :
## un modèle « Model » sous le battant « Slab », largeur et hauteur de
## l'ouverture arrondies au cube, 20 cm d'épaisseur (collision inchangée :
## _build_body). Aspect déterministe (identifiant de la porte) : la même porte
## sur toutes les machines.
const T := 2  # demi-épaisseur du battant (cubes)


## Modèle `vb` posé sous le battant, centré sur la largeur de l'ouverture.
func _add_model(vb: VoxelBuild, nw: int) -> MeshInstance3D:
	var mi := vb.node("Model", Vector3(-nw * VoxelBuild.CUBE * 0.5, 0.0, 0.0))
	_slab.add_child(mi)
	return mi


## Largeur et hauteur de l'ouverture en cubes.
func _cells() -> Vector2i:
	return Vector2i(VoxelBuild.cubes(_size.x, 6), VoxelBuild.cubes(_size.y, 6))


## Porte blindée (aspect par défaut) : tôle, cadre riveté en saillie, bande de
## danger, volant de verrouillage et prix au pochoir des deux côtés. Porte du
## courant : tôle et cadre, éclair peint (s'ouvre au courant). Rideau de
## scène : velours plissé.
func _build_steel() -> void:
	var n := _cells()
	var vb := VoxelBuild.new()
	if curtain:
		_curtain(vb, n.x, n.y)
	else:
		_steel_plate(vb, n.x, n.y)
		if power_door:
			_bolt(vb, n.x, n.y)
		else:
			_decorate(vb, n.x, n.y)
	_add_model(vb, n.x)


## Tôle et cadre de 2 cubes, un cube en saillie de chaque côté, rivets peints.
static func _steel_plate(vb: VoxelBuild, nw: int, nh: int) -> void:
	vb.fill(0, nw, 0, nh, -T, T, VoxelBuild.col("door_steel"), 3, 0.045, 2)
	var edge := VoxelBuild.col("door_edge")
	for x in nw:
		for y in nh:
			if x >= 2 and x < nw - 2 and y >= 2 and y < nh - 2:
				continue
			for z in range(-T - 1, T + 1):
				vb.put(x, y, z, VoxelBuild.grain(x, y, z, edge, 4, 0.06, 2))
	# Rivets clairs tous les 4 cubes sur le milieu du cadre.
	var rivet := VoxelBuild.col("steel", 0.85)
	for x in range(1, nw - 1, 4):
		for y in [1, nh - 2]:
			vb.paint(x, y, T, VoxelBuild.PZ, rivet)
			vb.paint(x, y, -T - 1, VoxelBuild.NZ, rivet)
	for y in range(1, nh - 1, 4):
		for x in [1, nw - 2]:
			vb.paint(x, y, T, VoxelBuild.PZ, rivet)
			vb.paint(x, y, -T - 1, VoxelBuild.NZ, rivet)


## Bande de danger jaune et noire en saillie (1 m du sol), volant de
## verrouillage des deux côtés (1,45 m), prix au pochoir en haut.
func _decorate(vb: VoxelBuild, nw: int, nh: int) -> void:
	var yb := mini(17, nh - 10)
	for x in range(2, nw - 2):
		for y in range(yb, yb + 6):
			var stripe := posmod(x + y, 6) < 3
			for z in range(-T - 1, T + 1):
				vb.put(x, y, z, VoxelBuild.col("hazard_yellow" if stripe else "rubber", 0.95 + 0.1 * VoxelBuild.noise(x, y, z, 6)))
	# Volant : carré de 7 ou 8 cubes, rayons en croix, moyeu ; un cube devant
	# et un derrière la tôle.
	var s := 7 if nw % 2 == 1 else 8
	var x0 := (nw - s) / 2
	var yc := mini(29, nh - 12)
	var y0 := yc - s / 2
	var mid := [s / 2] if s % 2 == 1 else [s / 2 - 1, s / 2]
	var steel := VoxelBuild.col("steel")
	for i in s:
		for j in s:
			var ring := i == 0 or j == 0 or i == s - 1 or j == s - 1
			if not (ring or i in mid or j in mid):
				continue
			var c := VoxelBuild.tone(steel, 1.12 if ring else 0.9)
			vb.put(x0 + i, y0 + j, T, c)
			vb.put(x0 + i, y0 + j, -T - 1, c)
	_paint_price(vb, nw, mini(42, nh - 8), -T - 1, T + 1)


## Éclair jaune peint des deux côtés (porte ouverte par le courant).
static func _bolt(vb: VoxelBuild, nw: int, nh: int) -> void:
	var shape := ["...##", "..##.", ".##..", "#####", "..##.", ".##..", "##...", "#...."]
	var cx := nw / 2 - 2
	var top := mini(nh - 6, 36)
	for row in shape.size():
		for k in 5:
			if shape[row][k] != "#":
				continue
			vb.paint_front(cx + k, top - row, -T - 1, T + 1, VoxelBuild.PZ, VoxelBuild.col("hazard_yellow"))
			vb.paint_front(cx + 4 - k, top - row, -T - 1, T + 1, VoxelBuild.NZ, VoxelBuild.col("hazard_yellow"))


## Rideau de velours : plis verticaux (colonnes de 3 cubes en avancée ou en
## retrait), frange dorée en bas.
static func _curtain(vb: VoxelBuild, nw: int, nh: int) -> void:
	for x in nw:
		var fold := 1 if posmod(x, 6) < 3 else 0
		for y in nh:
			for z in range(-T + fold, T - 1 + fold):
				var c := VoxelBuild.grain(x, y, z, VoxelBuild.col("velvet", 1.0 if fold == 1 else 0.78), 9, 0.05, 2)
				if y < 2:
					c = VoxelBuild.grain(x, y, z, VoxelBuild.col("gold"), 9, 0.06, 2)
				vb.put(x, y, z, c)


## Prix peint au pochoir sur les deux faces, bas des chiffres en `y0`.
func _paint_price(vb: VoxelBuild, nw: int, y0: int, z0: int, z1: int) -> void:
	var txt := str(cost)
	var c := VoxelBuild.col("price")
	vb.paint_number(txt, nw / 2, y0, z0, z1, VoxelBuild.PZ, c)
	vb.paint_number(txt, nw / 2, y0, z0, z1, VoxelBuild.NZ, c)


## Porte en bois (variante « bois ») : planches verticales jointives un peu
## inégales en haut, traverses et écharpe en escalier des deux côtés,
## pentures peintes en fer, prix peint.
func _build_wood() -> void:
	var n := _cells()
	var nw := n.x
	var nh := n.y
	var vb := VoxelBuild.new()
	var boards := maxi(3, roundi(_size.x / 0.28))
	var seam := VoxelBuild.col("wood_dark", 0.7)
	for i in boards:
		var bx0 := i * nw / boards
		var bx1 := (i + 1) * nw / boards
		# Planches un peu inégales en haut (même porte sur toutes les machines).
		var dh := (i * 7 + door_id.length()) % 3
		var base := VoxelBuild.col("wood" if i % 2 == 0 else "wood_dark", 1.05)
		for x in range(bx0, bx1):
			for y in nh - dh:
				for z in range(-T, T):
					# Veines verticales : teinte par colonne, grain léger par cube.
					vb.put(x, y, z, VoxelBuild.grain(x, y / 4, z, base, 11 + i, 0.06, 3))
		for y in nh - dh:
			vb.paint(bx0, y, T - 1, VoxelBuild.PZ, seam)
			vb.paint(bx0, y, -T, VoxelBuild.NZ, seam)
	# Traverses (3 cubes) des deux côtés, écharpe en escalier de l'une à l'autre.
	var dark := VoxelBuild.col("wood_dark")
	var lo := mini(8, nh / 4)
	var hi := maxi(lo + 6, nh - 11)
	for z in [T, -T - 1]:
		for x in range(1, nw - 1):
			for y in [lo, lo + 1, lo + 2, hi, hi + 1, hi + 2]:
				vb.put(x, y, z, VoxelBuild.grain(x, y, z, dark, 12, 0.06, 2))
			var k := float(x - 1) / maxf(1.0, nw - 3.0)
			var yb := lo + 3 + roundi(k * (hi - lo - 6))
			for y in range(yb, mini(yb + 3, hi)):
				vb.put(x, y, z, VoxelBuild.grain(x, y, z, dark, 13, 0.06, 2))
		# Pentures (fer) au bout des traverses, côté gonds, et clous.
		var face := VoxelBuild.PZ if z == T else VoxelBuild.NZ
		for y in [lo + 1, hi + 1]:
			for x in range(1, mini(9, nw - 1)):
				vb.paint(x, y, z, face, VoxelBuild.col("metal_dark", 1.2))
			vb.paint(nw - 3, y, z, face, VoxelBuild.col("metal_dark"))
	_paint_price(vb, nw, nh - 8, -T - 1, T + 1)
	_add_model(vb, nw)


## Grille en fer (variante « grille ») : montants et traverses rouillés,
## barreaux d'un cube, plaque du prix. Même collision qu'une porte pleine.
func _build_gate() -> void:
	var n := _cells()
	var nw := n.x
	var nh := n.y
	var vb := VoxelBuild.new()
	var rust := VoxelBuild.col("rust")
	for x in nw:
		for y in nh:
			var post := x < 2 or x >= nw - 2
			var mid := roundi(nh * 0.55)
			var bar := y < 2 or y >= nh - 2 or (y >= mid - 1 and y < mid + 1)
			if post or bar:
				for z in range(-1, 1):
					vb.put(x, y, z, VoxelBuild.grain(x, y, z, rust, 21, 0.08, 3))
	# Barreaux d'un cube tous les 3 cubes (15 cm, l'écart d'avant), centrés.
	var inner := nw - 4
	var rods := maxi(1, (inner - 1) / 3)
	var start := 2 + (inner - (rods * 3 - 2)) / 2
	for i in rods:
		var x := start + i * 3
		for y in range(2, nh - 2):
			vb.put(x, y, -1, VoxelBuild.grain(x, y, 0, VoxelBuild.col("steel", 0.8), 22, 0.07, 3))
	# Plaque du prix accrochée à la traverse du milieu, lisible des deux côtés.
	var yc := roundi(nh * 0.55) + 4
	var pw := maxi(12, str(cost).length() * 4 + 3)
	var px := (nw - pw) / 2
	vb.fill(px, px + pw, yc - 3, yc + 4, -1, 1, VoxelBuild.col("door_steel"), 23, 0.04, 2)
	_paint_price(vb, nw, yc - 2, -1, 1)
	_add_model(vb, nw)


## Tas qui bouche l'ouverture (débris) : profil plus haut au milieu, bombé en
## profondeur (`depth` cubes de part et d'autre du plan de la porte), en blocs
## de matière : `block.call(bloc, cellule) -> Color` (bloc : rang de 3 cubes,
## tronçon de 7 cubes décalé d'un rang à l'autre, tranche de 5 cubes).
static func _heap(vb: VoxelBuild, nw: int, nh: int, depth: int, s: int, block: Callable) -> void:
	var mid := (nw - 1) * 0.5
	for x in nw:
		var t := nh * (0.95 - 1.3 * absf(x - mid) / nw) + (VoxelBuild.noise(x / 3, 0, 0, s) - 0.5) * 5.0
		for z in range(-depth, depth):
			var edge := absf(z + 0.5) / depth
			var top := clampi(roundi(t - edge * edge * 8.0 + (VoxelBuild.noise(x, 1, z, s) - 0.5) * 2.0), 1, nh)
			for y in top:
				var row := y / 3
				var k := Vector3i((x + row * 4) / 7, row, (z + 64) / 5)
				vb.put(x, y, z, block.call(k, Vector3i(x, y, z)))


## Planche qui dépasse du tas (le long de x, 1 cube d'épais, 4 de large),
## d'une face à l'autre de la porte : plus longue que le tas est profond.
static func _plank(vb: VoxelBuild, nw: int, x0: int, ln: int, y: int, z0: int, base: Color, s: int) -> void:
	for x in range(maxi(0, x0), mini(nw, x0 + ln)):
		for z in range(z0, z0 + 4):
			vb.put(x, y, z, VoxelBuild.grain(x, y, z, base, s, 0.07, 3))


## Tas de débris (planches, blocs de béton, poutre) qui bouche le passage,
## plus haut au milieu ; aspect déterministe (même tas sur toutes les machines).
func _build_debris() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("debris_" + door_id)
	var n := _cells()
	var nw := n.x
	var nh := n.y
	var vb := VoxelBuild.new()
	var s := int(rng.randi() % 1000)
	# Cœur du tas : rangs de planches (tons de bois par tronçon), blocs de béton.
	_heap(vb, nw, nh, 6, s, func(k: Vector3i, c: Vector3i) -> Color:
		var r := VoxelBuild.noise(k.x, k.y, k.z, s + 1)
		if r < 0.3:
			return VoxelBuild.grain(c.x, c.y, c.z, VoxelBuild.col("concrete", 0.8 + 0.4 * r), s + 2, 0.08, 3)
		var wood := VoxelBuild.col("wood" if r < 0.7 else "wood_dark", 0.8 + 0.3 * VoxelBuild.noise(k.x, k.y, k.z, s + 3))
		# Joint sombre sous chaque rang de planches.
		return VoxelBuild.tone(wood, 0.62) if c.y % 3 == 0 else VoxelBuild.grain(c.x / 3, c.y, c.z, wood, s + 4, 0.06, 2))
	# Planches en travers qui dépassent devant et derrière.
	for i in 7:
		var ln := VoxelBuild.cubes(rng.randf_range(0.9, maxf(1.0, _size.x * 0.8)))
		var x0 := roundi(rng.randf_range(0.0, 1.0) * (nw - ln))
		var y := roundi(rng.randf_range(0.1, 0.75) * nh)
		var z0 := -9 if i % 2 == 0 else 5
		_plank(vb, nw, x0, ln, y, z0, VoxelBuild.col("wood" if i % 3 else "wood_dark", rng.randf_range(0.8, 1.1)), s + 10 + i)
	# Poutre en travers, du sol au haut de l'ouverture : escalier de cubes
	# (3 × 3), devant le tas.
	var wood := VoxelBuild.col("wood", 0.75)
	var x_lo := roundi(nw * 0.2)
	var x_hi := roundi(nw * 0.8)
	for y in range(0, nh - 2):
		var x := x_hi - roundi(float(x_hi - x_lo) * y / (nh - 3))
		for dx in 3:
			for z in range(4, 7):
				vb.put(x + dx, y, z, VoxelBuild.grain(x + dx, y / 2, z, wood, 31, 0.06, 2))
	_add_model(vb, nw)


## Éboulement de béton (variante « gravats » des débris) : blocs de béton
## fissurés, dalle brisée en escalier devant, fers à béton rouillés ; aspect
## déterministe.
func _build_rubble() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("rubble_" + door_id)
	var n := _cells()
	var nw := n.x
	var nh := n.y
	var vb := VoxelBuild.new()
	var s := int(rng.randi() % 1000)
	_heap(vb, nw, nh, 7, s, func(k: Vector3i, c: Vector3i) -> Color:
		var base := VoxelBuild.col("concrete", 0.55 + 0.45 * VoxelBuild.noise(k.x, k.y, k.z, s + 1))
		# Fissures : joints des blocs plus sombres.
		var crack := c.y % 3 == 0 and VoxelBuild.noise(c.x, c.y, c.z, s + 5) < 0.25
		return VoxelBuild.tone(base, 0.6) if crack else VoxelBuild.grain(c.x / 2, c.y, c.z / 2, base, s + 2, 0.05, 2))
	# Dalle brisée appuyée devant le tas : escalier de 3 cubes d'épaisseur.
	var dark := VoxelBuild.col("concrete", 0.42)
	var x0 := roundi(nw * 0.1)
	var x1 := roundi(nw * 0.75)
	for x in range(x0, x1):
		var y_top := roundi(float(x - x0) / (x1 - x0) * nh * 0.6) + 3
		for y in range(maxi(0, y_top - 4), y_top):
			for z in range(7, 10):
				vb.put(x, y, z, VoxelBuild.grain(x, y, z, dark, 70, 0.06, 3))
	# Fers à béton : tiges rouillées d'un cube, droites, qui dépassent du tas.
	var rust := VoxelBuild.col("rust")
	for i in 6:
		var x := roundi(rng.randf_range(0.15, 0.85) * (nw - 1))
		var z := roundi(rng.randf_range(-5.0, 5.0))
		var top := 0
		while top < nh and vb.has(x, top, z):
			top += 1
		var ln := VoxelBuild.cubes(rng.randf_range(0.3, 0.6))
		for k in range(-3, ln):
			var p := Vector3i(x, top + k, z) if i % 2 == 0 else Vector3i(x + k + 3, top - 2, z)
			if p.x >= 0 and p.x < nw and p.y >= 0 and p.y < nh:
				vb.put(p.x, p.y, p.z, VoxelBuild.tone(rust, 0.9 + 0.2 * VoxelBuild.noise(p.x, p.y, p.z, 71)))
	_add_model(vb, nw)


@warning_ignore_restore("integer_division")


func _build_body() -> void:
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.set_meta("surface", "wood")  # impacts de balles (Fx.surface_at)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_size.x, _size.y, 0.9)
	cs.shape = box
	cs.position.y = _size.y * 0.5
	_body.add_child(cs)
	add_child(_body)


func interact_point() -> Vector3:
	return global_position + Vector3.UP * 1.2


func prompt(pid: int) -> String:
	if is_open or power_door:
		return ""
	# Nom de la zone de l'autre côté (celle où le joueur n'est pas).
	var game := system.game
	var p: Player = game.players.get(pid)
	var label := ""
	if p and zones.size() == 2:
		var here := game.layout.zone_at(p.global_position)
		label = game.map_def.zone_display_name(zones[1] if zones[0] == here else zones[0])
	if debris:
		return Lang.t("[F] Dégager les débris %s", "[F] Clear the debris %s") % Interactable.cost_text(cost)
	if label == "":
		return Lang.t("[F] Ouvrir la porte %s", "[F] Open the door %s") % Interactable.cost_text(cost)
	return Lang.t("[F] Ouvrir : %s %s", "[F] Open: %s %s") % [label, Interactable.cost_text(cost)]


func srv_use(pid: int) -> void:
	if is_open or power_door:
		return
	if not system.game.session.try_spend(pid, cost):
		system.deny(pid, InteractionSystem.NO_POINTS)
		return
	system.purchase_fx(self)
	VoxSystem.say(pid, "door_open", 0.6)
	srv_open()


## Serveur : ouvre la porte (achat, ou ouverture forcée).
func srv_open() -> void:
	is_open = true
	var game := system.game
	game.layout.set_blocked(block, false)
	for z in zones:
		game.spawner.activate_zone(z)
		# Zones reliées sans porte (test_levels : rez-de-chaussée = mezzanine).
		for linked in game.map_def.open_links.get(z, []):
			game.spawner.activate_zone(linked)
	print("[Door] porte %s ouverte (%s)" % [door_id, ", ".join(zones)])
	# Porte liée (l'autre bout de l'escalier) : ouverte du même achat.
	if link_id != "" and game.doors.has(link_id) and not game.doors[link_id].is_open:
		game.doors[link_id].srv_open()
	broadcast_state()


func get_state() -> Dictionary:
	return {"open": is_open}


func apply_state(state: Dictionary, animate: bool) -> void:
	set_open(state.get("open", false), animate)


## Visuel + collision (toutes les machines).
func set_open(open: bool, animate := true) -> void:
	if _slab == null:
		return
	is_open = open
	(_body.get_child(0) as CollisionShape3D).set_deferred("disabled", open)
	# Porte : monte dans le linteau ; débris : s'enfoncent sous le sol.
	var target_y := (-(_size.y + 0.3) if debris else _size.y - 0.1) if open else 0.0
	if animate:
		Audio.play_3d("door_open", global_position + Vector3.UP * 1.5, 0.0, 0.05)
		var tw := create_tween()
		tw.tween_property(_slab, "position:y", target_y, OPEN_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		if open:
			tw.tween_callback(func(): _slab.visible = false)
	else:
		_slab.position.y = target_y
		_slab.visible = not open


