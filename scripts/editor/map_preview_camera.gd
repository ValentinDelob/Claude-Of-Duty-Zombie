class_name MapPreviewCamera
extends Node3D
## Caméras de l'aperçu 3D de l'éditeur de cartes (MapPreviewWorld) :
##   ORBIT : autour d'un point (clic droit glisser : tourner, molette : zoom,
##           clic milieu : déplacer le point) ;
##   FLY   : vol libre (touches de déplacement du jeu, Maj : plus vite, clic
##           droit maintenu : regarder, Espace / accroupi : monter / descendre) ;
##   WALK  : vue joueur à hauteur d'yeux (Player.EYE_HEIGHT), qui marche avec
##           les collisions du jeu (capsule, gravité et vitesses du joueur) ;
##           les portes fermées se traversent (visite de la carte).
## Les entrées (souris, touches) sont données par le panneau
## (MapPreviewPanel) ; les tests peuvent imposer `move` et `sprint`.

enum Mode { ORBIT, FLY, WALK }

const LOOK_SENS := 0.005
const PAN_SENS := 0.0022
const FLY_SPEED := 9.0
const FLY_FAST := 3.0
const MIN_DIST := 1.5
const MAX_DIST := 250.0
const PITCH_LIMIT := 1.55

var mode := Mode.ORBIT
var cam: Camera3D
var walker: CharacterBody3D
## Point visé en orbite (monde).
var pivot := Vector3(14, 0, 14)
var yaw := 0.7
var pitch := -0.75
var dist := 24.0
## Position de la caméra en vol libre.
var fly_pos := Vector3(14, 8, 30)
## Déplacement demandé (x : droite, y : avant), vitesse rapide, montée (+1) / descente (-1).
var move := Vector2.ZERO
var sprint := false
var rise := 0.0
var jump := false
## Corps des portes, traversés en vue joueur.
var door_bodies: Array = []:
	set(v):
		door_bodies = v
		_apply_exceptions()
## La pose a changé depuis le dernier appel à take_moved() (repère 2D, rendu).
var _moved := true


func _ready() -> void:
	cam = Camera3D.new()
	cam.name = "Camera3D"
	cam.near = 0.05
	cam.far = 500.0
	cam.fov = Settings.fov
	cam.current = true
	add_child(cam)
	walker = CharacterBody3D.new()
	walker.name = "Walker"
	walker.collision_layer = 0
	walker.collision_mask = 1 | Barricade.BARRIER_LAYER
	walker.floor_max_angle = deg_to_rad(50.0)
	var cs := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = Player.RADIUS
	capsule.height = Player.STAND_HEIGHT
	cs.shape = capsule
	cs.position.y = Player.STAND_HEIGHT * 0.5
	walker.add_child(cs)
	walker.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(walker)
	_apply()


var _exceptions: Array[RID] = []


func _apply_exceptions() -> void:
	if walker == null:
		return
	# Exceptions des portes précédentes (reconstruites) retirées.
	for rid in _exceptions:
		PhysicsServer3D.body_remove_collision_exception(walker.get_rid(), rid)
	_exceptions.clear()
	for b in door_bodies:
		if is_instance_valid(b) and b is PhysicsBody3D:
			walker.add_collision_exception_with(b)
			_exceptions.append((b as PhysicsBody3D).get_rid())


func basis_now() -> Basis:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0))


func forward() -> Vector3:
	return -cam.global_transform.basis.z if cam != null else Vector3.FORWARD


## Position de l'œil (monde).
func eye() -> Vector3:
	return cam.global_position if cam != null else fly_pos


func take_moved() -> bool:
	var m := _moved
	_moved = false
	return m


func set_mode(m: Mode, ground: Callable = Callable()) -> void:
	end_glide()
	if m == mode:
		return
	var from := eye()
	var fwd := forward()
	match m:
		Mode.ORBIT:
			# Le point visé : devant la caméra, à la distance d'orbite.
			dist = clampf(dist, 4.0, 40.0)
			pivot = from + fwd * dist
			if mode == Mode.WALK:
				pivot = from + fwd * 6.0
				dist = 6.0
		Mode.FLY:
			fly_pos = from
		Mode.WALK:
			# Posé au sol sous la caméra, sinon sous le point visé.
			var at := from
			if ground.is_valid():
				var g: Variant = ground.call(from)
				if g == null and mode == Mode.ORBIT:
					g = ground.call(pivot + Vector3.UP * 1.0)
				if g != null:
					at = g
			walker.global_position = at + Vector3.UP * 0.05
			walker.velocity = Vector3.ZERO
			pitch = clampf(pitch, -0.6, 0.6)
	mode = m
	walker.process_mode = Node.PROCESS_MODE_INHERIT if mode == Mode.WALK else Node.PROCESS_MODE_DISABLED
	_apply()


