class_name Fx
extends Node3D
## Effets visuels locaux (chaque machine joue ses propres effets à partir des
## événements réseau) : impacts, sang, traçantes, flashs, décalques.
## Tout est mis en pool : aucune création de nœud pendant les combats.
## Style CUBIQUE (VoxelFx, GAME_CONCEPT.md § 4.19) : particules en cubes de
## 2,5 à 15 cm qui tournoient et disparaissent en rétrécissant, flamme de
## bouche et boule de feu en cubes, douilles en pavés de 2,5 cm, décalques
## (trous de balle, sang au sol, voir ThrowableSystem pour les traces
## d'explosion) en pixel art de 2,5 cm (trous) ou 5 cm (sang), alignés sur la
## grille et tournés par quarts de tour. Traçante : un seul pavé lumineux
## étiré (rayon de lumière, pas un objet).

const MAX_HOLES := 48
const MAX_BLOOD_DECALS := 40
const MAX_TRACERS := 24
const MAX_SHELLS := 32
const MAX_FLASHES := 6
## Pixel des décalques (m) : trous de balle, taches de sang.
const HOLE_PX := 0.025
const BLOOD_PX := 0.05
## Trou de balle : côté en pixels de 2,5 cm.
const HOLE_N := 4
## Taches de sang : côtés en pixels de 5 cm (petite, moyenne, grande).
const BLOOD_CLASSES := [12, 20, 28]

## Traçantes : couleur des balles, vitesse apparente (m/s) et longueur de la
## traînée (m).
const TRACER_COLOR := Color(1.0, 0.78, 0.45, 0.75)
const TRACER_SPEED := 170.0
const TRACER_STREAK := 6.0
## Douilles : durée de vie (s) et rebond.
const SHELL_LIFE := 2.5
const SHELL_BOUNCE := 0.35

var sparks: ParticlePool
var dust: ParticlePool
var blood: ParticlePool
## Morceaux de corps arrachés (démembrement).
var gibs: GibPool
## Éclats (béton, bois) : particules éclairées, tombent vite.
var debris: ParticlePool
## Boules de feu (explosions) : gros cubes lumineux qui montent et rétrécissent.
var flames: ParticlePool
var _holes: Array[Decal] = []
var _hole_i := 0
## Décalques réellement utilisés (réduit en qualité LOW, voir apply_quality).
var _hole_n := MAX_HOLES
var _blood_decals: Array[Decal] = []
var _blood_i := 0
var _blood_n := MAX_BLOOD_DECALS
## Classe de taille (BLOOD_CLASSES) de chaque tache, fixée une fois pour
## toutes : aucune texture ne change en jeu (atlas des décalques stable).
var _blood_class: PackedInt32Array = []
var _tracers: Array[MeshInstance3D] = []
var _tracer_i := 0
## Traçante i : origine, direction, longueur du trajet, tête (m), traînée (m),
## durée de vie restante (s ; faisceau fixe si > 0) .
var _tr_from: PackedVector3Array = []
var _tr_dir: PackedVector3Array = []
var _tr_len: PackedFloat32Array = []
var _tr_head: PackedFloat32Array = []
var _tr_streak: PackedFloat32Array = []
var _tr_beam: PackedFloat32Array = []
var _flash: OmniLight3D
var _flash_t := 0.0
## Douilles éjectées (pool) : nœud, vitesse, vie, hauteur du sol, a rebondi.
var _shells: Array[MeshInstance3D] = []
var _shell_vel: PackedVector3Array = []
var _shell_spin: PackedVector3Array = []
var _shell_life: PackedFloat32Array = []
var _shell_floor: PackedFloat32Array = []
var _shell_bounces: PackedInt32Array = []
var _shell_i := 0
## Flammes de bouche des autres joueurs (monde) : étoile de cubes (VoxelFx).
var _flashes: Array[MeshInstance3D] = []
var _flash_life: PackedFloat32Array = []
var _flashes_i := 0

static var _tex_cache: Dictionary = {}


