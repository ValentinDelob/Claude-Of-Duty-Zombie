extends AutotestScenario
## @rendu : a besoin du rendu (lancé avec fenêtre hors écran par check.sh).
## Formes de collision d'un zombie dessinées par-dessus le modèle (captures à
## faire valider, retirées une fois la fonction livrée) :
##   - DÉPLACEMENT, en cyan : capsule du CharacterBody3D ; au sol, en vert :
##     rayon d'érosion du navmesh (MeshNav), en magenta : portée de la
##     séparation entre zombies ;
##   - TOUCHE des tirs : corps en rouge, tête en jaune, bras (avant-bras et
##     haut du bras) en orange.
## Vues orthographiques de face, de dessus et de profil ; trois zombies côte
## à côte : marcheur (bras tendus), coureur, sprinteur.

var H := AutotestHelpers
var game: Game
var cam: Camera3D
var _zs: Array[Zombie] = []
var _draw: MeshInstance3D
var _im: ImmediateMesh
var _segs := {}   # couleur -> segments (paires de points)
var _mats := {}
## Quai du BUNKER K-7 (scène dégagée, comme zombie_look).
const STAGE := Vector3(33.5, 0.0, 4.6)
const GAP := 1.6
const MOVE := Color(0.0, 0.95, 1.0)
const NAV := Color(0.25, 1.0, 0.3)
const SEP := Color(1.0, 0.25, 1.0)
const HIT_BODY := Color(1.0, 0.1, 0.05)
const HIT_HEAD := Color(1.0, 0.95, 0.1)
const HIT_ARM := Color(1.0, 0.38, 0.0)


func run() -> void:
	timeout_sec = 120
	var p := await H.start_solo_game(self, "bunker_k7")
	if p == null:
		return
	game = Game.instance
	game.combat.debug_invulnerable = true
	game.rounds.paused = true
	await H.clear_zombies(self)
	game.hud.visible = false
	var base := STAGE
	# Joueur derrière la caméra (à 4 m des zombies).
	p.teleport_to(base + Vector3(0, 0.05, 6.0))
	var classes := [0, 2, 3]
	for k in classes.size():
		# Bras tendus (ZombieAnim.Arms.REACH) : la pose la plus large en marche.
		var z: Zombie
		for v in 60:
			z = Zombie.new()
			z.setup(62001 + k, v * 3 + k, classes[k], false)
			game.zombies.add_child(z)
			if z.anim.arm_style == ZombieAnim.Arms.REACH:
				break
			z.free()
		z.global_position = base + Vector3((k - 1) * GAP, 0, 0)
		z.state = Zombie.State.CHASE
		z.anim_speed = Zombie.SPEEDS[classes[k]]
		_zs.append(z)
	print("[hitbox_look] styles de bras : %s" % [_zs.map(func(z): return z.anim.arm_style)])
	_im = ImmediateMesh.new()
	_draw = MeshInstance3D.new()
	_draw.mesh = _im
	game.add_child(_draw)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.far = 50.0
	game.add_child(cam)
	cam.make_current()
	var mid := base + Vector3(0, 0.95, 0)
	# Éclairage d'appoint : modèles lisibles sous le tracé.
	var lamp := OmniLight3D.new()
	lamp.omni_range = 7.0
	lamp.light_energy = 2.5
	game.add_child(lamp)
	lamp.global_position = mid + Vector3(0, 1.5, 2.5)
	# Face : le modèle regarde vers +Z.
	await _shot("face", mid + Vector3(0, 0, 4), mid, Vector3.UP, 2.4)
	await _shot("dessus", mid + Vector3(0, 8, 0), mid, Vector3.FORWARD, 2.4)
	for z in _zs:
		z.yaw = PI * 0.5
		z.rotation.y = z.yaw
	await _shot("profil", mid + Vector3(0, 0, 4), mid, Vector3.UP, 2.4)
	for z in _zs:
		z.queue_free()
	_draw.queue_free()
	p.camera.make_current()
	cam.queue_free()


