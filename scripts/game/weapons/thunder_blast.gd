class_name ThunderBlast
extends Node3D
## Onde de choc du TONNERRE-7 (arme merveille de Kino, façon Thundergun).
##
## * Règles pures (testées) : sélection des zombies dans le cône, vitesse de
##   projection.
## * Serveur : `server_blast` tue d'un coup chaque zombie du cône en vue du
##   tireur et le projette (Combat.damage_zombie avec `fling` ->
##   ZombieManager.kill_flung, RPC fiable avec la vitesse : tous les clients
##   voient le même vol). Aucun dégât aux joueurs.
## * Toutes les machines : l'effet visuel (instance de ce nœud) : cône de
##   distorsion d'air qui s'étend, anneaux de choc, poussière, éclair.

## Hauteurs (au-dessus des pieds) testées sur chaque zombie : un zombie au
## contact est dans le cône même si son buste est sous l'axe de visée.
const BODY_SAMPLES := [0.35, 0.95, 1.6]
## Rayon « au contact » : tout zombie devant le tireur à moins de cette distance est touché.
const CLOSE_RADIUS := 1.2
const DURATION := 0.45
const RINGS := 3

static var _cone_mesh: Mesh
static var _ring_mesh: Mesh
static var _wave_shader: Shader

var _t := 0.0
var _length := 20.0
var _pap := false
var _cone: MeshInstance3D
var _cone_mat: ShaderMaterial
var _rings: Array[MeshInstance3D] = []
var _ring_mats: Array[ShaderMaterial] = []
var _light: OmniLight3D


# --------------------------------------------------------------------------
# Règles pures
# --------------------------------------------------------------------------

## Vrai si un zombie dont les pieds sont en `feet` est dans le cône (sommet
## `origin`, axe `dir` normalisé, portée `range`, ouverture totale `angle_deg`).
static func in_cone(origin: Vector3, dir: Vector3, feet: Vector3, blast_range: float, angle_deg: float) -> bool:
	var cos_half := cos(deg_to_rad(angle_deg * 0.5))
	for h in BODY_SAMPLES:
		var to: Vector3 = feet + Vector3.UP * h - origin
		var d := to.length()
		if d > blast_range:
			continue
		if d < 0.001:
			return true
		if to.dot(dir) / d >= cos_half:
			return true
	# Au contact : devant le tireur (demi-espace horizontal).
	var flat := Vector3(feet.x - origin.x, 0.0, feet.z - origin.z)
	var fdir := Vector3(dir.x, 0.0, dir.z)
	return flat.length() <= CLOSE_RADIUS and fdir.length_squared() > 0.0001 and flat.dot(fdir) > 0.0


## Indices des positions (pieds des zombies) situées dans le cône.
static func select(origin: Vector3, dir: Vector3, positions: Array, blast_range: float, angle_deg: float) -> Array[int]:
	var out: Array[int] = []
	for i in positions.size():
		if in_cone(origin, dir, positions[i], blast_range, angle_deg):
			out.append(i)
	return out


## Vitesse de projection d'un zombie (m/s) : d'autant plus violente qu'il est
## proche, vers l'arrière (loin du tireur, un peu dans l'axe du tir) et vers le
## haut. `jitter` dans [-1, 1] : variation d'angle et de force (serveur).
static func fling_velocity(origin: Vector3, dir: Vector3, feet: Vector3, blast_range: float, jitter := 0.0) -> Vector3:
	var away := Vector3(feet.x - origin.x, 0.0, feet.z - origin.z)
	var fdir := Vector3(dir.x, 0.0, dir.z).normalized()
	if fdir.length_squared() < 0.01:
		fdir = away.normalized() if away.length_squared() > 0.0001 else Vector3.FORWARD
	var push := (away.normalized() * 0.6 + fdir * 0.4).normalized() if away.length_squared() > 0.0001 else fdir
	push = push.rotated(Vector3.UP, jitter * 0.25)
	var k := 1.0 - clampf(away.length() / maxf(blast_range, 0.1), 0.0, 1.0)
	var horiz := lerpf(9.0, 21.0, k) * (1.0 + 0.12 * jitter)
	var up := lerpf(3.5, 7.5, k) * (1.0 - 0.1 * jitter)
	return push * horiz + Vector3.UP * up


