class_name Barricade
extends Interactable
## Fenêtre barricadée (marqueur W) : 6 planches clouées en travers d'une
## ouverture du mur extérieur, comme dans Black Ops 1.
##
## * Les zombies apparus dans la poche extérieure viennent se placer devant la
##   fenêtre, arrachent les planches une par une, puis l'enjambent.
## * Les joueurs réparent en maintenant [F] depuis l'intérieur : une planche
##   toutes les 0,75 s, +10 points (plafond par manche : BarricadeSystem).
## * Serveur : état (masque de 6 bits), réparations, logique des zombies.
##   Chaque changement est diffusé par l'InteractionSystem (RPC fiable par
##   fenêtre) ; toutes les machines animent les planches.
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
## Arrivée de l'enjambement (dedans, +Z).
const INSIDE_DIST := 1.0
## Un joueur plus proche que cela du zombie à la fenêtre se fait frapper.
const REACH := 1.8
## Le zombie frappe à travers la fenêtre s'il reste au plus ce nombre de planches.
const REACH_MAX_PLANKS := 3
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

var window_index := 0
var cell := Vector2i.ZERO
var inward := Vector3.FORWARD
## Hauteur de l'ouverture et graine des planches (déterministes).
var opening_height := MapBuilder.WALL_HEIGHT
@warning_ignore("shadowed_global_identifier")
var seed := 0
var zone := ""
var spawn_cells: Array = []
## Planches présentes (bit i = planche i).
var mask := BarricadeRules.FULL_MASK
## Serveur : zombie en train d'enjamber (un seul à la fois).
var vaulter: Zombie

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
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in BarricadeRules.PLANKS:
		var l: Array = LAYOUT[i]
		var b := Basis(Vector3.UP, rng.randf_range(-0.05, 0.05)) * Basis(Vector3.BACK, l[1] + rng.randf_range(-0.04, 0.04))
		_rest.append(Transform3D(b, Vector3(l[3], l[0] + rng.randf_range(-0.03, 0.03), PLANK_Z + l[2])))
		# Planche arrachée : à plat sur le sol, dehors, en vrac.
		var fb := Basis(Vector3.UP, rng.randf_range(-0.9, 0.9)) * Basis(Vector3.RIGHT, PI * 0.5)
		_fallen.append(Transform3D(fb, Vector3(rng.randf_range(-0.55, 0.55), 0.03 + i * 0.012, -rng.randf_range(0.75, 1.25))))
		_anim.append([0, 0.0])


func _ready() -> void:
	# L'encadrement fixe (allège, linteau, bois) est fusionné au décor par
	# PropBuilder._windows() ; ici : les planches, la barrière et la lueur.
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
	bm.size = PLANK_SIZE
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = bm
	_mm.instance_count = BarricadeRules.PLANKS
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 7
	for i in BarricadeRules.PLANKS:
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
	bbox.size = Vector3(1.0, opening_height, 1.0)
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
	mask = new_mask & BarricadeRules.FULL_MASK
	if _mm == null:
		return
	if not animate:
		for i in BarricadeRules.PLANKS:
			_anim[i] = [0, 0.0]
		_refresh_all()
		return
	var torn := false
	var fixed := false
	for i in BarricadeRules.PLANKS:
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
			fx.dust.burst(to_global(Vector3(0, 1.5, PLANK_Z - 0.1)), -inward, 6, 1.2, 0.5, 0.7, Color(0.3, 0.24, 0.17, 0.5))
	# Le son du marteau part à l'arrivée de la planche (fin d'animation).
	if torn or fixed:
		_animating = true
		set_process(true)


func _process(delta: float) -> void:
	var busy := false
	for i in BarricadeRules.PLANKS:
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
	for i in BarricadeRules.PLANKS:
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

## Là où se tient le zombie qui arrache les planches (dehors).
func tear_point() -> Vector3:
	var p := global_position - inward * TEAR_DIST
	return Vector3(p.x, global_position.y, p.z)


## Arrivée de l'enjambement (dedans).
func inside_point() -> Vector3:
	var p := global_position + inward * INSIDE_DIST
	return Vector3(p.x, global_position.y, p.z)


func interact_point() -> Vector3:
	return global_position + inward * 0.55 + Vector3.UP * 1.3


## Le point `pos` est-il du côté intérieur de la fenêtre ?
func is_inside(pos: Vector3) -> bool:
	return (pos - global_position).dot(inward) > 0.2


# --------------------------------------------------------------------------
# Interaction : réparation (serveur)
# --------------------------------------------------------------------------

func prompt(pid: int) -> String:
	if mask == BarricadeRules.FULL_MASK:
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
		if p == null or pd == null or pd.life != PlayerData.Life.ALIVE or not is_inside(p.global_position) \
				or _flat_dist(p.global_position, interact_point()) > REPAIR_RANGE:
			_repairers.erase(pid)
			continue
		if mask == BarricadeRules.FULL_MASK:
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
	var i := BarricadeRules.plank_to_repair(mask)
	if i < 0:
		return false
	set_mask(mask | (1 << i))
	broadcast_state()
	if pid > 0 and system.game.barricades:
		system.game.barricades.srv_award_repair(pid)
	return true


## Serveur : un zombie arrache une planche.
func srv_tear() -> bool:
	var i := BarricadeRules.plank_to_tear(mask)
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


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --------------------------------------------------------------------------
# Zombies (serveur) : approche, arrachage, coup à travers, enjambement
# --------------------------------------------------------------------------

func srv_zombie_barrier(z: Zombie, delta: float) -> void:
	var tp := tear_point()
	var to := tp - z.global_position
	to.y = 0.0
	var dist := to.length()
	var desired := Vector3.ZERO
	var face := atan2(inward.x, inward.z)
	if dist < 0.5:
		var victim := _victim_for(z)
		if victim and planks() <= REACH_MAX_PLANKS:
			z.target = victim
			z.barrier_attack()
			return
		if mask == 0:
			if vaulter == null or not is_instance_valid(vaulter) or not vaulter.is_alive() or vaulter.barricade != self:
				vaulter = z
				z.start_vault(tp, inside_point())
				return
		else:
			z.tear_t += delta
			if z.tear_t >= BarricadeRules.tear_interval(z.speed_class):
				z.tear_t = -randf() * BarricadeRules.TEAR_PAUSE_MAX
				srv_tear()
		# Petit recentrage sur le point d'arrachage.
		desired = to * 2.0
	else:
		z.tear_t = 0.0
		var spd: float = Zombie.SPEEDS[z.speed_class] * z.speed_mult
		desired = (to / dist + z._separation() * 0.6).normalized() * spd * clampf(dist * 1.5, 0.3, 1.0)
		face = atan2(to.x, to.z)
	var horiz := Vector3(z.velocity.x, 0.0, z.velocity.z).move_toward(desired, 12.0 * delta)
	z.velocity.x = horiz.x
	z.velocity.z = horiz.z
	z.yaw = lerp_angle(z.yaw, face, 1.0 - exp(-delta * 8.0))
	z.rotation.y = z.yaw


## Serveur : fin de l'enjambement.
func srv_vault_done(z: Zombie) -> void:
	if vaulter == z:
		vaulter = null


## Joueur debout collé à la fenêtre, à portée du zombie.
func _victim_for(z: Zombie) -> Player:
	var best: Player = null
	var best_d := REACH
	for p: Player in system.game.players.values():
		if not z._is_target_valid(p) or not is_inside(p.global_position):
			continue
		var d := _flat_dist(p.global_position, z.global_position)
		if d < best_d:
			best_d = d
			best = p
	return best
