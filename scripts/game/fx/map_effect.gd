class_name MapEffect
extends Node3D
## Un effet de carte posé dans l'éditeur (MapEffects le construit) : couches
## de particules GPU, lumières qui vacillent, arcs électriques qui crépitent,
## salves (court-circuit, pluie d'étincelles) et cycles (soudure). AUCUN
## objet solide (format 11 : ce sont des décors à part) ni collision, rien à
## synchroniser en réseau (décor de la carte, hasard local).
##
## Coût : un seul _process léger par effet (lumières, arcs, minuteries ; aucune
## allocation par image). Loin de la caméra (FAR m, moins en qualité basse),
## l'effet est caché et ses particules cessent d'être émises ; ses lumières
## s'éteignent. Qualité graphique (groupe RenderQuality.GROUP) : densité des
## particules (amount_ratio) et lumières secondaires éteintes en LOW.

## Distance (m) au-delà de laquelle l'effet se met en pause (x 0,7 en LOW).
const FAR := 38.0
## Période (s) du test de distance.
const CHECK := 0.3

enum Light { STEADY, FIRE, WELD, CRACKLE, PULSE, FLASH }

var fx_id := ""
var intensity := 1.0
## Corps de l'effet (particules, arcs) ; les lumières restent sur la racine.
## Format 11 : jamais mis à l'échelle (une grande zone a PLUS de particules,
## pas de plus grosses).
var body: Node3D
## Zone de l'effet (m) : largeur (x), profondeur (z ; effet mural : sa portée
## dans la pièce), hauteur (volume ; effet mural : étendue verticale).
var zone := Vector3.ONE

var parts: Array[GPUParticles3D] = []
## Particules qui émettent en continu (mise en pause loin de la caméra).
var _continuous: Array[GPUParticles3D] = []
var lights: Array[OmniLight3D] = []
var _light_base: PackedFloat32Array = []
var _light_mode: PackedByteArray = []
var _light_minor: PackedByteArray = []
var _light_on: PackedByteArray = []   # 0 : coupée par le budget de la carte
var _light_val: PackedFloat32Array = []   # éclair : énergie qui retombe
var _phase: PackedFloat32Array = []

## Arcs électriques : nœud, mode (0 : entre deux points, 1 : rayon au
## hasard autour d'un centre), a, b (points ou centre / [rmin, rmax, 0]),
## largeur, salve seulement (visible juste après une salve).
var arcs: Array[MeshInstance3D] = []
var _arc_mode: PackedByteArray = []
var _arc_a: PackedVector3Array = []
var _arc_b: PackedVector3Array = []
var _arc_w: PackedFloat32Array = []
var _arc_burst: PackedByteArray = []
var arc_mats: Array[Material] = []
var _arc_t := 0.0
var _burst_glow := 0.0

## Salves : particules relancées ensemble (one_shot) toutes les
## [min, max] s, parfois deux ou trois coups rapprochés (pops : probabilité).
var _burst_parts: Array[GPUParticles3D] = []
var burst_every := Vector2.ZERO
var burst_pops := 0.0
var _burst_t := 0.0
var _pops_left := 0

## Cycle marche / pause (soudure) : particules coupées pendant la pause.
var cycle_on := Vector2.ZERO
var cycle_off := Vector2.ZERO
var _cycle_parts: Array[GPUParticles3D] = []
var _cycle_t := 0.0
var _cycling := true

var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _check_t := 0.0
var _active := true
var _far := FAR
var _density := 1.0
var _budget := 1.0
var _low := false


func _init() -> void:
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	_rng.randomize()
	_check_t = _rng.randf() * CHECK


func _ready() -> void:
	add_to_group(RenderQuality.GROUP)
	apply_quality(RenderQuality.current())
	_burst_t = _rng.randf_range(0.3, maxf(0.4, burst_every.y)) if burst_every != Vector2.ZERO else 0.0
	_cycle_t = _rng.randf_range(cycle_on.x, cycle_on.y) if cycle_on != Vector2.ZERO else 0.0