# --------------------------------------------------------------------------
# Serveur
# --------------------------------------------------------------------------

## Serveur : applique l'onde de choc d'un tir validé (appelé par Combat.srv_fire).
static func server_blast(combat: Combat, pid: int, w: Dictionary, origin: Vector3, dir: Vector3) -> int:
	var s := WeaponDB.stats(w.id, w.pap)
	var game := combat.game
	var r: float = s.blast_range
	var targets: Array[Zombie] = []
	var positions := []
	for z: Zombie in game.zombies.alive:
		targets.append(z)
		positions.append(z.global_position)
	var space := game.get_world_3d().direct_space_state
	var killed := 0
	for i in select(origin, dir, positions, r, float(s.blast_angle)):
		var z: Zombie = targets[i]
		if not z.is_alive() or not _visible_from(space, origin, z.global_position):
			continue
		var vel := fling_velocity(origin, dir, z.global_position, r, randf_range(-1.0, 1.0))
		combat.damage_zombie(z.id, maxi(z.health, 1), pid, false, vel.normalized(), Combat.HitKind.SPECIAL, vel)
		killed += 1
	return killed


## Ligne de vue de l'œil du tireur vers le corps (pas à travers les murs).
static func _visible_from(space: PhysicsDirectSpaceState3D, origin: Vector3, feet: Vector3) -> bool:
	for h in [0.95, 1.6, 0.35]:
		var q := PhysicsRayQueryParameters3D.create(origin, feet + Vector3.UP * h, 1)
		if space.intersect_ray(q).is_empty():
			return true
	return false


# --------------------------------------------------------------------------
# Effet visuel (toutes les machines)
# --------------------------------------------------------------------------

## Joue l'onde de choc depuis `muzzle` dans la direction `dir`.
static func play_fx(fx: Fx, muzzle: Vector3, dir: Vector3, pap: bool, blast_range := 20.0) -> void:
	if fx == null or not fx.is_inside_tree():
		return
	dir = dir.normalized()
	var length := blast_range
	var q := PhysicsRayQueryParameters3D.create(muzzle, muzzle + dir * blast_range, 1)
	var hit := fx.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		length = maxf(muzzle.distance_to(hit.position), 1.5)
	var wave := ThunderBlast.new()
	wave._length = length
	wave._pap = pap
	fx.add_child(wave)
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.FORWARD
	wave.global_transform = Transform3D(Basis.looking_at(dir, up), muzzle)
	# Poussière soulevée au sol le long du cône (loin de la caméra du tireur),
	# quelques étincelles bleutées à la bouche.
	var tint := Color(0.75, 0.55, 1.0, 0.8) if pap else Color(0.6, 0.85, 1.0, 0.8)
	fx.sparks.burst(muzzle + dir * 0.3, dir, 8, 10.0, 0.35, 0.25, tint, 0.8)
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	for k in 14:
		var d := randf_range(3.0, maxf(length * 0.9, 3.5))
		var at := muzzle + dir * d + flat.cross(Vector3.UP) * randf_range(-0.4, 0.4) * d * 0.5
		at.y = randf_range(0.1, 0.5)
		var v := flat * randf_range(5.0, 10.0) + Vector3(randf_range(-1, 1), randf_range(0.5, 1.8), randf_range(-1, 1))
		fx.dust.emit(at, v, randf_range(0.7, 1.2), Color(0.3, 0.28, 0.25, 0.4), randf_range(3.0, 5.0))