func _ready() -> void:
	# Étincelles : cubes lumineux de 2,5 à 5 cm qui tournoient.
	sparks = ParticlePool.new().setup(160, _particle_mat(true, false, VoxelFx.SMALL), 0.035)
	sparks.gravity = 12.0
	sparks.drag = 0.8
	add_child(sparks)
	# Poussière, fumée de tir : touffes de cubes (5 à 15 cm) qui s'écartent en
	# grossissant, éclairées, translucides.
	dust = ParticlePool.new().setup(160, _particle_mat(false, true, VoxelFx.BIG), 0.07, VoxelFx.cluster("puff"))
	dust.gravity = -0.2
	dust.drag = 4.0
	dust.grow = 1.5
	dust.spin = 0.8
	add_child(dust)
	# Sang : cubes de 2,5 à 5 cm, éclairés (ne brillent pas dans le noir).
	blood = ParticlePool.new().setup(240, _particle_mat(false, true, VoxelFx.SMALL), 0.04)
	blood.gravity = 9.0
	blood.drag = 1.0
	add_child(blood)
	gibs = GibPool.new()
	gibs.name = "Gibs"
	add_child(gibs)
	debris = ParticlePool.new().setup(160, _particle_mat(false, true, VoxelFx.SMALL), 0.03)
	debris.gravity = 11.0
	debris.drag = 0.6
	add_child(debris)
	flames = ParticlePool.new().setup(96, _particle_mat(true, false, VoxelFx.BIG), 0.12)
	flames.gravity = -2.0
	flames.drag = 3.5
	flames.grow = -0.3
	flames.spin = 2.0
	add_child(flames)

	for i in MAX_HOLES:
		var d := Decal.new()
		d.texture_albedo = bullet_hole_texture()
		d.size = Vector3(HOLE_N * HOLE_PX, 0.2, HOLE_N * HOLE_PX)
		d.visible = false
		d.cull_mask = 1
		d.add_to_group(RenderQuality.DECAL_GROUP)
		add_child(d)
		_holes.append(d)
	for i in MAX_BLOOD_DECALS:
		var d := Decal.new()
		var cls := i % BLOOD_CLASSES.size()
		_blood_class.append(cls)
		var n: int = BLOOD_CLASSES[cls]
		d.texture_albedo = blood_splat_texture((i / BLOOD_CLASSES.size()) % 4, n)
		d.size = Vector3(n * BLOOD_PX, 0.6, n * BLOOD_PX)
		d.modulate = Color(0.55, 0.02, 0.02)
		d.visible = false
		d.cull_mask = 1
		d.add_to_group(RenderQuality.DECAL_GROUP)
		add_child(d)
		_blood_decals.append(d)
	add_to_group(RenderQuality.GROUP)
	apply_quality(RenderQuality.current())

	var tracer_mesh := BoxMesh.new()
	tracer_mesh.size = Vector3(0.014, 0.014, 1.0)
	for arr in [_tr_from, _tr_dir]:
		arr.resize(MAX_TRACERS)
	for arr in [_tr_len, _tr_head, _tr_streak, _tr_beam]:
		arr.resize(MAX_TRACERS)
	for i in MAX_TRACERS:
		var t := MeshInstance3D.new()
		t.mesh = tracer_mesh
		# Un matériau par traçante : chacune garde sa couleur.
		var tracer_mat := StandardMaterial3D.new()
		tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tracer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		tracer_mat.albedo_color = TRACER_COLOR
		t.material_override = tracer_mat
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.visible = false
		t.top_level = true
		add_child(t)
		_tracers.append(t)

	# Douilles : pavés laiton (fusil à pompe : rouge) en cubes de 2,5 cm.
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.62, 0.47, 0.2)
	brass.metallic = 0.9
	brass.roughness = 0.35
	var hull := StandardMaterial3D.new()
	hull.albedo_color = Color(0.5, 0.08, 0.06)
	hull.roughness = 0.6
	_shell_vel.resize(MAX_SHELLS)
	_shell_spin.resize(MAX_SHELLS)
	_shell_life.resize(MAX_SHELLS)
	_shell_floor.resize(MAX_SHELLS)
	_shell_bounces.resize(MAX_SHELLS)
	for i in MAX_SHELLS:
		var s := MeshInstance3D.new()
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.visible = false
		s.top_level = true
		s.set_meta("mats", [brass, hull])
		add_child(s)
		_shells.append(s)

	_flash_life.resize(MAX_FLASHES)
	for i in MAX_FLASHES:
		var f := MeshInstance3D.new()
		f.mesh = VoxelFx.flash_mesh(3, 6, 2, i)
		f.material_override = VoxelFx.flash_material()
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		f.visible = false
		f.top_level = true
		add_child(f)
		_flashes.append(f)

	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.72, 0.4)
	_flash.omni_range = 6.0
	_flash.light_energy = 0.0
	_flash.shadow_enabled = false
	add_child(_flash)


