class_name ThrowView
extends Node3D
## Main qui lance, vue à la première personne (joueur local) : la main droite
## monte avec la grenade (ou le singe), la main gauche arrache la goupille, le
## bras armé en arrière tremble quand la mèche arrive à sa fin, puis le lancer
## part en avant. Fils de la caméra, comme ViewModel.

const HIDDEN := Vector3(0.3, -0.65, -0.38)
const READY := Vector3(0.2, -0.2, -0.5)
const COCKED := Vector3(0.25, -0.14, -0.42)
const RELEASE := Vector3(0.08, -0.08, -0.72)

var _hand: Node3D
var _objects: Dictionary = {}  # kind -> Node3D
var _left: Node3D
var _pin: Node3D
var _kind := 0
var _pos := HIDDEN
var _rot := Vector3.ZERO
## Tenue des mains construites (ViewHands.STYLES).
var _style := 0


func _ready() -> void:
	_hand = Node3D.new()
	add_child(_hand)
	# Avant-bras vers le bas-droite de l'écran, main refermée sur l'objet.
	_hand.add_child(ViewHands.throw_hand(maxi(ViewModel.style, 0), false))
	for k in [ThrowableRules.Kind.FRAG, ThrowableRules.Kind.MONKEY]:
		var o := Throwable.build_model(k, true)
		o.position = Vector3(0.0, 0.0, 0.0) if k == ThrowableRules.Kind.FRAG else Vector3(0.0, -0.06, 0.0)
		o.scale = Vector3.ONE * (1.0 if k == ThrowableRules.Kind.FRAG else 0.7)
		if k == ThrowableRules.Kind.MONKEY:
			o.rotation.y = PI * 0.75  # vu de trois quarts dos
		o.visible = false
		_hand.add_child(o)
		_objects[k] = o
	# Main gauche (arrache la goupille / remonte la clé du singe).
	_left = Node3D.new()
	add_child(_left)
	_left.add_child(ViewHands.throw_hand(maxi(ViewModel.style, 0), true))
	_left.visible = false
	visible = false


func _limb(parent: Node3D, a: Vector3, b: Vector3, thickness: float, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(thickness, thickness, a.distance_to(b))
	mi.mesh = box
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.position = (a + b) * 0.5
	mi.basis = Basis.looking_at(b - a, Vector3.UP)


## Nouveau lancer : objet dans la main, goupille en place.
func begin(kind: int) -> void:
	# Mains à la tenue du joueur (connue après la première image).
	var st := maxi(ViewModel.style, 0)
	if st != _style:
		_style = st
		for pair in [[_hand, false], [_left, true]]:
			var old: Node = pair[0].get_node_or_null("ThrowHand")
			if old:
				old.free()
			pair[0].add_child(ViewHands.throw_hand(st, pair[1]))
	_kind = kind
	for k in _objects:
		_objects[k].visible = k == kind
	_pin = _objects[kind].get_node_or_null("Pin")
	if _pin:
		_pin.visible = true
		_pin.position = Vector3(0.018, 0.05, 0)
	_pos = HIDDEN
	visible = true


## Pose de la main. `phase` : ThrowController.Phase ; `k` : avancement de la
## phase (0..1) ; `danger` : fin de mèche proche (0..1, tremblement).
func pose(delta: float, phase: int, k: float, danger: float) -> void:
	if not visible:
		return
	var target := HIDDEN
	var trot := Vector3.ZERO
	var left_k := 0.0
	match phase:
		ThrowController.Phase.PULL:
			target = HIDDEN.lerp(READY, ease(minf(k * 1.6, 1.0), 0.4))
			trot = Vector3(0.3, 0.2, 0.0)
			# La main gauche vient arracher la goupille (ou tourner la clé).
			left_k = sin(clampf((k - 0.35) / 0.65, 0.0, 1.0) * PI)
			if _pin and k > 0.6:
				_pin.position = Vector3(0.018, 0.05, 0).lerp(Vector3(-0.2, 0.02, 0.05), (k - 0.6) / 0.4)
				_pin.visible = k < 0.97
		ThrowController.Phase.HOLD:
			target = READY.lerp(COCKED, 0.7)
			trot = Vector3(0.5, 0.25, -0.2)
			if _pin:
				_pin.visible = false
			if danger > 0.0:
				target += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0.0) * 0.006 * danger
		ThrowController.Phase.THROW:
			# Bras armé -> projection vers l'avant -> la main redescend.
			if k < 0.45:
				target = COCKED.lerp(RELEASE, ease(k / 0.45, 0.5))
				trot = Vector3(0.5, 0.25, -0.2).lerp(Vector3(-0.35, -0.1, 0.2), k / 0.45)
			else:
				target = RELEASE.lerp(HIDDEN, ease((k - 0.45) / 0.55, 2.0))
				trot = Vector3(-0.35, -0.1, 0.2)
			_objects[_kind].visible = k < 0.4
		_:
			target = HIDDEN
	var f := 1.0 - exp(-delta * 22.0)
	_pos = _pos.lerp(target, f)
	_rot = _rot.lerp(trot, f)
	_hand.position = _pos
	_hand.rotation = _rot
	_left.visible = left_k > 0.02
	_left.position = Vector3(-0.2, -0.5, -0.3).lerp(Vector3(0.1, -0.15, -0.38), left_k)
	# Champ de vision propre à l'arme (ViewModel) : profondeur compensée pour
	# garder la même image.
	scale = Vector3(1.0, 1.0, ViewModel.fov_k)
	if phase == ThrowController.Phase.IDLE and _pos.distance_to(HIDDEN) < 0.02:
		visible = false


## Grenade explosée dans la main : plus rien à tenir.
func drop() -> void:
	for k in _objects:
		_objects[k].visible = false