## Clic droit glissé : tourner (orbite) ou regarder (vol, joueur).
func look(rel: Vector2) -> void:
	end_glide()
	yaw -= rel.x * LOOK_SENS
	pitch = clampf(pitch - rel.y * LOOK_SENS, -PITCH_LIMIT, PITCH_LIMIT if mode != Mode.ORBIT else 0.2)
	_apply()


## Clic milieu glissé : déplacer le point visé (ou la caméra) dans le plan de la vue.
func pan(rel: Vector2) -> void:
	end_glide()
	var b := basis_now()
	var k := PAN_SENS * (dist if mode == Mode.ORBIT else 8.0)
	var d := (-b.x * rel.x + b.y * rel.y) * k
	if mode == Mode.ORBIT:
		pivot += d
	elif mode == Mode.FLY:
		fly_pos += d
	_apply()


## Molette : rapprocher / éloigner (orbite), avancer / reculer (vol).
func zoom(steps: float) -> void:
	end_glide()
	if mode == Mode.ORBIT:
		dist = clampf(dist * pow(0.87, steps), MIN_DIST, MAX_DIST)
	elif mode == Mode.FLY:
		fly_pos += forward() * steps * 1.5
	_apply()


## Cadre un point (monde) et un rayon : orbite autour, vol libre en face
## (la vue joueur passe en orbite). `animate` : glissement (maison du ViewCube).
func focus(center: Vector3, radius: float, animate := false) -> void:
	end_glide()
	var d := clampf(radius * 2.4, 4.0, MAX_DIST)
	if mode == Mode.WALK:
		set_mode(Mode.ORBIT)
	var from := _pose()
	pivot = center
	dist = d
	if mode == Mode.FLY:
		fly_pos = center + basis_now().z * d
	if animate:
		_glide(from)
	_apply()


## Vise un point (suivre la vue 2D) : l'orbite y déplace son point, le vol
## libre se décale d'autant. Sans effet en vue joueur.
func follow(target: Vector3, delta: float) -> void:
	if gliding():
		return
	var k := clampf(delta * 10.0, 0.0, 1.0)
	match mode:
		Mode.ORBIT:
			var np := pivot.lerp(target, k)
			if np.distance_to(pivot) > 0.0005:
				pivot = np
				_apply()
		Mode.FLY:
			var cur := fly_pos + forward() * dist
			var d := (target - cur) * k
			if d.length() > 0.0005:
				fly_pos += d
				_apply()


## ViewCube (docs/EDITOR_VIEWS.md § 4) : la caméra regarde depuis la
## direction `dir` (monde, du point visé vers la caméra), SANS changer de mode :
##   ORBIT : orbite sur cette direction autour de `target`, même distance ;
##   FLY   : la caméra libre se place sur cette direction, à la distance
##           d'orbite (au moins 4 m) du point visé, et le regarde ;
##   WALK  : le joueur reste où il est et tourne le regard (pas de
##           téléportation ; `target` ignoré).
## `target` null : le point visé actuel (orbite : son point ; vol libre : le
## point à `dist` devant la caméra). `animate` : glissement de GLIDE s.
func look_from(dir: Vector3, target: Variant = null, animate := false) -> void:
	if dir.length() < 0.001:
		return
	end_glide()
	var d := dir.normalized()
	var from := _pose()
	# Cap : vers -d à l'horizontale ; vue de dessus ou de dessous : le nord en haut.
	yaw = atan2(d.x, d.z) if Vector2(d.x, d.z).length() > 0.001 else 0.0
	var p := -asin(clampf(d.y, -1.0, 1.0))
	match mode:
		Mode.ORBIT:
			if target is Vector3:
				pivot = target
			pitch = clampf(p, -PITCH_LIMIT, 0.2)
		Mode.FLY:
			var r := clampf(dist, 4.0, MAX_DIST)
			var t: Vector3 = target if target is Vector3 else eye() + forward() * r
			dist = r
			pivot = t
			pitch = clampf(p, -PITCH_LIMIT, PITCH_LIMIT)
			fly_pos = t + basis_now().z * r
		Mode.WALK:
			pitch = clampf(p, -PITCH_LIMIT, PITCH_LIMIT)
	if animate:
		_glide(from)
	_apply()


# ------------------------------------------------------------------ transition

## Transition du ViewCube (s) : la caméra glisse de son ancienne pose vers la
## nouvelle (cap par le plus court chemin) ; toute entrée de l'utilisateur
## (regard, déplacement, molette, changement de mode) la termine net.
const GLIDE := 0.25