func _process(delta: float) -> void:
	for i in MAX_TRACERS:
		if _tracers[i].visible:
			_tick_tracer(i, delta)
	for i in MAX_FLASHES:
		if _flash_life[i] > 0.0:
			_flash_life[i] -= delta
			if _flash_life[i] <= 0.0:
				_flashes[i].visible = false
	for i in MAX_SHELLS:
		if _shell_life[i] > 0.0:
			_tick_shell(i, delta)
	if _flash_t > 0.0:
		_flash_t -= delta
		_flash.light_energy = maxf(_flash_t / 0.05, 0.0) * 2.5


func _tick_tracer(i: int, delta: float) -> void:
	var t := _tracers[i]
	if _tr_beam[i] > 0.0:
		# Faisceau fixe : de la bouche à l'impact, puis s'éteint.
		_tr_beam[i] -= delta
		if _tr_beam[i] <= 0.0:
			t.visible = false
		return
	_tr_head[i] += TRACER_SPEED * delta
	_place_tracer(i)


## Place la traînée i entre sa queue et sa tête (bornées au trajet).
func _place_tracer(i: int) -> void:
	var t := _tracers[i]
	var total := _tr_len[i]
	var head := minf(_tr_head[i], total)
	var tail := clampf(_tr_head[i] - _tr_streak[i], 0.0, total)
	if tail >= total - 0.01:
		t.visible = false
		return
	var from := _tr_from[i] + _tr_dir[i] * tail
	var to := _tr_from[i] + _tr_dir[i] * head
	_stretch(t, from, to)


