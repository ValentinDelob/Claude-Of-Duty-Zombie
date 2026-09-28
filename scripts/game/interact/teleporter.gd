class_name Teleporter
extends Interactable
## Téléporteur (BUNKER K-7 : du quai vers la salle du rituel et son
## Pack-a-Punch ; KINO : de la scène vers la cabine de projection).
##
## Serveur : IDLE -> CHARGING (3 s) -> ACTIVE (joueurs dans la salle, 25 s)
## -> COOLDOWN (60 s) -> IDLE. Tous les joueurs présents sur la plateforme au
## moment du départ (positions serveur) sont transportés, puis ramenés.
## Chaque client déplace lui-même son joueur (autorité de mouvement), sur
## ordre du serveur.
##
## Mode « liaison » (MapDef.teleporter_link, KINO) : comme à Kino der Toten,
## après le courant il faut activer la plateforme (gratuit) puis la relier au
## poste central (TeleporterMainframe) ; chaque voyage consomme la liaison et
## ramène les joueurs devant le poste central. Option
## MapDef.pap_revealed_by_teleporter : le premier voyage fait surgir le
## Pack-a-Punch (caché jusque-là) sur la scène.

enum State { IDLE, CHARGING, ACTIVE, COOLDOWN }
enum Link { UNLINKED, PRIMED, LINKED }

const COST := 1500
const CHARGE_TIME := 3.0
const ACTIVE_TIME := 25.0
const COOLDOWN_TIME := 60.0
const PAD_RADIUS := 1.6

var state: State = State.IDLE
var exit_pos := Vector3.ZERO
var _timer := 0.0
var _travellers: Array = []
var _ring_mat: StandardMaterial3D
var _light: OmniLight3D
var _exit_ring_mat: StandardMaterial3D
var _t := 0.0
var end_time_msec := 0
## Mode liaison (KINO) et état de la liaison.
var needs_link := false
var link: Link = Link.LINKED
## Point de retour (plateforme par défaut, poste central en mode liaison).
var return_pos := Vector3.ZERO
var has_return_pos := false
## Pack-a-Punch révélé par le premier voyage ?
var reveals_pap := false
var pap_revealed := false
var mainframe: TeleporterMainframe
## Réglages de la carte (MapDef.teleporter_*).
var cost := COST
var charge_time := CHARGE_TIME
var stay_time := ACTIVE_TIME
var cooldown_time := COOLDOWN_TIME
var link_cooldown := 0.0
var kill_radius := 0.0
var _shown_link: Link = Link.LINKED
var _shown_pap := false


## Construit le téléporteur de la carte (plateforme T, arrivée F, poste
## central A en mode liaison). Retourne null si la carte n'en a pas.
static func build(game: Game) -> Teleporter:
	var spec := game.layout.teleporter()
	if spec.is_empty():
		return null
	var tp := Teleporter.new()
	tp.setup_at(spec.pad, spec.exit)
	tp.reveals_pap = game.map_def.pap_revealed_by_teleporter
	var def := game.map_def
	tp.cost = def.teleporter_cost
	tp.charge_time = def.teleporter_charge
	tp.stay_time = def.teleporter_stay
	tp.cooldown_time = def.teleporter_cooldown
	tp.link_cooldown = def.teleporter_link_cooldown
	tp.kill_radius = def.teleporter_kill_radius
	var mf: MapMarker = spec.get("mainframe")
	if game.map_def.teleporter_link and mf != null:
		tp.needs_link = true
		tp.link = Link.UNLINKED
		tp._shown_link = Link.UNLINKED
		tp.mainframe = TeleporterMainframe.new()
		tp.mainframe.setup_marker(mf)
		tp.mainframe.teleporter = tp
		tp.return_pos = tp.mainframe.arrival_point()
		tp.has_return_pos = true
		game.interact.register(tp.mainframe)
		game.world.add_child(tp.mainframe)
		game.layout.set_blocked(mf.block, true)
	game.interact.register(tp)
	game.world.add_child(tp)
	return tp


## Plateforme centrée en `pad` (au sol), arrivée des voyageurs en `exit`.
func setup_at(pad: Vector3, exit: Vector3) -> void:
	interact_id = "teleporter"
	name = "Teleporter"
	position = pad
	exit_pos = exit
	interact_range = 2.4


func _ready() -> void:
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = Color(0.1, 0.05, 0.02)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = Color(1.0, 0.5, 0.15)
	_ring_mat.emission_energy_multiplier = 0.0
	_build_pad(self, 1.0, _ring_mat)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.omni_range = 6.0
	_light.light_energy = 0.0
	_light.position = Vector3(0, 1.5, 0)
	add_child(_light)
	# Plateforme d'arrivée dans la salle du rituel.
	_exit_ring_mat = _ring_mat.duplicate()
	var exit_pad := Node3D.new()
	exit_pad.name = "ExitPad"
	get_parent().add_child.call_deferred(exit_pad)
	exit_pad.position = exit_pos - Vector3(0, 0.05, 0)
	_build_pad(exit_pad, 0.7, _exit_ring_mat)
	system.game.power_changed.connect(func(_on): _refresh())
	_refresh()
	if reveals_pap:
		_apply_pap(false)


