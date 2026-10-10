class_name Throwable
extends Node3D
## Objet lancé (grenade ou PELUCHE LEURRE) : trajectoire balistique qui
## rebondit sur le décor puis roule au sol.
##
## Le SERVEUR simule l'objet qui fait foi (mèche, arrêt au sol de la peluche,
## explosion) ; chaque client simule la même trajectoire à partir de la même
## position et de la même vitesse initiales (même décor : résultat quasi
## identique), et le serveur recale la position à l'explosion / à l'arrêt.

const WORLD_MASK := 1
## Vol : décor et corps des zombies (la grenade s'arrête à leurs pieds).
const FLIGHT_MASK := 1 | (1 << 2)
const MAX_FLIGHT := 6.0
## Peluche leurre : ours en peluche (TeddyModel) réduit à ~21 cm.
const DECOY_SCALE := 0.42

var tid := 0
var kind: int = ThrowableRules.Kind.FRAG
var owner_pid := 0
var server_side := false
var system: ThrowableSystem
var vel := Vector3.ZERO
## Temps local (s) de l'explosion (grenade).
var fuse_end := 0.0
var on_ground := false
var resting := false
var bounces := 0
## Peluche leurre : musique en cours (leurre actif).
var luring := false
var lure_end := 0.0
var _age := 0.0
var _spin := Vector3.ZERO
var _model: Node3D
var _eye_light: OmniLight3D
var _music: AudioStreamPlayer3D


func setup(id: int, k: int, pid: int, pos: Vector3, velocity: Vector3, fuse: float, is_server: bool) -> void:
	tid = id
	kind = k
	owner_pid = pid
	vel = velocity
	fuse_end = GameClock.now() + fuse
	server_side = is_server
	name = "T%d" % id if id > 0 else "Pred%d" % -id
	position = pos
	_spin = Vector3(randf_range(-9, 9), randf_range(-5, 5), randf_range(-9, 9))


func _ready() -> void:
	_model = build_model(kind, false)
	add_child(_model)
	if kind == ThrowableRules.Kind.DECOY:
		# Le point simulé est le centre d'une sphère de RADIUS : assise au sol.
		for c in _model.get_children():
			c.position.y -= ThrowableRules.RADIUS
		# Lueur rouge qui bat au rythme de la musique.
		_eye_light = OmniLight3D.new()
		_eye_light.light_color = Color(1.0, 0.15, 0.08)
		_eye_light.omni_range = 2.5
		_eye_light.light_energy = 0.0
		_eye_light.position = Vector3(0, 0.15, 0.06)
		add_child(_eye_light)


func _physics_process(delta: float) -> void:
	_age += delta
	if not resting:
		_step(delta)
		if _age > MAX_FLIGHT and server_side:
			_settle()
	if server_side and system:
		if kind == ThrowableRules.Kind.FRAG:
			if GameClock.now() >= fuse_end:
				system.srv_detonate(self)
		elif resting and not luring:
			system.srv_decoy_landed(self)
		elif luring and GameClock.now() >= lure_end:
			system.srv_detonate(self)


func _process(delta: float) -> void:
	# Rotation visuelle en vol, amortie au sol.
	if not resting:
		var k := 0.25 if on_ground else 1.0
		_model.rotation += _spin * delta * k
	elif kind == ThrowableRules.Kind.DECOY:
		_model.rotation = _model.rotation.lerp(Vector3(0, _model.rotation.y, 0), 1.0 - exp(-delta * 10.0))
	if luring:
		_animate_decoy()


