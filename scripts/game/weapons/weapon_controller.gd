class_name WeaponController
extends Node
## Gestion des armes du joueur LOCAL (prédiction client).
##
## Le client joue immédiatement tir, recul, effets et décompte de munitions
## pour un ressenti sans latence, puis envoie ses intentions au serveur
## (Combat.srv_*). Le serveur fait foi : chaque resynchronisation d'inventaire
## écrase la prédiction locale.

const SWITCH_TIME := 0.55
## Changement d'arme demandé au serveur : arme bloquée (ni tir ni
## rechargement) jusqu'à l'inventaire qui l'applique, au plus ce délai (s)
## si le serveur refuse.
const SWITCH_REQUEST_TIMEOUT := 0.5
const RAY_LENGTH := 150.0
const HITBOX_LAYER := 1 << 3

signal fired
signal ammo_changed

var player: Player
## Partie reçue de setup() (null avant : contrôleur seul des tests unitaires).
var game: Game
var combat: Combat
var session: Session
var fx: Fx
var view: ViewModel

## Copie locale (prédite) de l'inventaire.
var weapons: Array = []
var slot := 0
var _next_fire := 0.0
var _reload_end := -1.0
## Début et durée du rechargement en cours (cartouches déjà poussées).
var _reload_start := -1.0
var _reload_dur := 0.0
## Numéro du rechargement : ses sons différés ne jouent que s'il est encore
## en cours (jamais sur l'arme sortie après une annulation).
var _reload_serial := 0
var _switch_end := -1.0
var _switch_req_end := -1.0
var _melee_ready := 0.0
var _trigger_released := true
var _drink_end := -1.0
## Couteau de mêlée tenu (KnifeDB) et fin de l'animation de récupération.
var knife_id := ""
var _pickup_end := -1.0
## Vrai entre le début d'une fente et le coup de couteau qui la termine.
var lunging := false
## Coups restant à tirer dans la rafale en cours (M16, G11...).
var _burst_left := 0
## Grenades et SINGE-TAMBOUR (dégoupillage, cuisson, lancer).
var throws: ThrowController
## DEADEYE DRAM : aimantation de la visée vers la tête.
var deadeye := DeadeyeAim.new()
## Dispersion (degrés) du dernier tir (tests).
var last_spread_deg := 0.0
## Dispersion dynamique, recul progressif, balancement de la lunette.
var feel := ShotFeel.new()
## Visée dans la lunette (écran de lunette affiché, modèle masqué).
var scoped := false
## Points d'arrivée des balles du dernier tir (tests) :
## [position, normale, id du zombie touché ou -1].
var last_impacts: Array = []
## Rayon des balles (_trace), réutilisé d'un segment et d'un tir à l'autre.
var _trace_q: PhysicsRayQueryParameters3D

## Sons de rechargement par mécanisme : [fraction de la durée, son].
const RELOAD_SOUNDS := {
	"mag": [[0.0, "mag_out"], [0.55, "mag_in"], [0.85, "slide"]],
	"belt": [[0.0, "mag_out"], [0.3, "break_open"], [0.6, "mag_in"], [0.85, "bolt"]],
	"break": [[0.05, "break_open"], [0.4, "shell_in"], [0.55, "shell_in"], [0.85, "break_close"]],
	"bolt": [[0.08, "bolt"], [0.3, "mag_out"], [0.6, "mag_in"], [0.86, "bolt"]],
	"cylinder": [[0.05, "break_open"], [0.2, "shell"], [0.55, "shell_in"], [0.85, "break_close"]],
	"rocket": [[0.1, "mag_out"], [0.55, "mag_in"], [0.85, "break_close"]],
	# TONNERRE-7 : réservoirs vidés, nouveaux réservoirs, tambour qui se recharge en pression.
	"thunder": [[0.05, "break_open"], [0.25, "mag_out"], [0.5, "mag_in"], [0.62, "thunder_charge"], [0.9, "break_close"]],
}


