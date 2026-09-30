class_name Door
extends Interactable
## Porte blindée payante entre deux zones. Construite de façon déterministe à
## partir des cellules d'un marqueur chiffré de la carte.
##
## Serveur : l'achat débite les points, débloque la navigation et active les
## zones d'apparition de l'autre côté. Toutes les machines animent l'ouverture.

const SLAB_THICKNESS := 0.22
const OPEN_TIME := 1.6

var door_id := ""
## Cellules de la porte (cartes grille seulement).
var cells: Array = []
## Bloqueur de navigation levé à l'ouverture (MapLayout.set_blocked).
var block := ""
## Porte ouverte par le courant (non achetable : KINO, hall <-> salle de théâtre).
var power_door := false
## Porte liée : un seul achat ouvre les deux (KINO : escaliers à deux portes).
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
var _signs: Array[Label3D] = []


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


## Porte blindée (aspect par défaut ; porte du courant et rideau : sans décor).
func _build_steel() -> void:
	var slab := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = _size
	slab.mesh = bm
	slab.material_override = WorldLook.surface("velvet" if curtain else "door")
	slab.position.y = _size.y * 0.5
	_slab.add_child(slab)
	if not power_door:
		_decorate()


## Pavé du visuel (enfant du battant) : `size`, centre `at`, matériau `mat`.
func _part(size: Vector3, at: Vector3, mat: String, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = WorldLook.surface(mat)
	mi.position = at
	mi.rotation = rot
	_slab.add_child(mi)
	return mi


## Barreau (cylindre fin) du visuel : fers d'une grille, fers à béton.
func _rod(length: float, radius: float, at: Vector3, mat: String, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = 6
	mi.mesh = cm
	mi.material_override = WorldLook.surface(mat)
	mi.position = at
	mi.rotation = rot
	_slab.add_child(mi)
	return mi


## Porte en bois (variante « bois ») : planches verticales jointives,
## traverses et écharpe en Z des deux côtés, pentures en fer, prix peint.
func _build_wood() -> void:
	var w := _size.x
	var h := _size.y
	var t := SLAB_THICKNESS
	var n := maxi(3, roundi(w / 0.28))
	var pw := w / n
	for i in n:
		# Planches un peu inégales en haut (même porte sur toutes les machines).
		var dh := 0.04 * float((i * 7 + door_id.length()) % 3)
		_part(Vector3(pw - 0.015, h - dh, t), Vector3(-w * 0.5 + pw * (i + 0.5), (h - dh) * 0.5, 0.0), "wood" if i % 2 == 0 else "dark_wood")
	var ang := atan2(h - 1.0, w - 0.2)
	for side in [-1.0, 1.0]:
		var z: float = side * (t * 0.5 + 0.025)
		for y in [0.45, h - 0.45]:
			_part(Vector3(w - 0.08, 0.16, 0.05), Vector3(0, y, z), "dark_wood")
			# Penture (bande de fer) au bout de la traverse.
			_part(Vector3(0.42, 0.07, 0.02), Vector3(-w * 0.5 + 0.25, y, side * (t * 0.5 + 0.06)), "steel")
		# Écharpe en travers, d'une traverse à l'autre.
		_part(Vector3(sqrt(pow(w - 0.2, 2.0) + pow(h - 1.0, 2.0)), 0.14, 0.05), Vector3(0, h * 0.5, z), "dark_wood", Vector3(0, 0, ang))
	_price_signs(h - 0.25, t * 0.5 + 0.055)


## Grille en fer (variante « grille ») : cadre, barreaux, traverse et plaque du
## prix. Même collision qu'une porte pleine (on ne tire pas au travers).
func _build_gate() -> void:
	var w := _size.x
	var h := _size.y
	for x in [-w * 0.5 + 0.05, w * 0.5 - 0.05]:
		_part(Vector3(0.1, h, 0.1), Vector3(x, h * 0.5, 0), "wall_rust")
	for y in [0.06, h * 0.55, h - 0.06]:
		_part(Vector3(w, 0.08, 0.08), Vector3(0, y, 0), "wall_rust")
	var n := maxi(4, roundi((w - 0.1) / 0.14))
	for i in range(1, n):
		_rod(h - 0.1, 0.018, Vector3(-w * 0.5 + 0.05 + (w - 0.1) * float(i) / n, h * 0.5, 0), "steel")
	# Plaque du prix accrochée à la traverse, lisible des deux côtés.
	_part(Vector3(0.62, 0.3, 0.03), Vector3(0, h * 0.55 + 0.21, 0), "door")
	_price_signs(h * 0.55 + 0.21, 0.02, 64)


## Prix peint au pochoir, des deux côtés, à la hauteur `y` et à `z` du milieu.
func _price_signs(y: float, z: float, font_size := 96) -> void:
	for side in [-1.0, 1.0]:
		var sign_label := Label3D.new()
		sign_label.text = str(cost)
		sign_label.font = UiStyle.font("stencil")
		sign_label.font_size = font_size
		sign_label.pixel_size = 0.004
		sign_label.modulate = Color(0.75, 0.62, 0.35, 0.9)
		sign_label.outline_size = 0
		sign_label.position = Vector3(0, y, side * z)
		sign_label.rotation.y = 0.0 if side > 0 else PI
		sign_label.shaded = true
		_slab.add_child(sign_label)
		_signs.append(sign_label)


## Éboulement de béton (variante « gravats » des débris) : blocs de béton,
## dalle brisée en travers, fers à béton tordus ; aspect déterministe.
func _build_rubble() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("rubble_" + door_id)
	var w := _size.x
	var h := _size.y
	for i in 12:
		var s := rng.randf_range(0.35, 0.8)
		var x := rng.randf_range(-0.5, 0.5) * (w - 0.3)
		var top := h * (0.9 - absf(x) / w)
		_part(Vector3(s, s * rng.randf_range(0.5, 0.8), s * rng.randf_range(0.7, 1.1)),
			Vector3(x, rng.randf_range(0.2, maxf(top, 0.35)), rng.randf_range(-0.3, 0.3)),
			"concrete" if i % 3 != 0 else "concrete_dark",
			Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.7, 0.7), rng.randf_range(-0.4, 0.4)))
	# Dalle brisée appuyée en travers de l'ouverture.
	_part(Vector3(w * 0.85, 0.18, 0.9), Vector3(-w * 0.05, h * 0.45, 0.0), "concrete_dark", Vector3(0, 0.1, 0.5))
	for i in 5:
		_rod(rng.randf_range(0.6, 1.3), 0.012, Vector3(rng.randf_range(-0.45, 0.45) * w, rng.randf_range(0.5, h * 0.8), rng.randf_range(-0.25, 0.25)),
			"wall_rust", Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-1.2, 1.2)))