## Étire la traînée entre `from` et `to`. Épaisseur proportionnelle à la
## distance de la caméra : ~2 px à l'écran de près comme de loin.
func _stretch(t: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var seg_len := maxf(from.distance_to(to), 0.001)
	var dir := (to - from) / seg_len
	var mid := (from + to) * 0.5
	var w := 1.0
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam:
		# Point de la traînée le plus proche de la caméra.
		var cp := cam.global_position
		var k := clampf((cp - from).dot(dir), 0.0, seg_len)
		var d := (from + dir * k).distance_to(cp)
		w = clampf(d * 0.004, 0.006, 0.08) / 0.014
	var b := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	# Échelle dans les axes PROPRES de la traînée (Basis.scaled agit dans les
	# axes du monde : les traçantes hors de l'axe Z restaient minuscules).
	t.global_transform = Transform3D(Basis(b.x * w, b.y * w, b.z * seg_len), mid)
	t.visible = true


func _tick_shell(i: int, delta: float) -> void:
	var s := _shells[i]
	_shell_life[i] -= delta
	if _shell_life[i] <= 0.0:
		s.visible = false
		return
	var v := _shell_vel[i]
	var p := s.global_position
	if _shell_bounces[i] < 3:
		v.y -= 9.8 * delta
		p += v * delta
		s.rotation += _shell_spin[i] * delta
		if p.y <= _shell_floor[i]:
			p.y = _shell_floor[i]
			_shell_bounces[i] += 1
			if _shell_bounces[i] == 1:
				# Tintement de la douille au sol (son du barillet, grave et bref).
				Audio.play_3d("shell", p, -20.0, 0.25, 6, randf_range(1.5, 1.9))
			v = Vector3(v.x * 0.45, -v.y * SHELL_BOUNCE, v.z * 0.45)
			_shell_spin[i] *= 0.5
			if absf(v.y) < 0.4:
				_shell_bounces[i] = 3
				# Couchée à plat, d'un quart de tour (pavé posé sur une face).
				s.rotation = Vector3(PI * 0.5, snappedf(s.rotation.y, PI * 0.5), 0.0)
		_shell_vel[i] = v
		s.global_position = p


## Préréglage de qualité (RenderQuality) : nombre de décalques en rotation,
## distance de fondu. Les décalques au-delà du quota sont masqués.
func apply_quality(q: Dictionary) -> void:
	_hole_n = clampi(roundi(MAX_HOLES * float(q.decals)), 1, MAX_HOLES)
	_blood_n = clampi(roundi(MAX_BLOOD_DECALS * float(q.decals)), 1, MAX_BLOOD_DECALS)
	for i in MAX_HOLES:
		RenderQuality.apply_decal(_holes[i], q)
		if i >= _hole_n:
			_holes[i].visible = false
	for i in MAX_BLOOD_DECALS:
		RenderQuality.apply_decal(_blood_decals[i], q)
		if i >= _blood_n:
			_blood_decals[i].visible = false
	_hole_i %= _hole_n
	_blood_i %= _blood_n


## Surface d'un objet touché par une balle : "metal", "wood", "concrete"...
## Méta "surface" posée sur la forme de collision (décor : clé de matériau
## PropBuilder) ou sur le corps, sinon déduite du type d'objet.
static func surface_of(col: Object, shape_index := 0) -> String:
	if col == null:
		return "concrete"
	if col is CollisionObject3D:
		var co := col as CollisionObject3D
		var owner_id := co.shape_find_owner(shape_index)
		if owner_id >= 0:
			var shape_node: Variant = co.shape_owner_get_owner(owner_id)
			if shape_node is Node and (shape_node as Node).has_meta("surface"):
				return surface_kind(String(shape_node.get_meta("surface")))
		if co.has_meta("surface"):
			return surface_kind(String(co.get_meta("surface")))
		var parent := co.get_parent()
		if parent is MysteryBox or parent is Barricade:
			return "wood"
		if parent is TeleporterMainframe or parent is ElectricTrap:
			return "metal"
		if parent is Door:
			return "wood"
	return "concrete"


## Famille d'effet d'impact pour une clé de matériau du décor.
static func surface_kind(key: String) -> String:
	if key in ["metal", "wood", "concrete", "flesh", "dirt"]:
		return key
	for w in ["crate", "wood", "door", "plank", "seat", "bench", "bed", "stage", "rack"]:
		if key.contains(w):
			return "wood"
	for m in ["steel", "barrel", "metal", "pipe", "generator", "brass", "iron", "cage"]:
		if key.contains(m):
			return "metal"
	return "concrete"


## Impact de balle sur le décor, selon la surface : béton (poussière et
## éclats), métal (gerbe d'étincelles), bois (échardes), terre.
func impact(pos: Vector3, normal: Vector3, with_sound := true, surface := "concrete") -> void:
	var n := normal.normalized()
	var p := pos + n * 0.02
	match surface:
		"metal":
			sparks.burst(p, n, 10, 7.0, 0.8, 0.3, Color(1.0, 0.7, 0.3, 0.95), 0.8)
			sparks.burst(p, n, 3, 2.0, 0.5, 0.12, Color(1.0, 0.95, 0.8, 1.0), 1.6)
			dust.burst(p + n * 0.03, n, 1, 0.4, 0.4, 0.5, Color(0.35, 0.35, 0.35, 0.25))
		"wood":
			debris.burst(p, n, 7, 3.2, 0.7, 0.8, Color(0.42, 0.26, 0.12, 1.0), 1.3)
			dust.burst(p + n * 0.04, n, 2, 0.6, 0.5, 0.7, Color(0.45, 0.34, 0.22, 0.35))
		"dirt":
			debris.burst(p, n, 6, 2.5, 0.6, 0.7, Color(0.2, 0.15, 0.1, 1.0), 1.4)
			dust.burst(p + n * 0.05, n, 4, 0.8, 0.5, 1.0, Color(0.3, 0.24, 0.17, 0.45), 1.4)
		_:
			# Béton, plâtre, carrelage : nuage de poussière, éclats, rares étincelles.
			dust.burst(p + n * 0.03, n, 4, 0.9, 0.45, 1.0, Color(0.52, 0.49, 0.44, 0.42), 1.3)
			debris.burst(p, n, 5, 3.0, 0.6, 0.6, Color(0.36, 0.34, 0.31, 1.0))
			sparks.burst(p, n, 2, 4.5, 0.6, 0.18, Color(0.9, 0.55, 0.2, 0.8))
	var d := _holes[_hole_i]
	_hole_i = (_hole_i + 1) % _hole_n
	_place_decal(d, pos, n, HOLE_PX)
	if with_sound:
		# Sons CC0 par matière (la terre et le reste sonnent comme le béton).
		var snd := surface if surface in ["metal", "wood"] else "concrete"
		Audio.play_3d("impact_%s_%d" % [snd, 1 + randi() % 2], pos, -12.0, 0.12, 4)


## Surface au point d'impact annoncé par le serveur (tirs des autres joueurs) :
## court rayon le long de la normale.
func surface_at(pos: Vector3, normal: Vector3) -> String:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + normal * 0.05, pos - normal * 0.05, 1)
	var r := space.intersect_ray(q)
	if r.is_empty():
		return "concrete"
	return surface_of(r.collider, int(r.get("shape", 0)))