func _ready() -> void:
	if _wave_shader == null:
		_wave_shader = _make_shader()
		# Cône ouvert : sommet au canon, base à 1 m (mis à l'échelle ensuite).
		var c := CylinderMesh.new()
		c.top_radius = 0.0
		c.bottom_radius = 1.0
		c.height = 1.0
		c.radial_segments = 20
		c.rings = 4
		c.cap_top = false
		c.cap_bottom = false
		_cone_mesh = c
		var t := TorusMesh.new()
		t.inner_radius = 0.82
		t.outer_radius = 1.0
		t.rings = 24
		t.ring_segments = 6
		_ring_mesh = t
	var tint := Color(0.7, 0.5, 1.0) if _pap else Color(0.55, 0.8, 1.0)
	_cone = MeshInstance3D.new()
	_cone.mesh = _cone_mesh
	_cone_mat = _material(tint, 0.9)
	_cone.material_override = _cone_mat
	_cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cone)
	for i in RINGS:
		var r := MeshInstance3D.new()
		r.mesh = _ring_mesh
		var m := _material(tint, 1.4)
		r.material_override = m
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Anneau perpendiculaire à l'axe du tir (-Z local).
		r.rotation.x = PI * 0.5
		add_child(r)
		_rings.append(r)
		_ring_mats.append(m)
	_light = OmniLight3D.new()
	_light.light_color = tint
	_light.omni_range = 9.0
	_light.shadow_enabled = false
	add_child(_light)
	_process(0.0)


func _material(tint: Color, strength: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _wave_shader
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("strength", strength)
	return m


func _process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / DURATION, 0.0, 1.0)
	if k >= 1.0:
		queue_free()
		return
	# Cône qui s'allonge très vite puis s'estompe.
	var reach := _length * ease(minf(k * 1.6, 1.0), 0.35)
	var half := tan(deg_to_rad(30.0))
	var radius := maxf(reach * half, 0.05)
	# Le cylindre est orienté selon Y (sommet en +Y) : on le couche, sommet au
	# canon (z = 0), base au bout de la portée (-Z).
	_cone.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(radius, reach, radius)), Vector3(0, 0, -reach * 0.5))
	_cone_mat.set_shader_parameter("fade", (1.0 - k) * (1.0 - k))
	for i in RINGS:
		var rk := clampf(k * 1.4 - float(i) * 0.18, 0.0, 1.0)
		var d := _length * ease(rk, 0.5)
		var rr := maxf(d * half, 0.08)
		_rings[i].position = Vector3(0, 0, -d)
		_rings[i].scale = Vector3(rr, rr * 0.35 + 0.05, rr)
		_rings[i].visible = rk > 0.0
		_ring_mats[i].set_shader_parameter("fade", (1.0 - rk) * 0.9)
	_light.position = Vector3(0, 0, -reach * 0.5)
	_light.light_energy = (1.0 - k) * 2.2


## Distorsion d'air : l'image derrière est déplacée par un bruit animé ; bord
## (effet de Fresnel) légèrement lumineux et teinté.
static func _make_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.55, 0.8, 1.0, 1.0);
uniform float strength = 1.0;
uniform float fade = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float rim = 1.0 - abs(dot(normalize(NORMAL), normalize(VIEW)));
	vec2 uv = UV * vec2(9.0, 4.0) + vec2(0.0, -TIME * 6.0);
	vec2 n = vec2(noise(uv), noise(uv + 17.3)) - 0.5;
	vec2 offs = n * 0.06 * strength * fade * (0.35 + rim);
	vec3 bg = textureLod(screen_tex, SCREEN_UV + offs, 1.5 * fade).rgb;
	float glow = pow(rim, 3.0) * 0.9 * fade * strength;
	ALBEDO = bg * (1.0 + 0.25 * fade) + tint.rgb * glow;
	ALPHA = clamp(fade * (0.4 + rim * 0.5), 0.0, 1.0);
}
"""
	return sh
