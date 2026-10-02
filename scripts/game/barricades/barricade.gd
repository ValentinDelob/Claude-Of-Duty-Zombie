class_name Barricade
extends Interactable
## Fenêtre barricadée (marqueur W) : 6 planches clouées en travers d'une
## ouverture du mur extérieur, comme dans Black Ops 1.
##
## * Les zombies apparus dans la poche extérieure viennent se placer devant la
##   fenêtre, arrachent les planches une par une, puis l'enjambent. Trois
##   places (BO1 : attack_spots ; milieu, gauche, droite), un zombie par
##   place, chacun à son rythme : une planche toutes les 2,5 s en moyenne,
##   pause « de folie » entre deux (BarricadeRules.tear_tick).
## * Les joueurs réparent en maintenant [F] depuis l'intérieur : une planche
##   toutes les 0,75 s, +10 points (plafond par manche : BarricadeSystem).
## * Serveur : état (masque de 6 bits), réparations, logique des zombies.
##   Chaque changement est diffusé par l'InteractionSystem (RPC fiable par
##   fenêtre) ; toutes les machines animent les planches.
##
## * Format 8 (cartes de l'éditeur) : PORTE À ZOMBIES simple ou double
##   (`kind`, BarricadeRules.KINDS ; docs/MAP_OBJECTS.md § 9) : vraie porte
##   défoncée de 10 cm d'épaisseur (ZombieDoorModel) dans la face intérieure
##   du mur, planches clouées devant. Porte simple : un seul zombie arrache
##   (TEAR_OFFSETS), trois attendent derrière lui (WAIT_POINTS) ; porte
##   double : un zombie par battant (deux à la fois), quatre attendent, deux
##   passages de front. Le battant est cassé à mi-hauteur : le zombie
##   l'enjambe comme une fenêtre (VAULT_TIME).
##
## Repère local : +Z vers l'intérieur de la zone, X le long du mur.

## Couche physique « barrière » : bloque joueurs et zombies, pas les balles.
const BARRIER_LAYER := 1 << 4
const SILL_TOP := 0.95
const LINTEL_BOTTOM := 2.35
const PLANK_SIZE := Vector3(1.34, 0.17, 0.045)
## Plan des planches (côté extérieur de l'embrasure, à portée des zombies).
const PLANK_Z := -0.36
## Le zombie qui arrache se tient là (dehors, -Z).
const TEAR_DIST := 0.82
## Places devant la fenêtre (BO1 : attack_spots) : décalage le long du mur
## (X local) de chacune ; un zombie par place, chacun arrache à son rythme.
## 0,65 m : deux capsules (2 x 0,3 m) côte à côte sans se toucher.
const SLOT_OFFSETS := [0.0, -0.65, 0.65]
## Sans place libre : attente à cette distance derrière la place du milieu.
const WAIT_BACK := 1.0
## Arrivée de l'enjambement (dedans, +Z).
const INSIDE_DIST := 1.0
## Pas d'enjambement tant qu'un zombie se tient à moins de cela de l'arrivée.
const EXIT_CLEARANCE := 0.65
## Fenêtre sans planches : l'enjambement part de moins de cela du point d'arrachage.
const VAULT_REACH := 0.9
## Un joueur plus proche que cela du zombie à la fenêtre se fait frapper.
const REACH := 1.8
const REPAIR_RANGE := 2.4
const TEAR_ANIM := 0.5
const REPAIR_ANIM := 0.32
## [hauteur, roulis, décalage z, décalage x] des 6 planches (de travers).
const LAYOUT := [
	[1.12, 0.10, 0.00, 0.03],
	[2.17, -0.08, 0.01, -0.03],
	[1.65, 0.44, -0.035, 0.0],
	[1.65, -0.41, 0.035, 0.02],
	[1.38, -0.06, 0.012, -0.05],
	[1.93, 0.07, -0.012, 0.05],
]