## Fumée légère à la bouche du canon après un tir.
func smoke(pos: Vector3, dir: Vector3, amount := 1) -> void:
	dust.burst(pos + dir * 0.05, dir * 0.35 + Vector3.UP * 0.3, amount, 0.5, 0.35, 0.9, Color(0.6, 0.6, 0.6, 0.16), 1.3)


## Douille éjectée (pool) : chute, rebonds sur le sol, tintement, disparition.
func eject_shell(pos: Vector3, vel: Vector3, kind: String) -> void:
	if kind == "":
		return
	var i := _shell_i
	_shell_i = (_shell_i + 1) % MAX_SHELLS
	var s := _shells[i]
	s.mesh = _shell_mesh(kind)
	var mats: Array = s.get_meta("mats")
	s.material_override = mats[1] if kind == "shotgun" else mats[0]
	s.global_position = pos
	s.rotation = Vector3(0, randf() * TAU, PI * 0.5)
	s.visible = true
	_shell_vel[i] = vel
	_shell_spin[i] = Vector3(randf_range(-20, 20), randf_range(-8, 8), randf_range(-25, 25))
	_shell_life[i] = SHELL_LIFE
	_shell_bounces[i] = 0
	# Hauteur du sol sous la douille (cartes plates : un rayon vers le bas).
	var q := PhysicsRayQueryParameters3D.create(pos, pos + Vector3.DOWN * 3.0, 1)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	_shell_floor[i] = (r.position.y + 0.0125) if not r.is_empty() else pos.y - 1.5


static var _shell_meshes: Dictionary = {}


## Douille : pavé d'un cube de 2,5 cm de section, 1 (pistolet), 2 (fusil)
## ou 3 (fusil à pompe) cubes de long.
static func _shell_mesh(kind: String) -> Mesh:
	if _shell_meshes.has(kind):
		return _shell_meshes[kind]
	var b := BoxMesh.new()
	var cubes: int = {"pistol": 1, "rifle": 2, "shotgun": 3}.get(kind, 1)
	b.size = Vector3(VoxelFx.GRID, VoxelFx.GRID * cubes, VoxelFx.GRID)
	_shell_meshes[kind] = b
	return b