# ------------------------------------------------------------------ enregistrement (MapEffects)

func add_part(p: GPUParticles3D, burst := false, cycled := false) -> void:
	body.add_child(p)
	parts.append(p)
	p.set_meta("ratio", 1.0)
	if burst:
		p.one_shot = true
		p.emitting = false
		_burst_parts.append(p)
	else:
		_continuous.append(p)
	if cycled:
		_cycle_parts.append(p)


func add_light(l: OmniLight3D, mode: int, minor := false) -> void:
	add_child(l)
	lights.append(l)
	_light_base.append(l.light_energy)
	_light_mode.append(mode)
	_light_minor.append(1 if minor else 0)
	_light_on.append(1)
	_light_val.append(0.0 if mode == Light.FLASH else l.light_energy)
	_phase.append(_rng.randf() * TAU)
	if mode == Light.FLASH:
		l.light_energy = 0.0


func add_arc(mi: MeshInstance3D, mode: int, a: Vector3, b: Vector3, width: float, burst_only := false) -> void:
	body.add_child(mi)
	arcs.append(mi)
	_arc_mode.append(mode)
	_arc_a.append(a)
	_arc_b.append(b)
	_arc_w.append(width)
	_arc_burst.append(1 if burst_only else 0)
	mi.visible = not burst_only
	_aim_arc(arcs.size() - 1)


## Garde au plus `n` lumières allumées (budget de la carte) ; rend le nombre gardé.
func limit_lights(n: int) -> int:
	var kept := 0
	for i in lights.size():
		var on := kept < n
		_light_on[i] = 1 if on else 0
		if on:
			kept += 1
	_apply_light_visibility()
	return kept


## Nombre de particules de l'effet (budget de la carte).
func particle_count() -> int:
	var n := 0
	for p in parts:
		n += p.amount
	return n


## Part des particules gardées (budget de la carte dépassé : 0 < k <= 1).
func set_budget(k: float) -> void:
	_budget = clampf(k, 0.05, 1.0)
	_apply_density()


# ------------------------------------------------------------------ qualité

func apply_quality(q: Dictionary) -> void:
	_density = float(q.get("particles", 1.0))
	_low = String(q.get("name", "")) == "low"
	_far = FAR * (0.7 if _low else 1.0)
	_apply_density()
	for l in lights:
		l.distance_fade_enabled = true
		l.distance_fade_begin = float(q.get("light_fade_begin", 28.0))
		l.distance_fade_length = float(q.get("light_fade_length", 6.0))
	_apply_light_visibility()


func _apply_density() -> void:
	for p in parts:
		p.amount_ratio = clampf(float(p.get_meta("ratio", 1.0)) * _density * _budget, 0.05, 1.0)


func _apply_light_visibility() -> void:
	for i in lights.size():
		lights[i].visible = _active and _light_on[i] == 1 and not (_low and _light_minor[i] == 1)


# ------------------------------------------------------------------ animation