# --- Portes à zombies (format 8) -------------------------------------------
## Haut de l'ouverture d'une porte (MapValidator.ZOMBIE_DOOR_TOP).
const DOOR_HEIGHT := 2.1
const DOOR_PLANK_SIZE := Vector3(1.04, 0.15, 0.04)
## Plan des planches d'une porte : devant le battant, dans la tranche de
## 10 cm de la porte (ZombieDoorModel.BOARD_Z), côté salle.
const DOOR_PLANK_Z := 0.231
## Le zombie qui arrache se tient dans l'embrasure, juste dehors.
const DOOR_TEAR_DIST := 0.62
## Places où l'on arrache (X local) : porte simple au milieu, double devant
## chaque battant.
const TEAR_OFFSETS := {"porte": [0.0], "porte_double": [-0.5, 0.5]}
## Places d'attente derrière ceux qui arrachent : [X local, distance dehors
## depuis le milieu du mur] ; à l'écart des points d'apparition (1,6 m dehors,
## ±DOUBLE_SPAWN_SIDE pour la double) pour ne pas les boucher.
const WAIT_POINTS := {
	"porte": [[-0.75, 1.15], [0.75, 1.15], [0.0, 2.3]],
	"porte_double": [[-1.4, 1.2], [1.4, 1.2], [-0.45, 2.3], [0.45, 2.3]],
}
## Apparitions derrière une porte double : une derrière chaque battant.
const DOUBLE_SPAWN_SIDE := 0.75
## [hauteur, roulis, décalage z, décalage x] des planches d'une porte simple
## (6) et d'un battant de porte double (5, planches i paires à gauche).
const DOOR_LAYOUT := [
	[0.42, 0.09, 0.0, 0.02],
	[1.86, -0.07, 0.004, -0.02],
	[1.16, 0.42, -0.006, 0.0],
	[1.16, -0.40, 0.006, 0.02],
	[0.78, -0.06, 0.002, -0.03],
	[1.52, 0.08, -0.002, 0.03],
]
const DOUBLE_LAYOUT := [
	[0.45, 0.08, 0.0, 0.0],
	[1.85, -0.06, 0.004, 0.0],
	[1.15, 0.40, -0.006, 0.0],
	[0.8, -0.07, 0.002, 0.0],
	[1.5, 0.07, -0.002, 0.0],
]

var window_index := 0
var cell := Vector2i.ZERO
var inward := Vector3.FORWARD
## Hauteur de l'ouverture et graine des planches (déterministes).
var opening_height := MapBuilder.WALL_HEIGHT
@warning_ignore("shadowed_global_identifier")
var seed := 0
var zone := ""
var spawn_cells: Array = []
## Type d'entrée (BarricadeRules.KINDS) et largeur de l'ouverture (m).
var kind := BarricadeRules.WINDOW
var width := 1.0
## Nombre de planches (6 ; porte double : 10).
var plank_count := BarricadeRules.PLANKS
## Planches présentes (bit i = planche i).
var mask := BarricadeRules.FULL_MASK
## Serveur : zombie en train d'enjamber (un seul à la fois ; porte double :
## celui du passage 0, les autres passages dans _vaulters).
var vaulter: Zombie
## Serveur : zombie en train de passer, par passage (porte double : 2).
var _vaulters: Array = [null]
## Serveur : zombie posté à chaque place (places où l'on arrache, puis
## places d'attente d'une porte), ou null.
var _slots: Array = [null, null, null]
## Serveur : places dégagées (mesurées au premier besoin, _slot_open).
var _slot_ok: Array = []

## Serveur : pid -> temps de maintien cumulé.
var _repairers: Dictionary = {}
var _mm: MultiMesh
var _rest: Array[Transform3D] = []
var _fallen: Array[Transform3D] = []
## Animation par planche : [type (0 aucune, 1 arrachée, 2 reposée), temps].
var _anim: Array = []
var _animating := false


