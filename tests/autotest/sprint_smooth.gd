extends AutotestScenario
## Course fluide : 8 s de sprint maintenu en ligne droite puis en virage.
## À chaque image physique : état de sprint, endurance, vitesse, position et
## orientation de la caméra, FOV, position de l'arme (viewmodel). Vérifie
## l'absence d'oscillation : le sprint ne bascule pas plus d'une fois par
## seconde (fin d'endurance : une seule bascule vers la marche, plus de
## sprint/marche à chaque image), la caméra ne monte et ne descend pas plus
## vite que le rythme des pas, FOV et arme restent continus.
## Journal image par image : tests/_out/sprint_smooth_<phase>.csv.

var H := AutotestHelpers
var p: Player
var _rows: Array = []
var _t := 0.0
var _turn := false


func run() -> void:
	timeout_sec = 60
	p = await H.start_solo_game(self)
	if p == null:
		return
	Game.instance.rounds.paused = true
	await H.clear_zombies(self)
	p.untargetable = true
	await phase("droite", false)
	await phase("virage", true)


## Une course de 8 s, sprint maintenu (aussi lancée par mp_sprint_client :
## joueur invité). `p` : joueur local piloté par le script.
func phase(label: String, turn: bool) -> void:
	p.input.move = Vector2.ZERO
	p.input.sprint = false
	p.teleport_to(Vector3(3.0, 0.05, 3.4), -PI * 0.5)
	p.pitch = 0.0
	p.stamina = Player.SPRINT_DURATION + p.sprint_duration_bonus
	await seconds(0.5)  # posé, endurance pleine
	_rows.clear()
	_t = 0.0
	_turn = turn
	p.input.move = Vector2(0, 1)
	p.input.sprint = true
	tree().physics_frame.connect(_record)
	await seconds(8.0)
	tree().physics_frame.disconnect(_record)
	p.input.move = Vector2.ZERO
	p.input.sprint = false
	_dump(label)
	_analyse(label)


## Image physique : pilote le bot (virage, bande de course bouclée) et note l'état.
func _record() -> void:
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	_t += dt
	if _turn:
		# Virage continu (un tour en ~7 s), comme un joueur qui contourne un pilier.
		p.yaw -= 0.9 * dt
		p.rotation.y = p.yaw
	# Bande de course dégagée de l'arène (rangée 3) : on ramène le joueur en
	# arrière sans toucher à sa vitesse (seule la position du monde change ;
	# caméra, arme et balancement sont locaux).
	var gp := p.global_position
	if gp.x > 22.0: gp.x -= 18.0
	elif gp.x < 3.0: gp.x += 18.0
	if gp.z > 3.7: gp.z -= 0.6
	elif gp.z < 3.1: gp.z += 0.6
	if gp != p.global_position:
		p.global_position = gp
	var vm: Node3D = p.weapons.view.model if p.weapons and p.weapons.view else null
	_rows.append({
		"t": _t,
		"sprint": p.sprinting,
		"stamina": p.stamina,
		"speed": Vector2(p.velocity.x, p.velocity.z).length(),
		"floor": p.is_on_floor(),
		"head": p.head.position,
		"cam_rot": p.camera.rotation,
		"fov": p.camera.fov,
		"vm_pos": vm.position if vm else Vector3.ZERO,
		"vm_rot": vm.rotation if vm else Vector3.ZERO,
	})


func _dump(label: String) -> void:
	var f := FileAccess.open("res://tests/_out/sprint_smooth_%s.csv" % label, FileAccess.WRITE)
	if f == null:
		return
	f.store_line("t;sprint;stamina;speed;floor;head_x;head_y;fov;vm_x;vm_y;vm_z;vm_rx;vm_ry;vm_rz")
	for r in _rows:
		f.store_line("%.4f;%d;%.4f;%.4f;%d;%.5f;%.5f;%.4f;%.5f;%.5f;%.5f;%.5f;%.5f;%.5f" % [
			r.t, int(r.sprint), r.stamina, r.speed, int(r.floor), r.head.x, r.head.y, r.fov,
			r.vm_pos.x, r.vm_pos.y, r.vm_pos.z, r.vm_rot.x, r.vm_rot.y, r.vm_rot.z])


## Nombre maximal d'événements dans une fenêtre glissante de `win` secondes.
static func _max_in_window(times: Array, win: float) -> int:
	var best := 0
	var a := 0
	for b in times.size():
		while times[b] - times[a] > win:
			a += 1
		best = maxi(best, b - a + 1)
	return best


## Instants où la dérivée de la série change de signe (variations < eps ignorées).
static func _sign_flips(rows: Array, key: Callable, eps: float) -> Array:
	var out := []
	var last_sign := 0
	for i in range(1, rows.size()):
		var d: float = key.call(rows[i]) - key.call(rows[i - 1])
		if absf(d) < eps:
			continue
		var s := 1 if d > 0.0 else -1
		if last_sign != 0 and s != last_sign:
			out.append(rows[i].t)
		last_sign = s
	return out