## Fige la démarche à mi-pas (bras tendus visibles), dessine et capture.
func _shot(shot: String, from: Vector3, to: Vector3, up: Vector3, size: float) -> void:
	cam.size = size
	cam.look_at_from_position(from, to, up)
	for z in _zs:
		z.gait_phase = PI * 0.5
	await frames(3)
	_redraw()
	await frames(2)
	await at.screenshot(shot)


func _redraw() -> void:
	_segs.clear()
	for z in _zs:
		var cs := z.body_shape
		var cap := cs.shape as CapsuleShape3D
		_capsule(cs.global_transform, cap.radius, cap.height, MOVE)
		var ground := Transform3D(Basis.IDENTITY, z.global_position + Vector3.UP * 0.02)
		_circle(ground, Vector3.RIGHT, Vector3.BACK, 0.4, NAV)
		# Demi-portée de la séparation : deux cercles qui se touchent = la
		# séparation commence à repousser.
		var sep: Variant = z.get("sep_range")
		_circle(ground, Vector3.RIGHT, Vector3.BACK, (float(sep) if sep != null else sqrt(0.8)) * 0.5, SEP)
		var hb := z.hit_body.get_child(0) as CollisionShape3D
		var hc := hb.shape as CapsuleShape3D
		_capsule(hb.global_transform, hc.radius, hc.height, HIT_BODY)
		var hh := z.hit_head.get_child(0) as CollisionShape3D
		_sphere(hh.global_transform, (hh.shape as SphereShape3D).radius, HIT_HEAD)
		for ha in z.hit_arms + z.hit_upper_arms:
			var ac := ha.get_child(0) as CollisionShape3D
			var acap := ac.shape as CapsuleShape3D
			_capsule(ac.global_transform, acap.radius, acap.height, HIT_ARM)
	_im.clear_surfaces()
	for c: Color in _segs:
		if not _mats.has(c):
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.albedo_color = c
			m.no_depth_test = true
			m.disable_fog = true
			m.render_priority = 10
			_mats[c] = m
		_im.surface_begin(Mesh.PRIMITIVE_LINES, _mats[c])
		for v: Vector3 in _segs[c]:
			_im.surface_add_vertex(v)
		_im.surface_end()


func _line(a: Vector3, b: Vector3, c: Color) -> void:
	if not _segs.has(c):
		_segs[c] = PackedVector3Array()
	_segs[c].append(a)
	_segs[c].append(b)


## Cercle de rayon `r` dans le plan (u, v) du repère `xf`.
func _circle(xf: Transform3D, u: Vector3, v: Vector3, r: float, c: Color, from := 0.0, to := TAU) -> void:
	var seg := 40
	for i in seg:
		var a0 := lerpf(from, to, float(i) / seg)
		var a1 := lerpf(from, to, float(i + 1) / seg)
		_line(xf * ((u * cos(a0) + v * sin(a0)) * r), xf * ((u * cos(a1) + v * sin(a1)) * r), c)


func _capsule(xf: Transform3D, r: float, h: float, c: Color) -> void:
	var half := maxf(h * 0.5 - r, 0.0)
	var top := xf * Transform3D(Basis.IDENTITY, Vector3.UP * half)
	var bot := xf * Transform3D(Basis.IDENTITY, Vector3.DOWN * half)
	_circle(top, Vector3.RIGHT, Vector3.BACK, r, c)
	_circle(bot, Vector3.RIGHT, Vector3.BACK, r, c)
	_circle(xf, Vector3.RIGHT, Vector3.BACK, r, c)
	for ax in [Vector3.RIGHT, Vector3.BACK]:
		_circle(top, ax, Vector3.UP, r, c, 0.0, PI)
		_circle(bot, ax, Vector3.DOWN, r, c, 0.0, PI)
		_line(top * (ax * r), bot * (ax * r), c)
		_line(top * (-ax * r), bot * (-ax * r), c)


func _sphere(xf: Transform3D, r: float, c: Color) -> void:
	_circle(xf, Vector3.RIGHT, Vector3.BACK, r, c)
	_circle(xf, Vector3.RIGHT, Vector3.UP, r, c)
	_circle(xf, Vector3.BACK, Vector3.UP, r, c)
