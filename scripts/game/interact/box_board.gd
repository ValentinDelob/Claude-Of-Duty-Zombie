class_name BoxBoard
extends Node3D
## Tableau indicateur de la boîte mystère (Kino der Toten) : planche de bois
## où le plan de la carte est tracé à la craie, une petite ampoule par
## emplacement de la boîte. Après le courant, l'ampoule de l'emplacement
## actuel est verte ; tout clignote pendant un déplacement ou une Liquidation.
## Purement visuel, lu localement sur chaque machine (l'état de la boîte est
## déjà répliqué).

const SIZE := Vector2(1.5, 1.05)
const TEX := 256

var box: MysteryBox
var _normal := Vector3.FORWARD
var _bulbs: Array[StandardMaterial3D] = []
var _t := 0.0
var _outlines: Array = []  # contours des salles (Godot, plan x/z)
var _spots: Array[Vector3] = []


## `outlines` : contours des salles ([[x, z]...]) ; `spots` : emplacements de la boîte.
func setup(m: MapMarker, outlines: Array, spots: Array[Vector3], mystery: MysteryBox) -> void:
	name = "BoxBoard_" + m.id
	_normal = m.wall
	position = m.on_wall(0.03, 1.65)
	_outlines = outlines
	_spots = spots
	box = mystery


func _ready() -> void:
	look_at(global_position - _normal, Vector3.UP)
	rotate_object_local(Vector3.UP, PI)
	var wood := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(SIZE.x + 0.12, SIZE.y + 0.12, 0.05)
	wood.mesh = bm
	wood.material_override = WorldLook.surface("dark_wood")
	add_child(wood)
	# Plan à la craie (texture générée d'après les contours des salles).
	var bounds := _bounds()
	var chalk := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = SIZE
	chalk.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(_draw(bounds))
	mat.roughness = 0.95
	chalk.material_override = mat
	chalk.position.z = 0.027
	add_child(chalk)
	for s in _spots:
		var bulb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.022
		sm.height = 0.044
		sm.radial_segments = 8
		sm.rings = 4
		bulb.mesh = sm
		var bmat := PropBuilder._emissive(Color(1.0, 0.15, 0.08), 0.0)
		bulb.material_override = bmat
		var uv := _to_uv(s, bounds)
		bulb.position = Vector3((uv.x - 0.5) * SIZE.x, (0.5 - uv.y) * SIZE.y, 0.04)
		add_child(bulb)
		_bulbs.append(bmat)


func _bounds() -> Rect2:
	var r := Rect2()
	var first := true
	for o in _outlines:
		for p in o:
			var v := Vector2(float(p[0]), float(p[1]))
			if first:
				r = Rect2(v, Vector2.ZERO)
				first = false
			else:
				r = r.expand(v)
	return r.grow(2.0)


## Position monde (x, z) -> coordonnées du tableau (0..1), nord en haut.
func _to_uv(p: Vector3, b: Rect2) -> Vector2:
	var s := maxf(b.size.x / SIZE.x, b.size.y / SIZE.y)
	var c := b.get_center()
	return Vector2(0.5 + (p.x - c.x) / (s * SIZE.x), 0.5 + (p.z - c.y) / (s * SIZE.y))


func _draw(b: Rect2) -> Image:
	var img := Image.create(TEX, int(TEX * SIZE.y / SIZE.x), false, Image.FORMAT_RGBA8)
	img.fill(Color(0.07, 0.08, 0.07))
	var chalk := Color(0.82, 0.82, 0.76)
	for o in _outlines:
		for i in o.size():
			var a: Vector2 = _to_uv(Vector3(o[i][0], 0, o[i][1]), b)
			var c: Vector2 = _to_uv(Vector3(o[(i + 1) % o.size()][0], 0, o[(i + 1) % o.size()][1]), b)
			_line(img, a * Vector2(img.get_width(), img.get_height()), c * Vector2(img.get_width(), img.get_height()), chalk)
	return img


static func _line(img: Image, a: Vector2, b: Vector2, col: Color) -> void:
	var n := int(maxf(absf(b.x - a.x), absf(b.y - a.y))) + 1
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		var x := int(p.x)
		var y := int(p.y)
		if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
			# Trait de craie irrégulier.
			var k := 0.55 + 0.45 * fposmod(sin(x * 12.9898 + y * 78.233) * 43758.5453, 1.0)
			img.set_pixel(x, y, Color(col, k))


func _process(delta: float) -> void:
	if box == null:
		return
	_t += delta
	var power := Game.instance != null and Game.instance.power_on
	var blinking := box.state == MysteryBox.State.MOVING or box.fire_sale
	for i in _bulbs.size():
		var m := _bulbs[i]
		if not power:
			m.emission_energy_multiplier = 0.0
		elif blinking:
			m.emission = Color(0.1, 1.0, 0.25)
			m.emission_energy_multiplier = 3.0 if fmod(_t + i * 0.13, 0.5) < 0.25 else 0.2
		elif i == box.location:
			m.emission = Color(0.1, 1.0, 0.25)
			m.emission_energy_multiplier = 3.0
		else:
			m.emission = Color(1.0, 0.15, 0.08)
			m.emission_energy_multiplier = 0.4
