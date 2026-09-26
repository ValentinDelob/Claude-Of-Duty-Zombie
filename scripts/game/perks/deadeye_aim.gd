class_name DeadeyeAim
extends RefCounted
## DEADEYE DRAM (Deadshot Daiquiri de BO1), joueur LOCAL : au passage en
## visée, la vue glisse en DEADEYE_SNAP_TIME vers la tête du zombie le plus
## proche du centre de l'écran (cône, portée, ligne de vue dégagée). Purement
## côté client : le serveur valide les touches comme pour tout tir.

var _was_aiming := false
var _target: Zombie
var _snap_left := 0.0
## Dernière tête visée (tests, statistiques).
var last_target_id := -1


## Appelé par WeaponController.tick à chaque image physique.
func tick(wc: WeaponController, delta: float) -> void:
	var p := wc.player
	var rising := p.aiming and not _was_aiming
	_was_aiming = p.aiming
	if rising and PerkDB.aim_assist(wc.session.get_data(p.peer_id)):
		_target = _pick(p)
		_snap_left = PerkDB.DEADEYE_SNAP_TIME if _target else 0.0
		if _target:
			last_target_id = _target.id
	if _snap_left <= 0.0:
		return
	if not p.aiming or not is_instance_valid(_target) or not _target.is_alive():
		_snap_left = 0.0
		_target = null
		return
	# Glissement amorti vers la tête (qui bouge), exact à la fin.
	var want := PerkDB.look_angles(p.eye_position(), _target.head_position())
	var k := clampf(delta / _snap_left, 0.0, 1.0)
	_snap_left -= delta
	if _snap_left <= 0.0:
		k = 1.0
		_target = null
	p.yaw = lerp_angle(p.yaw, want.x, k)
	p.pitch = clampf(lerpf(p.pitch, want.y, k), -Player.PITCH_LIMIT, Player.PITCH_LIMIT)
	p.rotation.y = p.yaw
	p.head.rotation.x = p.pitch


func _pick(p: Player) -> Zombie:
	if Game.instance == null or Game.instance.zombies == null:
		return null
	var eye := p.eye_position()
	var cands: Array[Zombie] = []
	var heads := []
	var space := p.get_world_3d().direct_space_state
	for z: Zombie in Game.instance.zombies.alive:
		if not is_instance_valid(z) or not z.is_alive():
			continue
		var h := z.head_position()
		if eye.distance_to(h) > PerkDB.DEADEYE_RANGE:
			continue
		# Pas d'aimantation à travers un mur ou une barricade.
		var q := PhysicsRayQueryParameters3D.create(eye, h, 1 | Barricade.BARRIER_LAYER, [p.get_rid()])
		if not space.intersect_ray(q).is_empty():
			continue
		cands.append(z)
		heads.append(h)
	var i := PerkDB.deadeye_pick(eye, p.aim_direction(), heads)
	return cands[i] if i >= 0 else null