## Plus grand déplacement d'une image à l'autre entre `t0` et `t1` (s).
static func _max_step(rows: Array, key: Callable, t0 := 0.0, t1 := INF) -> float:
	var m := 0.0
	for i in range(1, rows.size()):
		if rows[i].t < t0 or rows[i].t > t1:
			continue
		var a = key.call(rows[i - 1])
		var b = key.call(rows[i])
		m = maxf(m, (b - a).length() if b is Vector3 else absf(b - a))
	return m


func _analyse(label: String) -> void:
	if _rows.size() < 300:
		at.fail("%s : trop peu d'images enregistrées (%d)" % [label, _rows.size()])
		return
	# Sprint : bascules.
	var toggles := []
	var first_stop := -1.0
	for i in range(1, _rows.size()):
		if _rows[i].sprint != _rows[i - 1].sprint:
			toggles.append(_rows[i].t)
			if first_stop < 0.0 and not _rows[i].sprint:
				first_stop = _rows[i].t
	var floor_lost := 0
	for r in _rows:
		if not r.floor:
			floor_lost += 1
	var head_flips := _sign_flips(_rows, func(r): return r.head.y, 1e-5)
	var vm_flips := _sign_flips(_rows, func(r): return r.vm_pos.y, 1e-5)
	var fov_flips := _sign_flips(_rows, func(r): return r.fov, 1e-4)
	# Pas de référence : sprint établi (balancement à pleine amplitude).
	var head_ref := _max_step(_rows, func(r): return r.head, 1.0, 3.5)
	var head_step := _max_step(_rows, func(r): return r.head)
	var vm_step := _max_step(_rows, func(r): return r.vm_pos)
	var fov_step := _max_step(_rows, func(r): return r.fov)
	print("[sprint_smooth] %s : %d images, %d bascules de sprint (1re fin à %.2f s), sol perdu %d images" % [
		label, _rows.size(), toggles.size(), first_stop, floor_lost])
	print("[sprint_smooth] %s : inversions/s max : caméra %d, arme %d, FOV %d" % [
		label, _max_in_window(head_flips, 1.0), _max_in_window(vm_flips, 1.0), _max_in_window(fov_flips, 1.0)])
	print("[sprint_smooth] %s : pas max par image : tête %.4f m (sprint établi %.4f), arme %.4f m, FOV %.3f°" % [
		label, head_step, head_ref, vm_step, fov_step])
	# Secondes : aperçu de ce qui se passe autour de la fin du sprint.
	for w in 8:
		var n_sp := 0
		var n := 0
		for r in _rows:
			if r.t >= w and r.t < w + 1:
				n += 1
				n_sp += int(r.sprint)
		print("[sprint_smooth]   %s %d-%d s : sprint %d/%d images, inversions caméra %d, arme %d" % [label, w, w + 1, n_sp, n,
			head_flips.filter(func(t): return t >= w and t < w + 1).size(),
			vm_flips.filter(func(t): return t >= w and t < w + 1).size()])

	at.check(_max_in_window(toggles, 1.0) <= 1, "%s : le sprint bascule au plus une fois par seconde (%d bascules en 8 s)" % [label, toggles.size()])
	at.check(first_stop > 3.0, "%s : sprint tenu jusqu'à la fin de l'endurance (%.2f s)" % [label, first_stop])
	at.check(not _rows[_rows.size() - 1].sprint, "%s : endurance épuisée, retour à la marche (touche toujours maintenue)" % label)
	# Rythme des pas : ~4 pas/s en sprint, soit ~8 inversions/s de la vitesse
	# verticale de la caméra (et de l'arme) ; une alternance sprint/marche à
	# chaque image en donnait 40+.
	at.check(_max_in_window(head_flips, 1.0) <= 10, "%s : caméra sans tremblement vertical (max %d inversions/s)" % [label, _max_in_window(head_flips, 1.0)])
	at.check(_max_in_window(vm_flips, 1.0) <= 10, "%s : arme sans tremblement vertical (max %d inversions/s)" % [label, _max_in_window(vm_flips, 1.0)])
	at.check(_max_in_window(fov_flips, 1.0) <= 2, "%s : FOV sans va-et-vient (max %d inversions/s)" % [label, _max_in_window(fov_flips, 1.0)])
	# Continuité : aucun saut plus grand que le mouvement normal du sprint
	# (tête), que la bascule en pose de sprint (arme, ~0,03 m par image) ou que
	# l'élargissement du FOV en début de sprint (~1° par image).
	at.check(head_step <= head_ref * 1.25 + 0.001, "%s : caméra continue (pas max %.4f m, sprint établi %.4f m)" % [label, head_step, head_ref])
	at.check(vm_step < 0.04, "%s : arme continue (pas max %.4f m)" % [label, vm_step])
	at.check(fov_step < 1.2, "%s : FOV continu (pas max %.3f°)" % [label, fov_step])