func setup(p: Player, g: Game) -> void:
	player = p
	game = g
	combat = g.get_node("Combat")
	session = g.get_node("Session")
	fx = g.fx_root
	view = ViewModel.new()
	view.name = "ViewModel"
	p.camera.add_child(view)
	throws = ThrowController.new()
	throws.name = "Throws"
	add_child(throws)
	throws.setup(self, game)
	session.inventory_changed.connect(_on_inventory_changed)
	_on_inventory_changed(p.peer_id)


func _on_inventory_changed(pid: int) -> void:
	if pid != player.peer_id:
		return
	var pd := session.get_data(pid)
	if pd == null:
		return
	var old_id: String = current().get("id", "")
	var old_pap: bool = current().get("pap", false)
	weapons = pd.weapons.duplicate(true)
	slot = pd.slot
	if not pd.powerup_weapon.is_empty() and pd.life == PlayerData.Life.ALIVE:
		# Arme de bonus seule en main (pas de changement d'arme) ; `slot` reste
		# celui du serveur pour la validation des tirs.
		weapons = [pd.powerup_weapon.duplicate()]
	if pd.knife != knife_id:
		_on_knife_changed(pd.knife)
	var w := current()
	# Mains vides (arme déposée dans le Pack-a-Punch...).
	view.visible = not w.is_empty()
	if w.is_empty():
		ammo_changed.emit()
		return
	if w.id != old_id or w.pap != old_pap:
		if old_id == "":
			view.set_weapon(w.id, w.pap)
		else:
			_switch_end = GameClock.now() + SWITCH_TIME
			view.start_switch(SWITCH_TIME, func(): view.set_weapon(w.id, w.pap))
			Audio.play_2d("weapon_switch", -6.0)
		_switch_req_end = -1.0
		_stop_reload()
		feel.reset()
	ammo_changed.emit()


func current() -> Dictionary:
	if weapons.is_empty():
		return {}
	return weapons[clampi(slot, 0, weapons.size() - 1)]


func current_stats() -> Dictionary:
	var w := current()
	return WeaponDB.stats(w.id, w.pap) if not w.is_empty() else {}


func is_reloading() -> bool:
	return _reload_end > 0.0


## Avancement du rechargement en cours (0 au début, 1 à la fin ; 0 sans
## rechargement).
func reload_progress() -> float:
	if _reload_end <= 0.0 or _reload_dur <= 0.0:
		return 0.0
	return clampf((GameClock.now() - _reload_start) / _reload_dur, 0.0, 1.0)


## Fin de rechargement (prédite) : le chargeur se remplit à l'échéance.
## Rien après une annulation (_reload_end remis à -1) : jamais de remplissage
## différé sur l'arme sortie entre-temps.
func update_reload(t: float) -> void:
	if _reload_end <= 0.0 or t < _reload_end:
		return
	_reload_end = -1.0
	var w := current()
	if w.is_empty():
		return
	var take: int = mini(int(current_stats().mag) - int(w.mag), int(w.reserve))
	w.mag += take
	w.reserve -= take
	ammo_changed.emit()


## Rien n'empêche de changer d'arme : un rechargement en cours n'en empêche
## pas (il est annulé), un changement, une boisson, un coup de couteau, la
## récupération du couteau ou une grenade, si.
func can_switch(t: float) -> bool:
	return t >= _switch_end and t >= _switch_req_end and t >= _drink_end \
		and t >= _melee_ready - WeaponDB.MELEE_COOLDOWN * 0.3 and t >= _pickup_end \
		and not (throws != null and throws.busy())


## Changement d'arme (touche, molette, bouton de manette) : le rechargement en
## cours est annulé sur-le-champ (animation, sons, aucun remplissage), puis le
## serveur change l'emplacement (Combat.srv_switch) et l'inventaire reçu lance
## l'animation de changement.
func request_switch(to_slot: int) -> void:
	abort_reload()
	_switch_req_end = GameClock.now() + SWITCH_REQUEST_TIMEOUT
	if combat:
		combat.srv_switch.rpc_id(1, to_slot)