## Bandes d'avertissement, volants et prix peints (portes payantes).
func _decorate() -> void:
	# Bandes d'avertissement jaunes et noires.
	var stripe_mat := StandardMaterial3D.new()
	stripe_mat.albedo_texture = _stripes_texture()
	stripe_mat.roughness = 0.8
	stripe_mat.uv1_scale = Vector3(_size.x * 1.5, 1, 1)
	var stripe := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(_size.x - 0.05, 0.28, _size.z + 0.02)
	stripe.mesh = sm
	stripe.material_override = stripe_mat
	stripe.position.y = 1.0
	_slab.add_child(stripe)
	for side in [-1.0, 1.0]:
		# Volant de verrouillage.
		var wheel := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.18
		cm.bottom_radius = 0.18
		cm.height = 0.05
		cm.radial_segments = 10
		wheel.mesh = cm
		wheel.material_override = WorldLook.surface("steel")
		wheel.rotation.x = PI * 0.5
		wheel.position = Vector3(0, 1.45, side * (_size.z * 0.5 + 0.03))
		_slab.add_child(wheel)
		# Prix peint au pochoir, des deux côtés.
		var sign_label := Label3D.new()
		sign_label.text = str(cost)
		sign_label.font = UiStyle.font("stencil")
		sign_label.font_size = 96
		sign_label.pixel_size = 0.004
		sign_label.modulate = Color(0.75, 0.62, 0.35, 0.9)
		sign_label.outline_size = 0
		sign_label.position = Vector3(0, 2.25, side * (_size.z * 0.5 + 0.015))
		sign_label.rotation.y = 0.0 if side > 0 else PI
		sign_label.shaded = true
		_slab.add_child(sign_label)
		_signs.append(sign_label)


## Tas de débris (planches, gravats, poutre) qui bouche le passage, de
## l'aspect déterministe (même tas sur toutes les machines).
func _build_debris() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("debris_" + door_id)
	var w := _size.x
	var h := _size.y
	for i in 14:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var plank := i % 3 != 0
		var s := rng.randf_range(0.35, 0.75)
		bm.size = Vector3(rng.randf_range(0.9, w * 0.8), 0.07, 0.22) if plank else Vector3(s, s * 0.7, s)
		mi.mesh = bm
		mi.material_override = WorldLook.surface("wood" if plank else "concrete")
		# Tas plus haut au milieu, plus bas sur les bords.
		var x := rng.randf_range(-0.5, 0.5) * (w - 0.4)
		var top := h * (0.95 - absf(x) / w)
		mi.position = Vector3(x, rng.randf_range(0.15, maxf(top, 0.3)), rng.randf_range(-0.3, 0.3))
		mi.rotation = Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.6, 0.6), rng.randf_range(-0.9, 0.9) if plank else rng.randf_range(-0.3, 0.3))
		_slab.add_child(mi)
	# Poutre en travers, du sol au haut de l'ouverture.
	var beam := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.2, h * 1.05, 0.2)
	beam.mesh = bb
	beam.material_override = WorldLook.surface("wood")
	beam.position = Vector3(w * 0.15, h * 0.48, 0.05)
	beam.rotation.z = 0.55
	_slab.add_child(beam)


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


static var _stripes: Texture2D


static func _stripes_texture() -> Texture2D:
	if _stripes:
		return _stripes
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for y in n:
		for x in n:
			var s := fmod(float(x + y), 32.0) < 16.0
			var c := Color(0.75, 0.6, 0.08) if s else Color(0.05, 0.05, 0.04)
			img.set_pixel(x, y, c * (0.8 + 0.2 * rng.randf()))
	_stripes = ImageTexture.create_from_image(img)
	return _stripes