func setup(w: BarricadeLayout.Opening) -> void:
	window_index = w.index
	cell = w.cell
	zone = w.zone
	spawn_cells = w.spawns
	inward = w.inward_dir
	opening_height = w.height
	seed = w.seed
	interact_id = "window_%d" % w.index
	name = "Window%d" % w.index
	interact_range = 1.9
	hold_time = BarricadeRules.REPAIR_TIME
	position = w.pos
	rotation.y = atan2(inward.x, inward.z)
	kind = w.kind if BarricadeRules.KINDS.has(w.kind) else BarricadeRules.WINDOW
	width = w.width if is_door() else 1.0
	plank_count = BarricadeRules.planks_for(kind)
	mask = full_mask()
	_slots = []
	_slots.resize(slot_count())
	_vaulters = []
	_vaulters.resize(BarricadeRules.lanes(kind))
	if is_door():
		opening_height = minf(opening_height, DOOR_HEIGHT)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in plank_count:
		if is_door():
			_door_plank_rest(i, rng)
		else:
			var l: Array = LAYOUT[i]
			var b := Basis(Vector3.UP, rng.randf_range(-0.05, 0.05)) * Basis(Vector3.BACK, l[1] + rng.randf_range(-0.04, 0.04))
			_rest.append(Transform3D(b, Vector3(l[3], l[0] + rng.randf_range(-0.03, 0.03), PLANK_Z + l[2])))
		# Planche arrachée : à plat sur le sol, dehors, en vrac.
		var fb := Basis(Vector3.UP, rng.randf_range(-0.9, 0.9)) * Basis(Vector3.RIGHT, PI * 0.5)
		var fx := rng.randf_range(-0.55, 0.55) * (width if is_door() else 1.0)
		_fallen.append(Transform3D(fb, Vector3(fx, 0.03 + i * 0.012, -rng.randf_range(0.75, 1.25))))
		_anim.append([0, 0.0])


## Planche `i` d'une porte, au repos : clouée en travers de l'ouverture
## (porte double : de son battant), dans la tranche de 10 cm de la porte.
## Roulis tenu à ±0,42 rad et tirage léger : elle reste dans cette tranche.
func _door_plank_rest(i: int, rng: RandomNumberGenerator) -> void:
	var l: Array
	var cx := 0.0
	var dy := 0.0
	var roll_sign := 1.0
	if kind == BarricadeRules.DOUBLE_DOOR:
		var lane := BarricadeRules.lane_of_plank(i, 2)
		l = DOUBLE_LAYOUT[i >> 1]
		cx = TEAR_OFFSETS[kind][lane]
		# Battant droit : planches en miroir, un peu décalées en hauteur.
		roll_sign = 1.0 if lane == 0 else -1.0
		dy = 0.0 if lane == 0 else 0.08
	else:
		l = DOOR_LAYOUT[i]
	var b := Basis(Vector3.BACK, (float(l[1]) + rng.randf_range(-0.03, 0.03)) * roll_sign)
	_rest.append(Transform3D(b, Vector3(cx + float(l[3]), float(l[0]) + dy + rng.randf_range(-0.03, 0.03), DOOR_PLANK_Z + float(l[2]))))


func _ready() -> void:
	# L'encadrement fixe (allège, linteau, bois) est fusionné au décor par
	# PropBuilder._windows() ; ici : les planches, la barrière et la lueur.
	# Porte à zombies : le bâti et les battants défoncés (ZombieDoorModel).
	if is_door():
		add_child(ZombieDoorModel.build(kind, width, opening_height, seed))
	_build_planks()
	_build_barrier()
	# Faible lueur froide « du dehors » : les planches se découpent en
	# silhouette et un peu de lumière filtre dans la salle (sans ombre).
	var glow := OmniLight3D.new()
	glow.name = "OutsideGlow"
	glow.light_color = Color(0.45, 0.55, 0.78)
	glow.light_energy = 0.55
	glow.omni_range = 3.2
	glow.omni_attenuation = 1.4
	glow.shadow_enabled = false
	glow.distance_fade_enabled = true
	glow.distance_fade_begin = 22.0
	glow.distance_fade_length = 6.0
	glow.position = Vector3(0, 2.0, -1.4)
	add_child(glow)
	set_process(false)
	set_physics_process(false)


# --------------------------------------------------------------------------
# Construction (toutes les machines)
# --------------------------------------------------------------------------

