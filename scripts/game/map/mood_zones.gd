class_name MoodZones
extends Node3D
## Ambiances des pièces d'une carte en jeu (RoomMood, docs/ART_DIRECTION.md
## « Ambiance des pièces ») : posé par MapProps (BUNKER K-7 : PropBuilder,
## par zone ; cartes de l'éditeur : MeshMapBuilder, clé « moods » de la
## description) AVANT les lampes, qui y lisent la couleur de leur pièce
## (mood_at).
##
## Pour chaque pièce d'ambiance (`add_area` : préréglage et boîtes) :
##   - remplissage : une OmniLight3D sans ombre (« Fill ») par grande boîte
##     (au plus FILLS_PER_AREA, MAX_FILLS par carte), au-dessus des têtes,
##     atténuation douce : murs et plafond prennent la couleur de la pièce ;
##     liée au courant (35 % courant coupé), sauf l'alarme (secours) qui
##     pulse ;
##   - brume : un FogVolume par boîte (au plus MAX_FOG), matériau partagé par
##     ambiance (albédo, densité, émission ; l'alarme pulse aussi), visible
##     avec la brume volumétrique (MEDIUM, HIGH ; rien à payer en LOW).

## Coût mesuré (tools/perf.sh perf_costs, labo de BUNKER K-7) : chaque
## remplissage couvre une grande part de l'écran ; 3 par pièce et 14 m de
## portée coûtaient +0,57 ms GPU en MEDIUM : 2 par pièce, 11 m au plus.
const FILLS_PER_AREA := 2
const MAX_FILLS := 16
const MAX_FOG := 48
## Surface au sol (m²) d'une boîte pour mériter sa propre lumière de
## remplissage (la plus grande boîte de chaque pièce en a toujours une).
const FILL_MIN_AREA := 9.0
## Hauteur du remplissage : part de la hauteur de la pièce.
const FILL_HEIGHT := 0.75
## Courant coupé : part de l'énergie du remplissage.
const UNPOWERED := 0.35
const FADE_BEGIN := 40.0

## [{mood, boxes: Array[AABB]}]
var areas: Array = []
## [[OmniLight3D, énergie de base, préréglage, principale (la plus grande boîte)]]
var _fills: Array = []
var _fog_mats: Dictionary = {}
var _powered := true
var _t := 0.0


## Pièce d'ambiance `mood` (RoomMood.PRESETS ; « » ou inconnu : ignorée).
func add_area(mood: String, boxes: Array) -> void:
	if not RoomMood.is_preset(mood) or boxes.is_empty():
		return
	var list: Array[AABB] = []
	for b in boxes:
		if b is AABB and b.size.x > 0.01 and b.size.z > 0.01:
			list.append(b)
	if not list.is_empty():
		areas.append({"mood": mood, "boxes": list})


## Ambiance au point `p` (« » : standard).
func mood_at(p: Vector3) -> String:
	for a in areas:
		for b: AABB in a.boxes:
			if b.grow(0.1).has_point(p):
				return String(a.mood)
	return ""


## Crée lumières et brume ; `power` : courant de la carte (null : allumé).
func build(power: PowerGrid = null) -> void:
	var fog_n := 0
	for a in areas:
		var p := RoomMood.preset(String(a.mood))
		var boxes: Array = (a.boxes as Array).duplicate()
		boxes.sort_custom(func(x: AABB, y: AABB) -> bool: return x.size.x * x.size.z > y.size.x * y.size.z)
		var made := 0
		for b: AABB in boxes:
			if made >= FILLS_PER_AREA or _fills.size() >= MAX_FILLS:
				break
			if made > 0 and b.size.x * b.size.z < FILL_MIN_AREA:
				break
			_add_fill(b, p, String(a.mood), made == 0)
			made += 1
		for b: AABB in boxes:
			if fog_n >= MAX_FOG:
				break
			var fv := FogVolume.new()
			fv.name = "Fog%d" % fog_n
			fv.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
			fv.size = b.size
			fv.position = b.get_center()
			fv.material = _fog_material(String(a.mood))
			add_child(fv)
			fog_n += 1
	if power:
		power.add_hook(_on_power)
	add_to_group(RenderQuality.GROUP)
	apply_quality(RenderQuality.current())


