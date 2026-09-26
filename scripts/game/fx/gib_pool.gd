class_name GibPool
extends Node3D
## Morceaux de corps arrachés (démembrement façon BO1) : bras, jambes, éclats
## de crâne. Purement visuel, joué localement par chaque machine.
##
## Pool fixe de MAX_GIBS nœuds (aucune création pendant les combats) : un
## nouveau morceau recycle le plus ancien. Physique simple : gravité, rebonds
## amortis sur le sol (cartes plates, y = 0), rotation qui s'éteint au sol.
## Chaque morceau reste LIFE secondes puis rétrécit et disparaît.

const MAX_GIBS := 24
const LIFE := 6.0
const SHRINK_TIME := 0.6
const GRAVITY := 11.0
## Demi-épaisseur tenue au-dessus du sol.
const FLOOR_Y := 0.05

var _nodes: Array[MeshInstance3D] = []
var _vel: PackedVector3Array = []
var _spin: PackedVector3Array = []
var _age: PackedFloat32Array = []
var _landed: PackedByteArray = []
var _next := 0
var _active := 0
var _chunk_meshes: Array[Mesh] = []
## Membres à construire : [variante, os, repère, vitesse, rotation].
var _queue: Array = []
const BUILD_PER_FRAME := 3


func _ready() -> void:
	top_level = true
	_vel.resize(MAX_GIBS)
	_spin.resize(MAX_GIBS)
	_age.resize(MAX_GIBS)
	_landed.resize(MAX_GIBS)
	for i in MAX_GIBS:
		var mi := MeshInstance3D.new()
		mi.visible = false
		mi.material_override = ZombieModel.material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.top_level = true
		add_child(mi)
		_nodes.append(mi)
		_age[i] = -1.0
	# Éclats de crâne / chair (tête qui éclate).
	for c in [Color(0.36, 0.34, 0.28), Color(0.32, 0.03, 0.03), Color(0.2, 0.02, 0.02)]:
		var parts := [["head", Vector3(0.07, 0.05, 0.06), Vector3.ZERO, c, 0.0]]
		_chunk_meshes.append(RigBuilder.build_static(parts, ["head"]))


## Morceaux visibles ou sur le point d'apparaître (tests, mesures).
func active_count() -> int:
	return _active + _queue.size()


## Membre arraché du zombie `variant` (os `bones`, voir ZombieModel.limb_mesh).
## Le mesh est construit plus tard, BUILD_PER_FRAME par image au plus : une
## explosion qui déchiquette dix zombies ne coûte rien sur l'image du coup.
func spawn_limb(variant: int, bones: Array, xf: Transform3D, vel: Vector3, spin: Vector3) -> void:
	if _queue.size() >= MAX_GIBS:
		_queue.pop_front()
	_queue.append([variant, bones, xf, vel, spin])


## Lance un morceau `mesh` depuis `xf` (repère monde) à la vitesse `vel`.
func spawn(mesh: Mesh, xf: Transform3D, vel: Vector3, spin: Vector3) -> void:
	var i := _next
	_next = (_next + 1) % MAX_GIBS
	var mi := _nodes[i]
	if _age[i] < 0.0:
		_active += 1
	mi.mesh = mesh
	mi.global_transform = xf.orthonormalized()
	mi.visible = true
	_vel[i] = vel
	_spin[i] = spin
	_age[i] = 0.0
	_landed[i] = 0


## Tête qui éclate : quelques éclats projetés depuis `pos`.
func head_burst(pos: Vector3, dir: Vector3) -> void:
	for k in 4:
		var v := (dir * 1.5 + Vector3(randf_range(-1.5, 1.5), randf_range(1.5, 3.5), randf_range(-1.5, 1.5)))
		var xf := Transform3D(Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, 0.0)), pos)
		spawn(_chunk_meshes[k % _chunk_meshes.size()], xf, v, Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9)))


func _process(delta: float) -> void:
	for k in mini(_queue.size(), BUILD_PER_FRAME):
		var q: Array = _queue.pop_front()
		spawn(ZombieModel.limb_mesh(q[0], q[1]), q[2], q[3], q[4])
	if _active == 0:
		return
	var fx := get_parent() as Fx
	for i in MAX_GIBS:
		if _age[i] < 0.0:
			continue
		_age[i] += delta
		var mi := _nodes[i]
		if _age[i] >= LIFE:
			_age[i] = -1.0
			mi.visible = false
			mi.mesh = null
			_active -= 1
			continue
		var xf := mi.global_transform
		if _landed[i] < 2:
			_vel[i].y -= GRAVITY * delta
			xf.origin += _vel[i] * delta
			if xf.origin.y < FLOOR_Y:
				xf.origin.y = FLOOR_Y
				if _landed[i] == 0:
					# Première chute : le morceau se couche à plat (son axe
					# long, -Y local, à l'horizontale) ; flaque de sang dessous.
					var yv := xf.basis.y
					yv.y = 0.0
					yv = yv.normalized() if yv.length() > 0.1 else Vector3.RIGHT
					var xv := yv.cross(Vector3.UP).normalized()
					xf.basis = Basis(xv, yv, xv.cross(yv))
					_spin[i] = Vector3.ZERO
					if fx:
						fx.blood_decal(Vector3(xf.origin.x, 0.05, xf.origin.z), Vector3.UP, randf_range(0.25, 0.4))
				if absf(_vel[i].y) < 1.2:
					_landed[i] = 2
					_vel[i] = Vector3.ZERO
				else:
					_landed[i] = 1
					_vel[i] = Vector3(_vel[i].x * 0.45, -_vel[i].y * 0.3, _vel[i].z * 0.45)
					_spin[i] *= 0.5
			var s := _spin[i]
			if s.length_squared() > 0.0001 and _landed[i] < 2:
				xf.basis = Basis.from_euler(s * delta) * xf.basis
		var left := LIFE - _age[i]
		if left < SHRINK_TIME:
			var k := maxf(left / SHRINK_TIME, 0.02)
			xf.basis = xf.basis.orthonormalized().scaled(Vector3(k, k, k))
		mi.global_transform = xf
