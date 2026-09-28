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


func _ready() -> void:
	_slab = Node3D.new()
	_slab.name = "Slab"
	add_child(_slab)
	var slab := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = _size
	slab.mesh = bm
	slab.material_override = WorldLook.surface("door")
	slab.position.y = _size.y * 0.5
	_slab.add_child(slab)
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
		var sign := Label3D.new()
		sign.text = str(cost)
		sign.font = UiStyle.font("stencil")
		sign.font_size = 96
		sign.pixel_size = 0.004
		sign.modulate = Color(0.75, 0.62, 0.35, 0.9)
		sign.outline_size = 0
		sign.position = Vector3(0, 2.25, side * (_size.z * 0.5 + 0.015))
		sign.rotation.y = 0.0 if side > 0 else PI
		sign.shaded = true
		_slab.add_child(sign)
		_signs.append(sign)

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
	if is_open:
		return ""
	# Nom de la zone de l'autre côté (celle où le joueur n'est pas).
	var game := system.game
	var p: Player = game.players.get(pid)
	var label := ""
	if p and zones.size() == 2:
		var here := game.layout.zone_at(p.global_position)
		label = game.map_def.zone_display_name(zones[1] if zones[0] == here else zones[0])
	if label == "":
		return "[F] Ouvrir la porte %s" % Interactable.cost_text(cost)
	return "[F] Ouvrir : %s %s" % [label, Interactable.cost_text(cost)]


func srv_use(pid: int) -> void:
	if is_open:
		return
	if not system.game.session.try_spend(pid, cost):
		system.deny(pid, "Pas assez de points")
		return
	system.purchase_fx(self)
	srv_open()


## Serveur : ouvre la porte (achat, ou ouverture forcée).
func srv_open() -> void:
	is_open = true
	var game := system.game
	game.layout.set_blocked(block, false)
	for z in zones:
		game.spawner.activate_zone(z)
		# Zones reliées sans porte (KINO : machines = scène = salle).
		for linked in game.map_def.open_links.get(z, []):
			game.spawner.activate_zone(linked)
	print("[Door] porte %s ouverte (%s)" % [door_id, ", ".join(zones)])
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
	var target_y := _size.y - 0.1 if open else 0.0
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