## Gerbe de sang (touche un zombie). `dir` = direction de la balle.
func blood_hit(pos: Vector3, dir: Vector3, amount := 1.0) -> void:
	blood.burst(pos, -dir * 0.3 + Vector3.UP * 0.4, int(8 * amount), 3.0, 0.8, 0.7, Color(0.45, 0.0, 0.0, 0.95))
	blood.burst(pos, dir, int(4 * amount), 4.0, 0.4, 0.5, Color(0.35, 0.0, 0.0, 0.9), 1.3)


## Tache de sang au sol ou sur un mur (mort d'un zombie...). Pixels de 5 cm :
## la taille voulue (1,2 m × `size_scale`) choisit la classe la plus proche
## (BLOOD_CLASSES), puis la prochaine tache de cette classe dans la rotation.
func blood_decal(pos: Vector3, normal := Vector3.UP, size_scale := 1.0) -> void:
	var want := 1.2 * size_scale / BLOOD_PX
	var cls := 0
	for k in BLOOD_CLASSES.size():
		if absf(float(BLOOD_CLASSES[k]) - want) < absf(float(BLOOD_CLASSES[cls]) - want):
			cls = k
	var i := _blood_i
	for k in _blood_n:
		var j := (_blood_i + k) % _blood_n
		if _blood_class[j] == cls:
			i = j
			break
	_blood_i = (i + 1) % _blood_n
	_place_decal(_blood_decals[i], pos, normal, BLOOD_PX)


## Traçante de `from` (bouche du canon) à `to` (point touché) : une traînée
## lumineuse file à TRACER_SPEED m/s et s'arrête exactement à l'impact.
## `beam` > 0 : faisceau fixe de toute la longueur pendant `beam` s.
func tracer(from: Vector3, to: Vector3, color := TRACER_COLOR, beam := 0.0) -> void:
	var seg_len := from.distance_to(to)
	if seg_len < 0.3:
		return
	var i := _tracer_i
	_tracer_i = (_tracer_i + 1) % MAX_TRACERS
	var t := _tracers[i]
	(t.material_override as StandardMaterial3D).albedo_color = color
	_tr_from[i] = from
	_tr_dir[i] = (to - from) / seg_len
	_tr_len[i] = seg_len
	_tr_beam[i] = beam
	_tr_streak[i] = clampf(seg_len * 0.5, 0.4, TRACER_STREAK)
	if beam > 0.0:
		_stretch(t, from, to)
		return
	# Première image : la traînée sort déjà de la bouche (visible même de près).
	_tr_head[i] = minf(_tr_streak[i], seg_len)
	_place_tracer(i)


## Tir d'un autre joueur : étoile de cubes à la bouche de son arme (pointes
## le long du tir), lumière brève et fumée.
func muzzle_flash(pos: Vector3, dir := Vector3.ZERO) -> void:
	_flash.global_position = pos
	_flash.light_color = Color(1.0, 0.72, 0.4)
	_flash.omni_range = 6.0
	_flash_t = 0.05
	_flash.light_energy = 2.5
	var i := _flashes_i
	_flashes_i = (_flashes_i + 1) % MAX_FLASHES
	var f := _flashes[i]
	var fwd := dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	f.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP if absf(fwd.y) < 0.99 else Vector3.RIGHT), pos + fwd * 0.05)
	VoxelFx.reroll_flash(f, randf_range(0.15, 0.22), 0.15, 0.05)
	f.visible = true
	_flash_life[i] = 0.05
	if dir != Vector3.ZERO:
		smoke(pos, dir, 1)


