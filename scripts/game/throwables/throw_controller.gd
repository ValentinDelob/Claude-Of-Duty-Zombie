class_name ThrowController
extends Node
## Lancer du joueur LOCAL (prédiction client), piloté par WeaponController.
##
## [G] maintenu : dégoupillage puis « cuisson » (la mèche de 4 s court dès le
## dégoupillage) ; relâché : lancer en cloche. [Q] : SINGE-TAMBOUR. L'arme est
## baissée pendant tout le geste. Le serveur (ThrowableSystem) fait foi sur la
## réserve, la trajectoire et l'explosion.

enum Phase { IDLE, PULL, HOLD, THROW }

## Dégoupillage (ou remontage du singe) : minimum avant de pouvoir lancer.
const PULL_TIME := 0.4
## Geste du lancer puis retour de l'arme.
const THROW_TIME := 0.32
const RECOVER_TIME := 0.3
## Tremblement de la main pendant la dernière seconde et demie de la mèche.
const DANGER_TIME := 1.5

var wc: WeaponController
var player: Player
var system: ThrowableSystem
var view: ThrowView
var phase: Phase = Phase.IDLE
var kind := 0
var _t0 := 0.0
var _cook_start := 0.0
var _release := false
var _prev_frag := false
var _prev_tac := false
## Lancers partis (tests).
var thrown := 0


func setup(controller: WeaponController, game: Game) -> void:
	wc = controller
	player = controller.player
	system = game.throwables
	view = ThrowView.new()
	view.name = "ThrowView"
	player.camera.add_child(view)


static func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func busy() -> bool:
	return phase != Phase.IDLE


## Appelé à chaque image physique par WeaponController.tick.
func tick(delta: float) -> void:
	var inp := player.input
	var t := now()
	var frag_edge := inp.grenade and not _prev_frag
	var tac_edge := inp.tactical and not _prev_tac
	_prev_frag = inp.grenade
	_prev_tac = inp.tactical
	var pd := wc.session.get_data(player.peer_id)
	var alive := pd != null and pd.life == PlayerData.Life.ALIVE
	var k := 0.0
	match phase:
		Phase.IDLE:
			# Pas pendant une boisson, un coup / une fente de couteau ou la
			# récupération du couteau de chasse.
			if alive and system and not wc.view.is_drinking() and not wc.is_knifing() and not player.is_lunging():
				if frag_edge and pd.grenades > 0:
					_begin(ThrowableRules.Kind.FRAG)
				elif tac_edge and pd.has_monkeys and pd.monkeys > 0:
					_begin(ThrowableRules.Kind.MONKEY)
		Phase.PULL, Phase.HOLD:
			var held := inp.grenade if kind == ThrowableRules.Kind.FRAG else inp.tactical
			if not held:
				_release = true
			if phase == Phase.PULL:
				k = (t - _t0) / PULL_TIME
				if k >= 1.0:
					phase = Phase.HOLD
			if kind == ThrowableRules.Kind.FRAG and ThrowableRules.fuse_left(_cook_start, t) <= 0.0:
				# Gardée trop longtemps : le serveur la fait exploser dans la main.
				view.drop()
				phase = Phase.THROW
				_t0 = t
			elif not alive:
				view.drop()
				phase = Phase.THROW
				_t0 = t
			elif phase == Phase.HOLD and _release:
				_throw()
		Phase.THROW:
			k = (t - _t0) / THROW_TIME
			if t - _t0 >= THROW_TIME + RECOVER_TIME:
				phase = Phase.IDLE
	var danger := 0.0
	if phase == Phase.HOLD and kind == ThrowableRules.Kind.FRAG:
		danger = clampf(1.0 - ThrowableRules.fuse_left(_cook_start, t) / DANGER_TIME, 0.0, 1.0)
	view.pose(delta, phase, clampf(k, 0.0, 1.0), danger)
	# L'arme reste baissée jusqu'à la fin du geste.
	wc.view.lowered = 1.0 if phase != Phase.IDLE and not (phase == Phase.THROW and k > 0.8) else 0.0


func _begin(k: int) -> void:
	kind = k
	phase = Phase.PULL
	_t0 = now()
	_cook_start = _t0
	_release = false
	wc.cancel_reload_local()
	view.begin(k)
	Audio.play_2d("grenade_pin" if k == ThrowableRules.Kind.FRAG else "monkey_wind", -3.0, 0.05)
	system.srv_cook.rpc_id(1, k)


func _throw() -> void:
	phase = Phase.THROW
	_t0 = now()
	thrown += 1
	var fwd := player.aim_direction()
	var right := player.camera.global_transform.basis.x
	var eye := player.camera.global_position
	var origin := eye + fwd * 0.45 + right * 0.12 + Vector3.DOWN * 0.06
	# Jamais lancé depuis l'intérieur d'un mur tout proche.
	var q := PhysicsRayQueryParameters3D.create(eye, origin + fwd * ThrowableRules.RADIUS, 1)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		origin = (hit.position as Vector3) - fwd * (ThrowableRules.RADIUS + 0.05)
	Audio.play_2d("grenade_throw", -4.0, 0.08)
	system.throw_local(kind, origin, fwd, _cook_start)