func _build_planks() -> void:
	var bm := BoxMesh.new()
	bm.size = DOOR_PLANK_SIZE if is_door() else PLANK_SIZE
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = bm
	_mm.instance_count = plank_count
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 7
	for i in plank_count:
		var v := rng.randf_range(0.72, 1.08)
		_mm.set_instance_color(i, Color(v, v * rng.randf_range(0.9, 1.0), v * rng.randf_range(0.8, 0.95)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Planks"
	mmi.multimesh = _mm
	mmi.material_override = plank_material()
	# Sans ombre portée : ombre peu visible dans la pénombre des fenêtres, mais
	# redessinée dans les cubemaps des lampes à chaque planche animée.
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Au-delà, les planches ne se distinguent plus dans la pénombre.
	mmi.visibility_range_end = 32.0
	mmi.visibility_range_end_margin = 4.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(mmi)
	_refresh_all()


## Ouverture : infranchissable à pied (les zombies l'enjambent par script),
## mais les balles passent entre les planches.
func _build_barrier() -> void:
	var barrier := StaticBody3D.new()
	barrier.name = "Barrier"
	barrier.collision_layer = BARRIER_LAYER
	barrier.collision_mask = 0
	var bcs := CollisionShape3D.new()
	var bbox := BoxShape3D.new()
	bbox.size = Vector3(width, opening_height, 1.0)
	bcs.shape = bbox
	bcs.position.y = opening_height * 0.5
	barrier.add_child(bcs)
	add_child(barrier)


static var _plank_mat: StandardMaterial3D


## Bois gris et usé, veinage procédural ; teinte par planche (couleur d'instance).
static func plank_material() -> StandardMaterial3D:
	if _plank_mat:
		return _plank_mat
	var w := 128
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.08
	for y in h:
		for x in w:
			var grain := sin(x * 0.11 + noise.get_noise_2d(x * 0.4, y * 3.0) * 6.0 + y * 0.5) * 0.5 + 0.5
			var n := noise.get_noise_2d(x * 2.0, y * 2.0) * 0.5 + 0.5
			var k := 0.55 + grain * 0.25 + n * 0.2
			var c := Color(0.55, 0.47, 0.37) * k
			# Taches sombres (clous, pourriture) aux extrémités.
			if (x < 6 or x > w - 7) and absf(y - h * 0.5) < 3.0:
				c = Color(0.08, 0.07, 0.06)
			c.a = 1.0
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.92
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_plank_mat = m
	return m


# --------------------------------------------------------------------------
# État et animation des planches (toutes les machines)
# --------------------------------------------------------------------------

func planks() -> int:
	return BarricadeRules.count(mask)


func get_state() -> Dictionary:
	return {"m": mask}


func apply_state(state: Dictionary, animate: bool) -> void:
	set_mask(int(state.get("m", mask)), animate)


func set_mask(new_mask: int, animate := true) -> void:
	var old := mask
	mask = new_mask & full_mask()
	if _mm == null:
		return
	if not animate:
		for i in plank_count:
			_anim[i] = [0, 0.0]
		_refresh_all()
		return
	var torn := false
	var fixed := false
	for i in plank_count:
		var was := (old >> i) & 1
		var now := (mask >> i) & 1
		if was == now:
			continue
		_anim[i] = [1 if was == 1 else 2, 0.0]
		torn = torn or was == 1
		fixed = fixed or now == 1
	if torn:
		Audio.play_3d("barricade_tear_%d" % (1 + randi() % 3), global_position + Vector3.UP * 1.4, 0.0, 0.1, 4)
		var fx: Fx = Game.instance.fx_root if Game.instance else null
		if fx:
			fx.dust.burst(to_global(Vector3(0, 1.2 if is_door() else 1.5, (DOOR_PLANK_Z if is_door() else PLANK_Z) - 0.1)), -inward, 6, 1.2, 0.5, 0.7, Color(0.3, 0.24, 0.17, 0.5))
	# Le son du marteau part à l'arrivée de la planche (fin d'animation).
	if torn or fixed:
		_animating = true
		set_process(true)


func _process(delta: float) -> void:
	var busy := false
	for i in plank_count:
		var a: Array = _anim[i]
		if a[0] == 0:
			continue
		var dur := TEAR_ANIM if a[0] == 1 else REPAIR_ANIM
		a[1] += delta
		if a[1] >= dur:
			if a[0] == 2:
				Audio.play_3d("barricade_slam_%d" % (1 + randi() % 2), to_global(_rest[i].origin), 0.0, 0.08, 4)
				var fx: Fx = Game.instance.fx_root if Game.instance else null
				if fx:
					fx.dust.burst(to_global(_rest[i].origin), inward, 4, 0.8, 0.4, 0.6, Color(0.32, 0.27, 0.2, 0.45))
			a[0] = 0
		else:
			busy = true
		_mm.set_instance_transform(i, _plank_xform(i))
	if not busy:
		_animating = false
		set_process(false)
		_refresh_all()


func _refresh_all() -> void:
	for i in plank_count:
		_mm.set_instance_transform(i, _plank_xform(i))


## Transformation actuelle d'une planche (au repos, au sol ou en vol).
func _plank_xform(i: int) -> Transform3D:
	var a: Array = _anim[i]
	var present := (mask >> i) & 1 == 1
	if a[0] == 0:
		return _rest[i] if present else _fallen[i]
	var from: Transform3D
	var to: Transform3D
	var k: float
	if a[0] == 1:
		from = _rest[i]
		to = _fallen[i]
		k = clampf(a[1] / TEAR_ANIM, 0.0, 1.0)
		# Arrachée vers l'extérieur puis retombe.
		var p := from.origin.lerp(to.origin, ease(k, 1.6))
		p.z -= sin(k * PI) * 0.35
		p.y += sin(k * PI) * 0.25
		return Transform3D(from.basis.slerp(to.basis, k), p)
	from = _fallen[i]
	to = _rest[i]
	k = clampf(a[1] / REPAIR_ANIM, 0.0, 1.0)
	# Vole depuis le tas et claque en place.
	var q := from.origin.lerp(to.origin, ease(k, 0.6))
	q.y += sin(k * PI) * 0.4
	return Transform3D(from.basis.slerp(to.basis, ease(k, 0.5)), q)


# --------------------------------------------------------------------------
# Repères (monde)
# --------------------------------------------------------------------------

## Là où se tient le zombie qui arrache les planches (dehors, au milieu).
func tear_point() -> Vector3:
	var p := global_position - inward * (DOOR_TEAR_DIST if is_door() else TEAR_DIST)
	return Vector3(p.x, global_position.y, p.z)


## Arrivée de l'enjambement (dedans) ; porte double : devant le battant du
## passage `lane`.
func inside_point(lane := 0) -> Vector3:
	var p := global_position + inward * INSIDE_DIST + _side() * _lane_x(lane)
	return Vector3(p.x, global_position.y, p.z)


# --------------------------------------------------------------------------
# Type d'entrée (format 8) : fenêtre, porte simple, porte double
# --------------------------------------------------------------------------

func is_door() -> bool:
	return BarricadeRules.is_door(kind)


## Masque de toutes les planches de cette entrée.
func full_mask() -> int:
	return (1 << plank_count) - 1


## Places où l'on arrache (fenêtre : 3 ; porte : 1 ; porte double : 2).
func tear_slots() -> int:
	return SLOT_OFFSETS.size() if not is_door() else (TEAR_OFFSETS[kind] as Array).size()


## Toutes les places : où l'on arrache, puis où l'on attend (portes).
func slot_count() -> int:
	return tear_slots() + ((WAIT_POINTS[kind] as Array).size() if is_door() else 0)


## Zombies rattachés au plus (BarricadeRules.queue_max).
func queue_max() -> int:
	return BarricadeRules.WINDOW_QUEUE_MAX if not is_door() else BarricadeRules.queue_max(kind)


## La file de cette entrée est-elle pleine (Spawner) ?
func queue_full() -> bool:
	return BarricadeRules.queue_full(waiting_count(), kind)


## Passage de front de la place `i` (porte double : 0 à gauche, 1 à droite ;
## sinon 0).
func lane_of_slot(i: int) -> int:
	return i if kind == BarricadeRules.DOUBLE_DOOR and i < 2 else 0


func _lane_x(lane: int) -> float:
	return float(TEAR_OFFSETS[kind][lane]) if kind == BarricadeRules.DOUBLE_DOOR else 0.0


## Direction le long du mur (X local), à plat.
func _side() -> Vector3:
	var s := global_transform.basis.x if is_inside_tree() else Basis(Vector3.UP, rotation.y).x
	s.y = 0.0
	return s.normalized()


## Durée du passage (enjambement, fenêtre ou porte).
func vault_time() -> float:
	return BarricadeRules.VAULT_TIME


func interact_point() -> Vector3:
	return global_position + inward * 0.55 + Vector3.UP * 1.3


## Le point `pos` est-il du côté intérieur de la fenêtre ?
func is_inside(pos: Vector3) -> bool:
	return (pos - global_position).dot(inward) > 0.2  # même seuil que can_repair_from


# --------------------------------------------------------------------------
# Interaction : réparation (serveur)
# --------------------------------------------------------------------------

func prompt(pid: int) -> String:
	if mask == full_mask():
		return ""
	var p: Player = system.game.players.get(pid) if system else null
	if p and not is_inside(p.global_position):
		return ""
	return Lang.t("Maintenir [F] pour reconstruire la barricade", "Hold [F] to rebuild the barrier")


func srv_use(pid: int) -> void:
	if not _repairers.has(pid):
		_repairers[pid] = 0.0
	set_physics_process(true)


func srv_release(pid: int) -> void:
	_repairers.erase(pid)


func _physics_process(delta: float) -> void:
	if _repairers.is_empty():
		set_physics_process(false)
		return
	var game := system.game
	for pid in _repairers.keys():
		var p: Player = game.players.get(pid)
		var pd := game.session.get_data(pid)
		# Position de référence du serveur (dernier état accepté), pas la
		# position interpolée qui traîne derrière le joueur avec de la latence.
		if p == null or pd == null or pd.life != PlayerData.Life.ALIVE \
				or not can_repair_from(p.srv_origin(), global_position, inward, interact_point()):
			_repairers.erase(pid)
			continue
		if mask == full_mask():
			_repairers[pid] = 0.0
			continue
		_repairers[pid] += delta
		if _repairers[pid] >= BarricadeRules.repair_interval(PerkDB.reload_mult(pd)):
			_repairers[pid] = 0.0
			srv_add_plank(pid)


func is_repairing(pid: int) -> bool:
	return _repairers.has(pid)


## Serveur : repose une planche ; `pid` > 0 : réparation d'un joueur (points).
func srv_add_plank(pid := 0) -> bool:
	var i := BarricadeRules.plank_to_repair(mask, plank_count)
	if i < 0:
		return false
	set_mask(mask | (1 << i))
	broadcast_state()
	if pid > 0 and system.game.barricades:
		system.game.barricades.srv_award_repair(pid)
	return true


## Serveur : un zombie arrache une planche (porte double : `lane`, celle de
## son battant d'abord).
func srv_tear(lane := 0) -> bool:
	var i := BarricadeRules.plank_to_tear_lane(mask, plank_count, BarricadeRules.lanes(kind), lane)
	if i < 0:
		return false
	set_mask(mask & ~(1 << i))
	broadcast_state()
	return true


## Serveur : toutes les planches (bonus CHARPENTIER, tests).
func srv_set_mask(m: int) -> void:
	if m == mask:
		return
	set_mask(m)
	broadcast_state()


## Règle pure de la réparation : joueur en `pos` du côté intérieur de la
## fenêtre (`window`, normale `inward`) et à REPAIR_RANGE (à plat) de `point`.
static func can_repair_from(pos: Vector3, window: Vector3, inward_dir: Vector3, point: Vector3) -> bool:
	return (pos - window).dot(inward_dir) > 0.2 and _flat_dist(pos, point) <= REPAIR_RANGE


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --------------------------------------------------------------------------
# Zombies (serveur) : approche, arrachage, coup à travers, enjambement
# --------------------------------------------------------------------------

func srv_zombie_barrier(z: Zombie, delta: float) -> void:
	# Une place par zombie (BO1 : attack_spots) ; sans place libre, il attend
	# un peu en retrait (n'arrive pas en temps normal : le Spawner ne fait
	# plus apparaître derrière une fenêtre dont les places sont prises).
	var slot := _claim_slot(z)
	var tp := slot_point(slot) if slot >= 0 else tear_point() - inward * WAIT_BACK
	var to := tp - z.global_position
	to.y = 0.0
	var dist := to.length()
	var desired := Vector3.ZERO
	var face := atan2(inward.x, inward.z)
	# Fenêtre ouverte : on enjambe d'un peu plus loin. La file qui attend que
	# la sortie se libère se bousculait autour du point exact, aucun n'y
	# arrivait.
	if dist < (VAULT_REACH if mask == 0 else 0.5):
		if slot < 0 or slot >= tear_slots():
			# En retrait, ou à une place d'attente d'une porte : il s'agite en
			# attendant une place devant les planches.
			_frenzy_wait(z, delta)
			desired = to * 2.0
		else:
			var lane := lane_of_slot(slot)
			# Deux planches arrachées de son battant : le bras passe par le
			# trou et attrape le joueur collé à l'entrée (BO1).
			var victim := _victim_for(z)
			if victim and BarricadeRules.can_reach_through(mask, plank_count, BarricadeRules.lanes(kind), lane):
				z.target = victim
				z.barrier_attack()
				return
			if mask == 0:
				var v: Variant = _vaulters[lane]
				if (v == null or not is_instance_valid(v) or not (v as Zombie).is_alive() or (v as Zombie).barricade != self) and exit_clear(z, lane):
					_vaulters[lane] = z
					if lane == 0:
						vaulter = z
					_slots[slot] = null
					z.tear_frenzy = false
					z.start_vault(Vector3(z.global_position.x, tp.y, z.global_position.z), inside_point(lane))
					return
				# Fenêtre ouverte, sortie prise : il s'agite en attendant.
				_frenzy_wait(z, delta)
			else:
				# Agrippe-tire puis pause « de folie », à son propre rythme.
				var st := BarricadeRules.tear_tick(z.tear_frenzy, z.tear_t, z.tear_pause, delta, randf())
				z.tear_frenzy = st.x > 0.5
				z.tear_t = st.y
				z.tear_pause = st.z
				if st.w > 0.5:
					srv_tear(lane)
			# Petit recentrage sur sa place.
			desired = to * 2.0
	else:
		z.tear_t = 0.0
		z.tear_frenzy = false
		var spd: float = Zombie.SPEEDS[z.speed_class] * z.speed_mult
		desired = (to / dist + z.separation() * 0.6).normalized() * spd * clampf(dist * 1.5, 0.3, 1.0)
		face = atan2(to.x, to.z)
	var horiz := Vector3(z.velocity.x, 0.0, z.velocity.z).move_toward(desired, 12.0 * delta)
	z.velocity.x = horiz.x
	z.velocity.z = horiz.z
	z.yaw = lerp_angle(z.yaw, face, 1.0 - exp(-delta * 8.0))
	z.rotation.y = z.yaw


## Serveur : attente sans planche à arracher (place prise, sortie occupée) :
## pose de folie continue.
static func _frenzy_wait(z: Zombie, delta: float) -> void:
	if not z.tear_frenzy:
		z.tear_frenzy = true
		z.tear_t = 0.0
		z.tear_pause = 0.0
	z.tear_t += delta


## Place `i` devant la fenêtre (dehors) : celle du milieu, puis à gauche et à
## droite, le long du mur. Porte : les places où l'on arrache (TEAR_OFFSETS)
## puis les places d'attente (WAIT_POINTS).
func slot_point(i: int) -> Vector3:
	var side := _side()
	if not is_door():
		return tear_point() + side * SLOT_OFFSETS[i]
	var nt := tear_slots()
	if i < nt:
		return tear_point() + side * float(TEAR_OFFSETS[kind][i])
	var wp: Array = WAIT_POINTS[kind][i - nt]
	var p := global_position - inward * float(wp[1]) + side * float(wp[0])
	return Vector3(p.x, global_position.y, p.z)


## Serveur : place tenue par `z`, sinon la place libre (et dégagée) la plus
## proche de lui ; -1 s'il n'y en a pas. Une place se libère quand son
## zombie meurt, enjambe ou quitte la fenêtre. Porte : un zombie à une place
## d'attente prend la première place libre devant les planches (la plus
## proche de lui) ; un nouveau venu prend d'abord une place devant les
## planches, sinon une place d'attente.
func _claim_slot(z: Zombie) -> int:
	var nt := tear_slots()
	var held := -1
	var free_tear := -1
	var free_wait := -1
	var tear_d := INF
	var wait_d := INF
	for i in _slots.size():
		var o: Variant = _slots[i]
		if o != null and not _holds_slot(o):
			_slots[i] = null
			o = null
		if o == z:
			held = i
		elif o == null and _slot_open(i):
			var d := _flat_dist(slot_point(i), z.global_position)
			if i < nt and d < tear_d:
				tear_d = d
				free_tear = i
			elif i >= nt and d < wait_d:
				wait_d = d
				free_wait = i
	if held >= 0 and (held < nt or free_tear < 0):
		return held
	var pick := free_tear if free_tear >= 0 else free_wait
	if pick >= 0:
		if held >= 0:
			_slots[held] = null
		_slots[pick] = z
		z.tear_t = 0.0
		z.tear_frenzy = false
	return pick


## La place est-elle encore tenue par `o` (vivant, rattaché, pas en train
## d'enjamber) ? `o` peut être un zombie déjà libéré (retiré du jeu).
func _holds_slot(o: Variant) -> bool:
	if not is_instance_valid(o):
		return false
	var zo := o as Zombie
	return zo != null and zo.is_alive() and zo.barricade == self and zo.state != Zombie.State.VAULT


## Serveur : la place `i` est-elle dégagée (pas dans le mur d'une poche
## étroite) ? Mesuré une fois : rayon depuis la place du milieu, au niveau du
## bassin, rayon du zombie compris.
func _slot_open(i: int) -> bool:
	if i == 0:
		return true
	if _slot_ok.is_empty():
		_slot_ok = [true]
		var space := get_world_3d().direct_space_state if is_inside_tree() else null
		for k in range(1, slot_count()):
			var ok := space != null
			if ok:
				var from := tear_point() + Vector3.UP
				var dir := slot_point(k) - tear_point()
				var to := from + dir + dir.normalized() * (Zombie.RADIUS + 0.05)
				var q := PhysicsRayQueryParameters3D.create(from, to, 1)
				ok = space.intersect_ray(q).is_empty()
			_slot_ok.append(ok)
	return _slot_ok[i]


## Serveur : zombies qui attendent derrière cette fenêtre (rattachés à elle,
## pas encore en train d'enjamber). Le Spawner n'en ajoute plus au-delà de
## BarricadeRules.WINDOW_QUEUE_MAX.
func waiting_count() -> int:
	var n := 0
	for o: Zombie in system.game.zombies.alive:
		if o.barricade == self and o.state != Zombie.State.VAULT:
			n += 1
	return n


## Serveur : l'arrivée de l'enjambement est-elle libre ? L'enjambement pose le
## zombie sur ce point sans tenir compte des autres : posé dans un zombie qui
## attend là (joueur à terre, hors d'atteinte...), il le recouvrait, et la file
## ainsi tassée, alignée sur l'axe de la fenêtre, restait bloquée pour de bon
## (BUNKER K-7 : générateur à 1,5 m de la fenêtre sud).
## Porte double : une arrivée par passage (`lane`).
func exit_clear(z: Zombie, lane := 0) -> bool:
	var ip := inside_point(lane)
	for o: Zombie in system.game.zombies.alive:
		if o != z and absf(o.global_position.y - ip.y) < 1.0 and _flat_dist(o.global_position, ip) < EXIT_CLEARANCE:
			return false
	return true


## Serveur : fin de l'enjambement.
func srv_vault_done(z: Zombie) -> void:
	if vaulter == z:
		vaulter = null
	for i in _vaulters.size():
		if _vaulters[i] == z:
			_vaulters[i] = null


## Joueur debout collé à la fenêtre, à portée du zombie.
func _victim_for(z: Zombie) -> Player:
	var best: Player = null
	var best_d := REACH
	for p: Player in system.game.players.values():
		if not z.is_target_valid(p) or not is_inside(p.global_position):
			continue
		var d := _flat_dist(p.global_position, z.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best