## LOW : une seule lumière de remplissage par pièce (la plus grande boîte).
func apply_quality(q: Dictionary) -> void:
	for f in _fills:
		(f[0] as OmniLight3D).visible = bool(f[3]) or String(q.get("name", "")) != "low"


func _add_fill(b: AABB, p: Dictionary, mood: String, main: bool) -> void:
	var l := OmniLight3D.new()
	l.name = "Fill%d" % _fills.size()
	var c := b.get_center()
	l.position = Vector3(c.x, b.position.y + b.size.y * FILL_HEIGHT, c.z)
	var diag := Vector2(b.size.x, b.size.z).length()
	l.omni_range = clampf(diag * 0.6, 4.5, 11.0)
	l.omni_attenuation = 0.7
	l.light_color = p.fill
	var e := float(p.fill_energy)
	l.light_energy = e
	l.light_specular = 0.15
	l.light_volumetric_fog_energy = 0.0
	l.shadow_enabled = false
	l.distance_fade_enabled = true
	l.distance_fade_begin = FADE_BEGIN
	l.distance_fade_length = 8.0
	add_child(l)
	_fills.append([l, e, mood, main])


func _fog_material(mood: String) -> FogMaterial:
	if _fog_mats.has(mood):
		return _fog_mats[mood]
	var p := RoomMood.preset(mood)
	var m := FogMaterial.new()
	m.density = float(p.fog_density)
	m.albedo = p.fog
	m.emission = p.fog_emission
	m.edge_fade = 0.25
	_fog_mats[mood] = m
	return m


func _on_power(on: bool) -> void:
	_powered = on
	_apply_energy(1.0)


## Remplissage selon le courant ; l'alarme (lumière de secours) reste et pulse.
func _apply_energy(pulse: float) -> void:
	for f in _fills:
		var l := f[0] as OmniLight3D
		var mood := String(f[2])
		var k := 1.0
		if mood == "alarme":
			k = pulse
		elif not _powered and mood != "eteint":
			k = UNPOWERED
		l.light_energy = float(f[1]) * k


## Pulsation de l'alarme (0,3 à 1), période RoomMood « pulse ».
static func alarm_pulse(t: float) -> float:
	var period := float(RoomMood.PRESETS.alarme.pulse)
	var s := 0.5 + 0.5 * sin(t * TAU / period)
	return 0.3 + 0.7 * s * s


func _process(delta: float) -> void:
	if not _fog_mats.has("alarme") and not _has_alarm():
		set_process(false)
		return
	_t += delta
	var k := alarm_pulse(_t)
	_apply_energy(k)
	if _fog_mats.has("alarme"):
		(_fog_mats.alarme as FogMaterial).emission = (RoomMood.PRESETS.alarme.fog_emission as Color) * (0.4 + 1.2 * k)


func _has_alarm() -> bool:
	for f in _fills:
		if String(f[2]) == "alarme":
			return true
	return false


## Boîtes des zones d'une carte en grille (BUNKER K-7) : rectangles de
## cellules de la zone (MapData.greedy_rects), du sol au plafond.
static func grid_boxes(data: MapData, zone: String, height: float) -> Array:
	var out := []
	for r in data.greedy_rects(func(c: Vector2i) -> bool: return data.zone_at(c) == zone and not data.is_wall(c)):
		var lo := Vector3(r.position.x * MapData.CELL, 0.0, r.position.y * MapData.CELL)
		out.append(AABB(lo, Vector3(r.size.x * MapData.CELL, height, r.size.y * MapData.CELL)))
	return out