func _pap() -> PackAPunch:
	return system.game.interact.get_obj("pap") as PackAPunch


func _apply_pap(animate: bool) -> void:
	var pap := _pap()
	if pap:
		pap.set_revealed(pap_revealed, animate)


func _build_pad(parent: Node3D, scale_k: float, ring_mat: Material) -> void:
	var steel := WorldLook.surface("steel")
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 1.4 * scale_k
	dm.bottom_radius = 1.5 * scale_k
	dm.height = 0.12
	dm.radial_segments = 18
	disc.mesh = dm
	disc.material_override = steel
	disc.position.y = 0.06
	parent.add_child(disc)
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 1.05 * scale_k
	rm.outer_radius = 1.2 * scale_k
	rm.rings = 18
	rm.ring_segments = 6
	ring.mesh = rm
	ring.material_override = ring_mat
	ring.position.y = 0.13
	parent.add_child(ring)
	# Quatre bobines.
	for k in 4:
		var a := k * TAU / 4.0 + PI / 4.0
		var coil := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.06
		cm.bottom_radius = 0.12
		cm.height = 1.6 * scale_k
		cm.radial_segments = 8
		coil.mesh = cm
		coil.material_override = steel
		coil.position = Vector3(cos(a), 0, sin(a)) * 1.3 * scale_k + Vector3(0, 0.8 * scale_k, 0)
		parent.add_child(coil)
		var tip := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.1
		sm.height = 0.2
		tip.mesh = sm
		tip.material_override = ring_mat
		tip.position = coil.position + Vector3(0, 0.85 * scale_k, 0)
		parent.add_child(tip)


func _refresh() -> void:
	var on := system.game.power_on
	_ring_mat.emission_energy_multiplier = 1.5 if on else 0.0
	_exit_ring_mat.emission_energy_multiplier = 1.0 if on else 0.0


func interact_point() -> Vector3:
	return global_position + Vector3.UP * 1.0


func prompt(_pid: int) -> String:
	if state != State.IDLE:
		return ""
	if not system.game.power_on:
		return "Le courant doit être rétabli"
	match link:
		Link.UNLINKED:
			return "[F] Activer la plateforme du téléporteur"
		Link.PRIMED:
			return "Reliez le téléporteur au poste central (hall d'entrée)"
	if cost <= 0:
		return "[F] Activer le téléporteur"
	return "[F] Activer le téléporteur %s" % Interactable.cost_text(cost)


func srv_use(pid: int) -> void:
	var game := system.game
	if state != State.IDLE:
		return
	if not game.power_on:
		system.deny(pid, "Pas de courant")
		return
	if link == Link.UNLINKED:
		link = Link.PRIMED
		print("[Teleporter] plateforme activée : à relier au poste central")
		broadcast_state()
		return
	if link == Link.PRIMED:
		return
	if cost > 0 and not game.session.try_spend(pid, cost):
		system.deny(pid, "Pas assez de points")
		return
	system.purchase_fx(self)
	_timer = charge_time
	_set_state(State.CHARGING)


## Serveur : le poste central relie la plateforme activée.
func srv_link(pid: int) -> void:
	if not system.game.power_on:
		system.deny(pid, "Pas de courant")
		return
	if link != Link.PRIMED:
		return
	link = Link.LINKED
	print("[Teleporter] téléporteur relié au poste central")
	broadcast_state()


func _set_state(s: State) -> void:
	state = s
	end_time_msec = Time.get_ticks_msec() + int(_timer * 1000.0)
	broadcast_state()


func _process(delta: float) -> void:
	_animate(delta)
	if not multiplayer.is_server() or state == State.IDLE:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	var game := system.game
	match state:
		State.CHARGING:
			_travellers = []
			for p: Player in game.players.values():
				var pd := game.session.get_data(p.peer_id)
				var flat := p.global_position - global_position
				var dy := absf(flat.y)
				flat.y = 0.0
				# Tolérance verticale : pas de voyageur à l'étage du dessus.
				if pd and pd.life == PlayerData.Life.ALIVE and flat.length() <= PAD_RADIUS and dy < 1.5:
					_travellers.append(p.peer_id)
			if _travellers.is_empty():
				# Personne sur la plateforme : l'énergie se dissipe (et la
				# liaison est perdue).
				if needs_link:
					link = Link.UNLINKED
				_timer = cooldown_time * 0.25
				_set_state(State.COOLDOWN)
				return
			for i in _travellers.size():
				var off := Vector3(cos(i * 1.7), 0, sin(i * 1.7)) * (0.6 if i > 0 else 0.0)
				_send(_travellers[i], exit_pos + off, true)
			print("[Teleporter] %d joueur(s) téléporté(s)" % _travellers.size())
			_kill_around_pad()
			if reveals_pap and not pap_revealed:
				pap_revealed = true
				print("[Teleporter] le Pack-a-Punch apparaît")
			_timer = stay_time
			_set_state(State.ACTIVE)
		State.ACTIVE:
			var back := return_pos if has_return_pos else global_position
			for i in _travellers.size():
				var off := Vector3(cos(i * 1.7), 0, sin(i * 1.7)) * 0.7
				_send(_travellers[i], back + off + Vector3(0, 0.05, 0), false)
			_travellers = []
			if needs_link:
				# Comme à Kino : il faut relier à nouveau avant chaque voyage.
				link = Link.UNLINKED
				if link_cooldown > 0.0:
					# Kino der Toten : 90 s avant de pouvoir relier à nouveau.
					_timer = link_cooldown
					_set_state(State.COOLDOWN)
				else:
					_set_state(State.IDLE)
				return
			_timer = cooldown_time
			_set_state(State.COOLDOWN)
		State.COOLDOWN:
			_set_state(State.IDLE)