## Rechargement interrompu par le joueur (changement d'arme, couteau,
## grenade) : chargeur et réserve inchangés, sauf les cartouches déjà poussées
## une à une (fusil à pompe, comme BO1). Le serveur fait le même calcul
## (Combat.cancel_reload) et resynchronise l'inventaire.
func abort_reload() -> void:
	if _reload_end > 0.0:
		var w := current()
		if not w.is_empty():
			var n := shells_loaded(current_stats(), w, reload_progress())
			if n > 0:
				w.mag += n
				w.reserve -= n
				ammo_changed.emit()
	_stop_reload()


## Le serveur a annulé (achat de munitions, mise à terre, bonus...) ou refusé
## le rechargement de ce joueur, sans forcément changer d'arme
## (Combat._cl_reload_cancelled) : la prédiction s'arrête net, sans remplir
## le chargeur ; l'inventaire envoyé par le serveur fait foi.
func server_cancelled_reload() -> void:
	if _reload_end > 0.0:
		_stop_reload()
		ammo_changed.emit()


## Arrête net le rechargement (animation, sons à venir) sans toucher aux
## munitions.
func _stop_reload() -> void:
	_reload_end = -1.0
	_reload_serial += 1
	_burst_left = 0
	if view:
		view.cancel_reload()


## Rechargement coup par coup : les poussées de cartouche occupent
## [SHELL_START, SHELL_START + SHELL_SPAN] de la durée, découpées en
## shell_steps() poussées égales (au plus SHELL_MAX_STEPS : au-delà, chaque
## poussée compte pour plusieurs cartouches, sans déluge de sons).
const SHELL_START := 0.12
const SHELL_SPAN := 0.65
const SHELL_MAX_STEPS := 6


## Cartouches à pousser (manque du chargeur, borné par la réserve). Pure.
static func shells_needed(s: Dictionary, w: Dictionary) -> int:
	return maxi(mini(int(s.get("mag", 0)) - int(w.get("mag", 0)), int(w.get("reserve", 0))), 0)


## Nombre de poussées (sons « shell_in », gestes de l'animation) : une par
## cartouche, SHELL_MAX_STEPS au plus, 1 au moins. Pure.
static func shell_steps(s: Dictionary, w: Dictionary) -> int:
	return clampi(shells_needed(s, w), 1, SHELL_MAX_STEPS)


## Instant (fraction de la durée) de la poussée `j` sur `steps` : milieu de
## son geste dans l'animation (main au fond de la fenêtre de chargement).
static func shell_step_time(j: int, steps: int) -> float:
	return SHELL_START + SHELL_SPAN * (float(j) + 0.5) / float(steps)


## Cartouches déjà insérées à l'avancement `frac` d'un rechargement coup par
## coup (reload_kind « shells ») : celles des poussées déjà faites, aux
## instants mêmes des sons (reload_sounds) et de l'animation ; 0 pour les
## autres mécanismes (chargeur, barillet...). Pure (tests, serveur).
static func shells_loaded(s: Dictionary, w: Dictionary, frac: float) -> int:
	if String(s.get("reload_kind", "")) != "shells":
		return 0
	var need := shells_needed(s, w)
	if need <= 0:
		return 0
	var steps := shell_steps(s, w)
	# Poussées faites : j tel que shell_step_time(j, steps) <= frac.
	var done := clampi(floori((frac - SHELL_START) * steps / SHELL_SPAN - 0.5 + 0.0001) + 1, 0, steps)
	return need * done / steps