## Décalque posé sur la surface de normale `normal` : quand la surface est
## droite (sol, mur), pixels alignés sur les axes du monde et centre sur la
## grille de `px` m dans son plan ; tourné d'un quart de tour au hasard.
func _place_decal(d: Decal, pos: Vector3, normal: Vector3, px: float) -> void:
	var up := normal.normalized()
	var ax := up.abs()
	var main := Vector3.UP * signf(up.y)
	if ax.x > ax.y and ax.x >= ax.z:
		main = Vector3.RIGHT * signf(up.x)
	elif ax.z > ax.y and ax.z > ax.x:
		main = Vector3.BACK * signf(up.z)
	var straight := main.dot(up) > 0.97
	if straight:
		up = main
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(up).normalized()
	var z := x.cross(up).normalized()
	var b := Basis(x, up, z).rotated(up, PI * 0.5 * (randi() % 4))
	var at := pos
	if straight:
		var g := pos.snapped(Vector3.ONE * px)
		at = g - up * up.dot(g - pos)
	d.global_transform = Transform3D(b, at)
	d.visible = true


# --------------------------------------------------------------------------
# Matériaux et textures générés (aucun fichier externe)
# --------------------------------------------------------------------------

## Matériau des particules cubiques d'un pool (VoxelFx). `glow` : étincelles
## et flammes, cubes lumineux (non éclairés, couleur au-delà de 1 : lueur de
## l'écran) mais FONDUS, pas additifs : un cube orange reste orange devant un
## mur clair au lieu de virer au blanc ; poussière, sang, éclats éclairés par
## la scène (`lit`) pour ne pas briller dans le noir. `max_cube` : côté
## maximal d'un cube (m). La taille de fin de vie est réglée par le pool
## (rétrécissement), l'alpha de la couleur reste la transparence.
static func _particle_mat(glow: bool, lit := false, max_cube: float = VoxelFx.BIG) -> Material:
	if glow:
		return VoxelFx.material("mix", {"max": max_cube, "shrink": false, "energy": 1.25, "shade": false})
	return VoxelFx.material("lit" if lit else "mix", {"max": max_cube, "shrink": false, "edge": 0.3})


## Point doux (lueur de la boule du chien éclair, DogLightning, et
## poussière du menu) : seul reste des anciennes textures d'effets.
static func soft_dot_texture() -> Texture2D:
	if _tex_cache.has("dot"):
		return _tex_cache.dot
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - n * 0.5 + 0.5, y - n * 0.5 + 0.5).length() / (n * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache.dot = tex
	return tex


## Trou de balle en pixel art : HOLE_N x HOLE_N pixels (2,5 cm), cœur noir
## de 2 x 2, bord ébréché gris foncé, coins vides.
static func bullet_hole_texture() -> Texture2D:
	if _tex_cache.has("hole"):
		return _tex_cache.hole
	var n := HOLE_N
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in n:
		for x in n:
			var corner := (x == 0 or x == n - 1) and (y == 0 or y == n - 1)
			var core := x >= 1 and x <= n - 2 and y >= 1 and y <= n - 2
			if core:
				img.set_pixel(x, y, Color(0.03, 0.028, 0.026, 1.0))
			elif not corner:
				img.set_pixel(x, y, Color(0.16, 0.15, 0.14, 0.75))
	# Un coin ébréché (irrégularité fixe).
	img.set_pixel(n - 1, 0, Color(0.16, 0.15, 0.14, 0.6))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache.hole = tex
	return tex


## Tache de sang en pixel art : `n` x `n` pixels (5 cm chacun là où Fx la
## pose), mare centrale et gouttes autour, deux tons. Variante 0..3.
static func blood_splat_texture(variant: int, n := 32) -> Texture2D:
	var key := "blood%d_%d" % [variant, n]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 100 + variant
	var c := Vector2(n, n) * 0.5
	var blobs := [[c, n * 0.24]]
	for i in 12:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(0.12, 0.42) * n
		blobs.append([c + Vector2.from_angle(ang) * dist, rng.randf_range(0.03, 0.1) * n])
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5)
			var inside := false
			var deep := false
			for b in blobs:
				var d: float = p.distance_to(b[0]) / maxf(float(b[1]), 0.6)
				if d <= 1.0:
					inside = true
					deep = deep or d < 0.55
			if inside:
				# Deux tons par pixel : cœur plus sombre, bords plus clairs.
				var shade := 0.75 if deep else 1.0
				shade *= 0.9 + 0.1 * float((x * 7 + y * 13 + variant) % 3) / 2.0
				img.set_pixel(x, y, Color(shade, shade, shade, 0.92))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