## Serveur : ordonne au client propriétaire de déplacer son joueur.
func _send(pid: int, pos: Vector3, outbound: bool) -> void:
	system.game.teleport_player(pid, pos, outbound)


func get_state() -> Dictionary:
	return {"state": state, "remaining": _timer, "link": link, "pap": pap_revealed}


func apply_state(s: Dictionary, animate: bool) -> void:
	state = s.get("state", State.IDLE)
	end_time_msec = Time.get_ticks_msec() + int(float(s.get("remaining", 0.0)) * 1000.0)
	if animate and state == State.CHARGING:
		Audio.play_3d("tele_charge", global_position + Vector3.UP, 0.0, 0.0)
	# Visuels comparés à ce qui est affiché (le serveur a déjà modifié l'état).
	link = s.get("link", link)
	if link != _shown_link and animate:
		if link == Link.PRIMED:
			Audio.play_3d("lever", global_position + Vector3.UP, 0.0, 0.02)
			Audio.play_3d("tele_charge", global_position + Vector3.UP, -8.0, 0.1)
		elif link == Link.LINKED and mainframe:
			Audio.play_3d("lever", mainframe.interact_point(), 0.0, 0.02)
			Audio.play_3d("power_on", mainframe.interact_point(), -6.0, 0.0)
			system.game.hud.show_banner("TÉLÉPORTEUR RELIÉ", 1.5)
	_shown_link = link
	if mainframe:
		mainframe.refresh()
	pap_revealed = s.get("pap", pap_revealed)
	if pap_revealed != _shown_pap:
		_shown_pap = pap_revealed
		_apply_pap(animate)


func seconds_left() -> int:
	return maxi(0, int(ceil((end_time_msec - Time.get_ticks_msec()) / 1000.0)))


func _animate(delta: float) -> void:
	if _ring_mat == null:
		return
	_t += delta
	var on := system.game.power_on
	match state:
		State.CHARGING:
			var k := 1.0 - clampf((end_time_msec - Time.get_ticks_msec()) / (charge_time * 1000.0), 0.0, 1.0)
			_ring_mat.emission = Color(1.0, 0.6, 0.3).lerp(Color(1, 1, 1), k)
			_ring_mat.emission_energy_multiplier = 2.0 + k * 10.0 + sin(_t * 40.0) * 2.0
			_light.light_energy = 1.0 + k * 5.0
			if randf() < delta * 30.0:
				var a := randf() * TAU
				system.game.fx_root.sparks.burst(global_position + Vector3(cos(a), 1.6, sin(a)) * 1.3, Vector3.UP, 2, 3.0, 1.0, 0.3, Color(1.0, 0.8, 0.5))
		State.COOLDOWN:
			_ring_mat.emission = Color(1.0, 0.12, 0.05)
			_ring_mat.emission_energy_multiplier = 0.8 + 0.4 * sin(_t * 3.0)
			_light.light_energy = 0.3
		_:
			if on and link != Link.LINKED:
				# Non relié : lueur bleutée faible ; plateforme activée : clignote.
				var blink := link == Link.PRIMED and fmod(_t, 0.8) < 0.4
				_ring_mat.emission = Color(0.4, 0.6, 1.0)
				_ring_mat.emission_energy_multiplier = 3.0 if blink else 0.6
				_light.light_energy = 0.8 if blink else 0.15
				return
			_ring_mat.emission = Color(1.0, 0.5, 0.15)
			_ring_mat.emission_energy_multiplier = (1.5 + 0.3 * sin(_t * 2.0)) if on else 0.0
			_light.light_energy = 0.6 if on else 0.0


## Serveur, au départ : les zombies proches de la plateforme sont foudroyés
## (Kino der Toten : 300 unités autour du pad), sans points.
func _kill_around_pad() -> void:
	if kill_radius <= 0.0:
		return
	var game := system.game
	var n := 0
	for z: Zombie in game.zombies.alive.duplicate():
		if z.is_alive() and z.global_position.distance_to(global_position) <= kill_radius:
			var dir := z.global_position - global_position
			dir.y = 0.0
			# pid 0 : aucun point ni bonus (comme la Nuke).
			game.combat.damage_zombie(z.id, z.health + 1, 0, false, dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD, Combat.HitKind.SPECIAL)
			n += 1
	if n > 0:
		print("[Teleporter] %d zombie(s) foudroyé(s) au départ" % n)