## Appelé par Player._local_physics à chaque image physique.
func tick(delta: float) -> void:
	var w := current()
	var t := GameClock.now()
	throws.tick(delta)
	if w.is_empty():
		return
	var s := current_stats()
	var inp := player.input

	update_reload(t)

	# Le rechargement ne bloque pas le changement d'arme (il l'annule, BO1).
	var busy := _reload_end > 0.0 or not can_switch(t)
	var dead := false
	var pd := session.get_data(player.peer_id)
	if pd:
		dead = pd.life == PlayerData.Life.DEAD

	if not inp.fire:
		_trigger_released = true

	if not dead and _burst_left > 0:
		# Rafale en cours : les coups suivants partent seuls, même détente relâchée.
		if busy or w.mag <= 0:
			_burst_left = 0
		elif t >= _next_fire:
			_fire(w, s)
	elif not dead:
		if inp.switch_weapon and weapons.size() > 1 and can_switch(t):
			request_switch((slot + 1) % weapons.size())
		elif inp.reload and not busy and not use_takes_press(inp.interact_pressed, _use_focused()):
			_try_reload(w, s)
		elif inp.melee and t >= _melee_ready and t >= _pickup_end and not throws.busy():
			_melee()
		elif inp.fire and not busy and not player.sprinting:
			var want: bool = s.auto or _trigger_released
			if want and t >= _next_fire:
				if w.mag > 0:
					_fire(w, s)
				elif _trigger_released:
					Audio.play_2d("dry_fire", -4.0)
					_trigger_released = false
					_try_reload(w, s)
	if not dead:
		# Rechargement automatique quand le chargeur est vide.
		if w.mag == 0 and w.reserve > 0 and _reload_end < 0.0 and t >= _next_fire and not busy:
			_try_reload(w, s)

	view.scoped = scoped
	view.update(delta, player)
	# Lunette : l'écran de lunette remplace le modèle en fin de mise en joue,
	# dès l'image où la mise en joue l'atteint (jamais une image avec
	# l'oculaire et la carcasse contre l'œil).
	var was_scoped := scoped
	scoped = WeaponDB.scope_kind(s) != "" and player.aiming and view.ads >= ViewModel.SCOPE_ADS and not dead and not busy
	if scoped and not was_scoped:
		Audio.play_2d("slide", -12.0, 0.03, "SFX", 1.35)
	view.apply_scope(scoped)
	# Dispersion, recul progressif et retour, balancement dans la lunette.
	feel.update(delta, player, s, view.ads, scoped and WeaponDB.scope_kind(s) == "sniper", inp.sprint, hip_spread_mult(), t)
	deadeye.tick(self, delta)


## Multiplicateur de dispersion à la hanche (atouts : DEADEYE DRAM).
func hip_spread_mult() -> float:
	return PerkDB.hip_spread_mult(session.get_data(player.peer_id))


## Multiplicateur de recul (atouts : DEADEYE DRAM).
func recoil_mult() -> float:
	return PerkDB.recoil_mult(session.get_data(player.peer_id))


## Dispersion courante (°) : celle du prochain tir, dessinée par le réticule.
func spread_deg() -> float:
	return feel.spread


## Décalage de la visée (tangage, lacet ; rad) que Player ajoute à la caméra
## (balancement de la lunette) : les balles suivent la caméra, donc le réticule.
func aim_offset() -> Vector2:
	return feel.aim_offset


## Champ de vision de la caméra (crochet de Player) : champ de visée de
## l'arme (ads_zoom), zoom de la lunette (scope_fov, immédiat) sinon `target`.
func camera_fov(base_fov: float, target: float, fov_now: float, delta: float) -> float:
	var s := current_stats()
	if scoped and s.has("scope_fov"):
		return float(s.scope_fov)
	if player.aiming and not s.is_empty():
		var k := clampf(view.ads, 0.0, 1.0)
		target = lerpf(base_fov, base_fov * float(s.ads_zoom), k * k * (3.0 - 2.0 * k))
		if scoped:
			return target
	return lerpf(fov_now, target, 1.0 - exp(-delta * 14.0))


## Sensibilité de la souris en visée (crochet de Player) : proportionnelle au
## zoom dans la lunette, pour garder le même ressenti.
func ads_look_mult() -> float:
	if scoped:
		return 0.6 * tan(deg_to_rad(player.camera.fov) * 0.5) / tan(deg_to_rad(Settings.fov * float(current_stats().ads_zoom)) * 0.5)
	return 0.6