func _process(delta: float) -> void:
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = CHECK
		_update_active()
	if not _active:
		return
	_t += delta
	if not _cycle_parts.is_empty():
		_cycle_t -= delta
		if _cycle_t <= 0.0:
			_cycling = not _cycling
			_cycle_t = _rng.randf_range(cycle_on.x, cycle_on.y) if _cycling else _rng.randf_range(cycle_off.x, cycle_off.y)
			for p in _cycle_parts:
				p.emitting = _cycling
	if not _burst_parts.is_empty():
		_burst_t -= delta
		if _burst_t <= 0.0:
			_burst()
	_burst_glow = maxf(0.0, _burst_glow - delta)
	if not arcs.is_empty():
		_arc_t -= delta
		if _arc_t <= 0.0:
			_arc_t = _rng.randf_range(0.035, 0.09)
			for i in arcs.size():
				if _arc_burst[i] == 1:
					arcs[i].visible = _burst_glow > 0.0 and _rng.randf() < 0.8
				else:
					arcs[i].visible = _rng.randf() < 0.72
				if arcs[i].visible:
					_aim_arc(i)
	for i in lights.size():
		if not lights[i].visible:
			continue
		var base := _light_base[i]
		var ph := _phase[i]
		var e := base
		match _light_mode[i]:
			Light.FIRE:
				e = base * (0.82 + 0.1 * sin(_t * 8.7 + ph) + 0.06 * sin(_t * 21.3 + ph * 1.7) + _rng.randf_range(-0.05, 0.05))
			Light.WELD:
				e = (base * _rng.randf_range(0.55, 1.35) if _rng.randf() < 0.85 else base * 0.15) if _cycling else 0.0
			Light.CRACKLE:
				e = base * _rng.randf_range(0.35, 1.3) if _rng.randf() < 0.6 else base * 0.08
			Light.PULSE:
				e = base * (0.72 + 0.28 * sin(_t * 1.6 + ph))
			Light.FLASH:
				_light_val[i] *= exp(-delta * 13.0)
				e = _light_val[i]
		lights[i].light_energy = e


## Salve : particules relancées, éclair de lumière, arcs montrés un instant ;
## parfois un ou deux coups de plus juste après.
func _burst() -> void:
	for p in _burst_parts:
		p.restart()
	for i in lights.size():
		if _light_mode[i] == Light.FLASH:
			_light_val[i] = _light_base[i] * _rng.randf_range(0.7, 1.2)
	_burst_glow = 0.12
	if _pops_left > 0:
		# Coup suivant de la même salve, tout de suite après.
		_pops_left -= 1
		_burst_t = _rng.randf_range(0.07, 0.2)
	else:
		# Fin de la salve : la prochaine dans un moment, de 1 à 3 coups.
		_burst_t = _rng.randf_range(burst_every.x, burst_every.y)
		_pops_left = (1 if _rng.randf() < burst_pops else 0) + (1 if _rng.randf() < burst_pops * 0.4 else 0)


## Arc n° i : nouvelle forme (miroir au hasard, largeur, direction pour un
## arc rayonnant). Le quad est un panneau « Y fixe » : son axe Y va d'un bout
## de l'arc à l'autre, il fait face à la caméra autour de cet axe.
func _aim_arc(i: int) -> void:
	var mi := arcs[i]
	var a := _arc_a[i]
	var b := _arc_b[i]
	if _arc_mode[i] == 1:
		# Rayon au hasard : a = centre, b.x / b.y = longueur min / max.
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.45, 0.7), _rng.randf_range(-1, 1))
		if dir.length_squared() < 0.01:
			dir = Vector3.UP
		b = a + dir.normalized() * _rng.randf_range(_arc_b[i].x, _arc_b[i].y)
	var axis := b - a
	var span := maxf(axis.length(), 0.01)
	var y := axis / span
	# Panneau tourné autour de l'axe de l'arc vers la caméra (sinon de face).
	var mid := (a + b) * 0.5
	var view := Vector3.FORWARD
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		view = body.to_local(cam.global_position) - mid
	var x := y.cross(view)
	if x.length_squared() < 0.0001:
		x = y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	var w := _arc_w[i] * _rng.randf_range(0.7, 1.25)
	mi.transform = Transform3D(Basis(x * w, y * span * _rng.randf_range(1.0, 1.12), z), (a + b) * 0.5)
	if not arc_mats.is_empty():
		mi.material_override = arc_mats[_rng.randi() % arc_mats.size()]


## Pause loin de la caméra (rien n'est émis ni éclairé), reprise en approchant.
func _update_active() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var on := true
	if cam != null:
		var d := cam.global_position.distance_to(global_position)
		on = d < (_far * 1.1 if _active else _far)
	if on == _active:
		return
	_active = on
	visible = on
	for p in _continuous:
		p.emitting = on and (_cycling or not _cycle_parts.has(p))
	_apply_light_visibility()