## Trace noire d'explosion en pixel art (ThrowableSystem) : `n` x `n`
## pixels, disque irrégulier plus noir au centre.
static func scorch_texture(n := 52) -> Texture2D:
	var key := "scorch%d" % n
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	var c := Vector2(n, n) * 0.5
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5) - c
			var r := p.length() / (n * 0.5)
			var jag := 0.12 * sin(p.angle() * 5.0 + 1.3) + rng.randf_range(-0.08, 0.08)
			if r > 0.85 + jag:
				continue
			# Paliers d'opacité (pas de dégradé lisse : pixel art).
			var a := 1.0 if r < 0.35 else (0.75 if r < 0.6 else 0.45)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


## Flash lumineux coloré (téléportation...).
func explosion_light(pos: Vector3, color: Color) -> void:
	_flash.global_position = pos
	_flash.light_color = color
	_flash.omni_range = 8.0
	_flash_t = 0.25
	sparks.burst(pos, Vector3.UP, 20, 4.0, 1.0, 0.6, Color(color.r, color.g, color.b, 0.9))


## Explosion (arme spéciale, pièges...).
func explosion(pos: Vector3, radius: float) -> void:
	sparks.burst(pos, Vector3.UP, 26, 7.0, 1.0, 0.6, Color(1.0, 0.5, 0.15, 0.9), 1.6)
	fireball(pos, clampf(radius * 0.4, 0.6, 1.6))
	dust.burst(pos, Vector3.UP, 12, 2.0, 1.0, 1.4, Color(0.3, 0.28, 0.25, 0.5), 2.5)
	_flash.global_position = pos + Vector3.UP * 0.5
	_flash.omni_range = radius * 4.0
	_flash_t = 0.12
	Audio.play_3d("explosion", pos, 2.0, 0.15)


## Boule de feu en cubes : gros cubes lumineux (jusqu'à 15 cm) projetés dans
## toutes les directions, du blanc-jaune au rouge sombre, qui montent et
## rétrécissent. `size` : rayon atteint (m) à peu près.
func fireball(pos: Vector3, size: float) -> void:
	var n := roundi(18.0 * size)
	flames.burst(pos, Vector3.ZERO, n, 4.5 * size, 1.0, 0.35, Color(1.0, 0.72, 0.25, 0.9), 1.2)
	flames.burst(pos, Vector3.UP * 0.3, roundi(n * 0.8), 3.0 * size, 1.0, 0.5, Color(1.0, 0.38, 0.06, 0.9), 1.0)
	flames.burst(pos + Vector3.UP * 0.2, Vector3.UP, roundi(n * 0.4), 1.5 * size, 0.8, 0.7, Color(0.45, 0.1, 0.03, 0.85), 0.9)


## Terre projetée quand un zombie sort du sol.
func dirt_burst(pos: Vector3) -> void:
	dust.burst(pos + Vector3.UP * 0.1, Vector3.UP, 10, 1.4, 0.8, 1.6, Color(0.22, 0.17, 0.12, 0.6), 2.0)
	blood.burst(pos + Vector3.UP * 0.05, Vector3.UP, 14, 3.5, 0.7, 0.9, Color(0.16, 0.12, 0.08, 1.0), 1.2)
	blood_decal(pos + Vector3.UP * 0.1, Vector3.UP, 0.7)


## Hauteur du sol sous un point (0 sur les cartes plates ou hors partie).
static func floor_under(pos: Vector3) -> float:
	var g := Game.instance
	return g.layout.floor_y(pos) if g != null and g.layout != null else 0.0