## Pas de simulation : gravité, rebonds (lancer de rayon), roulement au sol.
func _step(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	if not on_ground:
		vel.y -= ThrowableRules.GRAVITY * delta
	var motion := vel * delta
	if on_ground:
		motion.y = 0.0
	if motion.length_squared() > 1e-8:
		var dir := motion.normalized()
		var q := PhysicsRayQueryParameters3D.create(position, position + motion + dir * ThrowableRules.RADIUS, FLIGHT_MASK)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			position += motion
		else:
			var n: Vector3 = hit.normal
			position = hit.position + n * ThrowableRules.RADIUS
			var impact := -vel.dot(n)
			vel = ThrowableRules.bounce(vel, n)
			if impact > 1.2:
				bounces += 1
				_spin *= 0.6
				Audio.play_3d("grenade_bounce" if kind == ThrowableRules.Kind.FRAG else "monkey_bounce",
					position, clampf(-14.0 + impact * 1.6, -14.0, 0.0), 0.12, 6)
			if n.y > 0.7 and absf(vel.y) < 1.4:
				on_ground = true
				vel.y = 0.0
	if on_ground:
		# Reste posé sur le sol ; tombe s'il roule au-delà d'un rebord.
		var down := PhysicsRayQueryParameters3D.create(position, position + Vector3.DOWN * (ThrowableRules.RADIUS + 0.12), WORLD_MASK)
		var g := space.intersect_ray(down)
		if g.is_empty():
			on_ground = false
		else:
			position.y = (g.position as Vector3).y + ThrowableRules.RADIUS
			var h := Vector2(vel.x, vel.z)
			h *= maxf(0.0, 1.0 - ThrowableRules.ROLL_FRICTION * delta)
			h = h.move_toward(Vector2.ZERO, ThrowableRules.ROLL_DECEL * delta)
			if h.length() < 0.15:
				h = Vector2.ZERO
				if server_side:
					_settle()
			vel = Vector3(h.x, 0.0, h.y)


func _settle() -> void:
	resting = true
	on_ground = true
	vel = Vector3.ZERO


## Serveur -> clients : position d'arrêt de la peluche ; la musique commence.
func start_lure(pos: Vector3, duration: float) -> void:
	position = pos
	_settle()
	luring = true
	lure_end = GameClock.now() + duration
	if _music == null:
		_music = AudioStreamPlayer3D.new()
		_music.bus = "SFX"
		_music.unit_size = 9.0
		_music.max_distance = 60.0
		_music.stream = Audio.get_stream("monkey_music")
		add_child(_music)
	_music.play()


## Peluche qui sautille et se dandine au tempo de la musique, lueur rouge.
func _animate_decoy() -> void:
	var t := GameClock.now() - (lure_end - ThrowableRules.DECOY_TIME)
	var beat := t * 2.0 * 2.25  # 135 battements/min, un saut par battement
	var hop := absf(sin(beat * PI * 0.5))
	_model.position.y = hop * 0.02
	_model.rotation.z = sin(beat * PI * 0.25) * 0.18
	if _eye_light:
		_eye_light.light_energy = 0.6 + 0.8 * (1.0 - hop)


# --------------------------------------------------------------------------
# Modèles (monde et vue à la première personne)
# --------------------------------------------------------------------------

static var _mats: Dictionary = {}


static func mat(c: Color, rough: float, metal: float, view: bool, glow := 0.0) -> ShaderMaterial:
	var key := "%s_%s_%s_%s_%s" % [c, rough, metal, view, glow]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/weapon.gdshader")
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("roughness", rough)
	m.set_shader_parameter("metallic", metal)
	m.set_shader_parameter("viewmodel", 1.0 if view else 0.0)
	m.set_shader_parameter("wear", 0.25)
	if glow > 0.0:
		m.set_shader_parameter("emission", c)
		m.set_shader_parameter("emission_energy", glow)
	_mats[key] = m
	return m


static func _part(parent: Node3D, mesh: Mesh, pos: Vector3, m: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _sphere(r: float, h := -1.0) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0 if h < 0.0 else h
	s.radial_segments = 10
	s.rings = 6
	return s


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _cyl(r_top: float, r_bot: float, h: float, seg := 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


## Modèle procédural. `view` : matériaux de la vue FPS (jamais dans les murs).
static func build_model(k: int, view: bool) -> Node3D:
	return _build_frag(view) if k == ThrowableRules.Kind.FRAG else _build_decoy()


## Grenade à fragmentation (type M67) : corps ovoïde olive, bouchon d'allumeur,
## cuillère et anneau de goupille.
static func _build_frag(view: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "Frag"
	var olive := mat(Color(0.2, 0.24, 0.13), 0.75, 0.1, view)
	var metal := mat(Color(0.35, 0.34, 0.3), 0.45, 0.8, view)
	_part(root, _sphere(0.034, 0.078), Vector3.ZERO, olive)
	# Bande de fragmentation (plus sombre).
	_part(root, _cyl(0.0355, 0.0355, 0.012, 12), Vector3(0, -0.004, 0), mat(Color(0.14, 0.17, 0.09), 0.8, 0.1, view))
	_part(root, _cyl(0.012, 0.014, 0.022), Vector3(0, 0.045, 0), metal)
	# Cuillère plaquée le long du corps.
	_part(root, _box(Vector3(0.012, 0.07, 0.006)), Vector3(0, 0.02, 0.036), metal, Vector3(0.25, 0, 0))
	# Anneau de goupille.
	var ring := TorusMesh.new()
	ring.inner_radius = 0.009
	ring.outer_radius = 0.013
	ring.rings = 8
	ring.ring_segments = 6
	var r := _part(root, ring, Vector3(0.018, 0.05, 0), metal, Vector3(0, 0, PI * 0.5))
	r.name = "Pin"
	return root


## PELUCHE LEURRE : petit ours en peluche (TeddyModel réduit), face vers +Z.
static func _build_decoy() -> Node3D:
	var root := Node3D.new()
	root.name = "Decoy"
	var teddy := TeddyModel.build()
	teddy.scale = Vector3.ONE * DECOY_SCALE
	root.add_child(teddy)
	return root