func _fire(w: Dictionary, s: Dictionary) -> void:
	var t := GameClock.now()
	var interval := WeaponDB.fire_interval(w.id, w.pap) / combat.game_rate_mult(player.peer_id)
	_next_fire = t + interval
	_trigger_released = false
	w.mag -= 1
	var burst: int = s.get("burst", 0)
	if burst > 1:
		_burst_left = burst - 1 if _burst_left <= 0 else _burst_left - 1
		if _burst_left <= 0 or w.mag <= 0:
			_burst_left = 0
			_next_fire += float(s.get("burst_delay", 0.2))
	# Fusil à pompe / à verrou : bruit du mécanisme entre deux coups, douille
	# éjectée au réarmement.
	var cycle: String = s.get("cycle", "")
	if cycle != "" and w.mag > 0:
		get_tree().create_timer(interval * 0.4).timeout.connect(func():
			Audio.play_2d(cycle, -4.0)
			view.eject_shell(fx, player, String(s.get("shell", ""))))

	# UNE seule vérité : le rayon de la caméra (centre du réticule, ligne de
	# mire en visée) décide de ce qui est touché. Les effets partent ensuite de
	# la bouche réelle du modèle et convergent vers ces points d'impact.
	var origin := player.camera.global_position
	var fwd := player.aim_direction()
	var spread := feel.spread
	last_spread_deg = spread
	var impacts := PackedVector3Array()
	var hits: Array = []
	last_impacts = []
	var blast: bool = s.has("blast_range")
	# Onde de choc (TONNERRE-7) : pas de balle, le serveur calcule le cône.
	for i in (0 if blast else int(s.pellets)):
		var dir := _spread_dir(fwd, spread)
		last_impacts.append(_trace(origin, dir, int(s.penetration), impacts, hits))

	# Effets locaux immédiats
	var muzzle: Vector3 = view.muzzle_global()
	WeaponAudio.play_2d(s, w.pap)
	view.fire(s, fx, player, cycle == "")
	feel.on_shot(s, view.ads, recoil_mult(), t)
	if blast:
		ThunderBlast.play_fx(fx, muzzle, fwd, w.pap, s.blast_range)
		combat.srv_fire.rpc_id(1, slot, origin, fwd, impacts, hits)
		fired.emit()
		ammo_changed.emit()
		return
	var ray_end: Vector3 = last_impacts[0][0]
	var kind: String = s.get("tracer", "")
	if s.has("projectile_speed"):
		# Grenade / roquette : projectile visible, l'explosion vient du serveur.
		ProjectileFx.launch(fx, muzzle, ray_end, s.projectile_speed, s.get("tracer", "grenade"), w.pap)
	else:
		if kind == "ray":
			fx.tracer(muzzle, ray_end, Fx.TRACER_RAY, 0.12)
		for i in last_impacts.size():
			var e: Array = last_impacts[i]
			# Traçante de la bouche au point touché (3 plombs au plus).
			if kind != "ray" and i < 3:
				fx.tracer(muzzle, e[0])
			if e[2] < 0 and e[1] != Vector3.ZERO:
				fx.impact(e[0], e[1], i == 0, e[3])
	combat.srv_fire.rpc_id(1, slot, origin, fwd, impacts, hits)
	fired.emit()
	ammo_changed.emit()