var _glide_t := -1.0
var _glide_from := {}
var _glide_to := {}


func _pose() -> Dictionary:
	return {"yaw": yaw, "pitch": pitch, "pivot": pivot, "fly_pos": fly_pos, "dist": dist}


func _set_pose(p: Dictionary) -> void:
	yaw = p.yaw
	pitch = p.pitch
	pivot = p.pivot
	fly_pos = p.fly_pos
	dist = p.dist


## Glissement de la pose `from` vers la pose actuelle (la pose de fin).
func _glide(from: Dictionary) -> void:
	_glide_to = _pose()
	_glide_from = from
	_glide_from.yaw = float(_glide_to.yaw) - wrapf(float(_glide_to.yaw) - float(from.yaw), -PI, PI)
	# Vol libre : point regardé au départ (la caméra tourne autour, sans
	# traverser la carte en ligne droite).
	_glide_from.aim = (from.fly_pos as Vector3) + Basis.from_euler(Vector3(from.pitch, from.yaw, 0.0)).z * -float(_glide_to.dist)
	_glide_t = 0.0
	_set_pose(_glide_from)


func gliding() -> bool:
	return _glide_t >= 0.0


## Termine la transition en cours : la caméra est à sa pose de fin.
func end_glide() -> void:
	if _glide_t < 0.0:
		return
	_glide_t = -1.0
	_set_pose(_glide_to)
	_apply()


func _step_glide(delta: float) -> void:
	_glide_t += delta
	var k := clampf(_glide_t / GLIDE, 0.0, 1.0)
	if k >= 1.0:
		end_glide()
		return
	k = k * k * (3.0 - 2.0 * k)
	var a := _glide_from
	var b := _glide_to
	yaw = lerpf(a.yaw, b.yaw, k)
	pitch = lerpf(a.pitch, b.pitch, k)
	dist = lerpf(a.dist, b.dist, k)
	match mode:
		Mode.ORBIT:
			pivot = (a.pivot as Vector3).lerp(b.pivot, k)
		Mode.FLY:
			fly_pos = (a.aim as Vector3).lerp(b.pivot, k) + basis_now().z * float(b.dist)
	_apply()


## Double-clic sur la carte 2D : la caméra va à ce point (au sol de l'étage).
func place_at(p: Vector3) -> void:
	end_glide()
	match mode:
		Mode.ORBIT:
			pivot = p
		Mode.FLY:
			fly_pos = p + Vector3.UP * Player.EYE_HEIGHT
		Mode.WALK:
			walker.global_position = p + Vector3.UP * 0.05
			walker.velocity = Vector3.ZERO
	_apply()


func _process(delta: float) -> void:
	if gliding():
		# Une touche de déplacement termine la transition (pose de fin).
		if move != Vector2.ZERO or rise != 0.0:
			end_glide()
		else:
			_step_glide(delta)
	if mode == Mode.FLY and (move != Vector2.ZERO or rise != 0.0):
		var b := basis_now()
		var v := (b.x * move.x - b.z * move.y + Vector3.UP * rise)
		if v.length() > 1.0:
			v = v.normalized()
		fly_pos += v * FLY_SPEED * (FLY_FAST if sprint else 1.0) * delta
		_apply()


func _physics_process(delta: float) -> void:
	if mode != Mode.WALK:
		return
	# Même capsule, gravité, vitesses et saut que le joueur (Player._move).
	if not walker.is_on_floor():
		walker.velocity.y -= Player.GRAVITY * delta
	elif jump:
		walker.velocity.y = Player.JUMP_VELOCITY
	var b := Basis(Vector3.UP, yaw)
	var wish := b * Vector3(move.x, 0.0, -move.y)
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	var target := wish * (Player.SPRINT_SPEED if sprint else Player.WALK_SPEED)
	walker.velocity.x = target.x
	walker.velocity.z = target.z
	walker.move_and_slide()
	# Tombé hors de la carte : retour en orbite.
	if walker.global_position.y < -30.0:
		set_mode(Mode.ORBIT)
		return
	_apply()


## Place la caméra selon le mode.
func _apply() -> void:
	if cam == null:
		return
	var b := basis_now()
	var xf := Transform3D.IDENTITY
	match mode:
		Mode.ORBIT:
			xf = Transform3D(b, pivot + b.z * dist)
		Mode.FLY:
			xf = Transform3D(b, fly_pos)
		Mode.WALK:
			xf = Transform3D(b, walker.global_position + Vector3.UP * Player.EYE_HEIGHT)
	if not xf.is_equal_approx(cam.global_transform):
		cam.global_transform = xf
		_moved = true