## Lancer de rayon avec pénétration : traverse jusqu'à `pen` zombies, s'arrête
## au décor. Retourne le point d'arrivée [position, normale (nulle si rien
## n'est touché), id du dernier zombie touché ou -1, surface].
func _trace(origin: Vector3, dir: Vector3, pen: int, impacts: PackedVector3Array, hits: Array) -> Array:
	var space := player.get_world_3d().direct_space_state
	var from := origin
	var exclude: Array[RID] = [player.get_rid()]
	var remaining := pen
	# Une requête gardée pour tous les segments et tous les tirs (même masque,
	# zones comprises) : seuls le départ, la fin et les exclusions changent.
	if _trace_q == null:
		_trace_q = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.FORWARD, 1 | HITBOX_LAYER)
		_trace_q.collide_with_areas = true
	var q := _trace_q
	q.to = origin + dir * RAY_LENGTH
	q.exclude = exclude
	for step in 12:
		q.from = from
		var r := space.intersect_ray(q)
		if r.is_empty():
			break
		var col: Object = r.collider
		if col is Area3D and col.has_meta("zombie_id"):
			var zid := int(col.get_meta("zombie_id"))
			hits.append([zid, int(col.get_meta("zone", 0)), origin.distance_to(r.position), r.position])
			fx.blood_hit(r.position, dir, 0.6)
			game.hud.hit_marker(false, int(col.get_meta("zone", 0)) == 1)
			exclude.append(r.rid)
			# Les autres hitboxes du même zombie ne comptent pas deux fois.
			for sib in col.get_parent().get_children():
				if sib is Area3D:
					exclude.append(sib.get_rid())
			# La requête garde une copie des exclusions : mise à jour.
			q.exclude = exclude
			remaining -= 1
			if remaining <= 0:
				return [r.position, -dir, zid, "flesh"]
			from = r.position + dir * 0.01
		else:
			impacts.append(r.position)
			impacts.append(r.normal)
			return [r.position, r.normal, -1, Fx.surface_of(col, int(r.get("shape", 0)))]
	return [origin + dir * RAY_LENGTH, Vector3.ZERO, -1, ""]


static func _spread_dir(fwd: Vector3, spread_angle: float) -> Vector3:
	if spread_angle <= 0.001:
		return fwd
	var r := deg_to_rad(spread_angle) * sqrt(randf())
	var a := randf() * TAU
	var right := fwd.cross(Vector3.UP).normalized()
	if right.length_squared() < 0.01:
		right = Vector3.RIGHT
	var up := right.cross(fwd).normalized()
	return (fwd + (right * cos(a) + up * sin(a)) * tan(r)).normalized()


## Même appui pour RECHARGER et INTERAGIR (touche partagée, comme X / Carré
## sur console dans BO1) devant un objet utilisable : l'achat ou l'action
## l'emporte, l'arme n'est pas rechargée par cet appui. Loin de tout objet,
## l'appui recharge. Pure (tests).
static func use_takes_press(interact_pressed: bool, has_focus: bool) -> bool:
	return interact_pressed and has_focus


## Un objet utilisable est visé (InteractionSystem.focused, image précédente).
func _use_focused() -> bool:
	return game != null and game.interact != null and game.interact.focused != null


func _try_reload(w: Dictionary, s: Dictionary) -> void:
	if _reload_end > 0.0 or w.mag >= s.mag or w.reserve <= 0:
		return
	var dur := combat.reload_time(player.peer_id, w)
	_reload_start = GameClock.now()
	_reload_dur = dur
	_reload_end = _reload_start + dur
	_reload_serial += 1
	var serial := _reload_serial
	view.start_reload(dur)
	_burst_left = 0
	for step in reload_sounds(s, w):
		# Rechargement annulé (ou remplacé par un autre) : son abandonné.
		get_tree().create_timer(maxf(dur * float(step[0]), 0.001)).timeout.connect(func():
			if _reload_serial == serial and _reload_end > 0.0:
				Audio.play_2d(step[1], -3.0))
	combat.srv_reload.rpc_id(1, slot)


## Suite de sons [fraction, son] d'un rechargement (cartouches une à une pour
## les fusils à pompe et lance-grenades, comme dans BO1).
static func reload_sounds(s: Dictionary, w: Dictionary) -> Array:
	var kind: String = s.get("reload_kind", "mag")
	if kind != "shells":
		return RELOAD_SOUNDS.get(kind, RELOAD_SOUNDS.mag)
	# Mêmes instants que le compte des cartouches (shells_loaded).
	var n := shell_steps(s, w)
	var out := []
	for i in n:
		out.append([shell_step_time(i, n), "shell_in"])
	out.append([0.88, "pump"])
	return out


## Coup de couteau. Si un zombie visé est à portée de fente (KnifeDB), le
## joueur se projette d'abord vers lui (LUNGE_TIME), puis frappe : le serveur
## valide le coup depuis la position d'arrivée.
func _melee() -> void:
	_melee_ready = GameClock.now() + WeaponDB.MELEE_COOLDOWN
	abort_reload()
	# À terre : pas de fente (le joueur rampe), coup au contact seulement.
	var target := _lunge_target() if not player.downed else null
	var lunge := target != null
	view.start_melee(lunge)
	Audio.play_2d("knife_swing", -4.0, 0.1)
	if not lunge:
		_strike()
		return
	var to := target.global_position - player.global_position
	to.y = 0.0
	var dist := maxf(to.length() - KnifeDB.LUNGE_STOP, 0.0)
	lunging = true
	player.start_lunge(to.normalized(), dist, KnifeDB.LUNGE_TIME)
	get_tree().create_timer(KnifeDB.LUNGE_TIME).timeout.connect(func():
		lunging = false
		_strike())


func _strike() -> void:
	var pd := session.get_data(player.peer_id)
	if pd == null or pd.life == PlayerData.Life.DEAD:
		return
	combat.srv_melee.rpc_id(1, player.camera.global_position, player.aim_direction())


## Zombie visé à portée de fente (au-delà de la portée au contact), visible.
func _lunge_target() -> Zombie:
	if game == null or game.zombies == null:
		return null
	var alive: Array[Zombie] = game.zombies.alive
	var positions := []
	for z in alive:
		positions.append(z.global_position)
	var i := KnifeDB.pick_target(player.global_position, player.aim_direction(), positions)
	if i < 0:
		return null
	var z: Zombie = alive[i]
	var flat := z.global_position - player.global_position
	flat.y = 0.0
	if not KnifeDB.needs_lunge(flat.length()):
		return null
	# Pas de fente à travers un mur ou une barricade.
	var q := PhysicsRayQueryParameters3D.create(player.eye_position(), z.global_position + Vector3.UP * 1.0, 1 | Barricade.BARRIER_LAYER, [player.get_rid()])
	if not player.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		return null
	return z


## Nouveau couteau (achat du COUTEAU DE CHASSE) : animation de récupération.
func _on_knife_changed(id: String) -> void:
	var first := knife_id == ""
	knife_id = id
	view.set_knife(id)
	if first:
		return
	_pickup_end = GameClock.now() + KnifeDB.PICKUP_TIME
	_stop_reload()
	view.start_knife_pickup(KnifeDB.PICKUP_TIME)
	Audio.play_2d("bowie_draw", -3.0)


func is_picking_up_knife() -> bool:
	return GameClock.now() < _pickup_end


## Coup de couteau, fente ou récupération du couteau en cours : pas de lancer
## de grenade pendant ce temps (ThrowController).
func is_knifing() -> bool:
	var t := GameClock.now()
	return t < _melee_ready - WeaponDB.MELEE_COOLDOWN * 0.3 or t < _pickup_end


## Lancer de grenade : le rechargement en cours est abandonné (comme BO1 ;
## le serveur l'annule aussi, voir ThrowableSystem.srv_cook).
func cancel_reload_local() -> void:
	abort_reload()


## Boisson d'un atout : l'arme est baissée, une bouteille apparaît. Le
## rechargement en cours est abandonné (BO1) avec la règle des interruptions
## (cartouches déjà poussées gardées) ; le serveur fait le même calcul
## (Combat.srv_hands_busy) et renvoie l'inventaire qui fait foi : il faudra
## recharger de nouveau après la boisson.
func drink(color: Color, duration: float) -> void:
	_drink_end = GameClock.now() + duration
	abort_reload()
	if view:  # null : contrôleur seul des tests unitaires
		view.start_drink(color, duration)
