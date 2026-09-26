class_name Game
extends Node3D
## Racine d'une partie (chemin réseau : /root/Game).
##
## Construit la carte de façon déterministe sur chaque machine (mêmes chemins de
## nœuds partout, indispensable aux RPC), attend que tout le monde ait chargé,
## puis fait apparaître les joueurs.

static var instance: Game

const MAP_SCRIPTS := {
	"bunker_k7": "res://scripts/game/map/maps/bunker_k7.gd",
	"test_arena": "res://scripts/game/map/maps/test_arena.gd",
	"kino": "res://scripts/game/map/maps/kino.gd",
}
const DEFAULT_MAP := "bunker_k7"
## Cartes proposées dans les menus (sélection solo, salon de l'hôte).
const MENU_MAPS := ["bunker_k7", "kino"]

## Carte à charger (les tests peuvent imposer l'arène avec --map=test_arena),
## sinon la dernière carte choisie dans le menu (Settings.last_map).
static func requested_map() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			return a.substr(6)
	return Settings.last_map if MAP_SCRIPTS.has(Settings.last_map) else DEFAULT_MAP

var map_def: MapDef
var map_data: MapData
## Navigation des zombies (serveur uniquement).
var nav: NavGrid
var players: Dictionary = {}  # peer_id -> Player
var local_player: Player

@onready var world: Node3D = $World
@onready var players_root: Node3D = $Players
@onready var fx_root: Fx = $Fx
@onready var session: Session = $Session
@onready var combat: Combat = $Combat
@onready var zombies: ZombieManager = $Zombies
@onready var points: Points = $Points
@onready var rounds: RoundManager = $Rounds
@onready var interact: InteractionSystem = $Interact
@onready var perks: PerkSystem = $Perks
@onready var downed: DownedSystem = $Downed
var spawner: Spawner
var props: PropBuilder
var doors: Dictionary = {}  # id -> Door
## Courant rétabli ? (répliqué par PowerSwitch)
var power_on := false
var teleporter: Teleporter
## Bonus (chemin réseau : /root/Game/Powerups).
var powerups: PowerupSystem
## Fenêtres barricadées (marqueurs W).
var barricades: BarricadeSystem
## Grenades et SINGE-TAMBOUR (chemin réseau : /root/Game/Throwables).
var throwables: ThrowableSystem
signal power_changed(on: bool)
@onready var hud: Hud = $HUD


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	if GameState.state == GameState.State.MAIN_MENU:
		GameState.set_state(GameState.State.LOADING)
	_load_map(Net.current_map if MAP_SCRIPTS.has(Net.current_map) else requested_map())
	powerups = PowerupSystem.new()
	powerups.name = "Powerups"
	add_child(powerups)
	throwables = ThrowableSystem.new()
	throwables.name = "Throwables"
	add_child(throwables)
	Net.player_left.connect(_on_player_left)
	Net.session_ended.connect(_on_session_ended)
	session.inventory_changed.connect(_refresh_remote_weapon)
	if multiplayer.is_server():
		Net.all_loaded.connect(_on_all_loaded)
		combat.player_fell.connect(_on_player_fell)
	Audio.play_music(map_def.music, -6.0, 3.0)
	hud.show_loading(map_def.display_name)
	var spawns: Array = map_data.markers.get(map_def.player_spawn_marker(), [])
	var warm_at := MapData.cell_to_world(spawns[0]) if not spawns.is_empty() else Vector3(2, 0, 2)
	var t0 := Time.get_ticks_msec()
	await Warmup.run(self, warm_at)
	print("[Game] préchauffage des shaders : %d ms" % (Time.get_ticks_msec() - t0))
	Net.report_loaded()


func _load_map(map_id: String) -> void:
	map_def = load(MAP_SCRIPTS[map_id]).new()
	map_data = MapData.parse(map_def.rows)
	if multiplayer.is_server():
		nav = NavGrid.new(map_data)
		nav.set_blocked(MapDef.blocking_cells(map_data, map_def), true)
		spawner = Spawner.new(self)
	var builder := MapBuilder.new(map_data, map_def)
	builder.materials = WorldLook.map_materials()
	builder.build(world)
	props = PropBuilder.new(map_data, map_def)
	props.build(world)
	WorldLook.setup_environment(world, map_def.look)
	_build_doors()
	_build_wall_buys()
	_build_power()
	_build_perk_machines()
	_build_mystery_box()
	_build_pack_a_punch()
	_build_teleporter()
	_build_traps()
	_build_barricades()
	print("[Game] carte « %s » construite (%dx%d)" % [map_def.display_name, map_data.width, map_data.height])


# --------------------------------------------------------------------------
# Démarrage de la manche / apparition des joueurs
# --------------------------------------------------------------------------

func _on_all_loaded() -> void:
	if not multiplayer.is_server() or not players.is_empty():
		return
	print("[Game] tout le monde a chargé, lancement")
	var box := interact.get_obj("box") as MysteryBox
	if box and not map_def.box_starts.is_empty():
		box.srv_random_start(map_def.box_starts)
	_cl_begin_match.rpc(Net.players)


@rpc("authority", "call_local", "reliable")
func _cl_begin_match(roster: Dictionary) -> void:
	var spawns: Array = map_data.markers.get(map_def.player_spawn_marker(), [])
	for pid in roster:
		session.create(pid)
	for pid in roster:
		var slot: int = roster[pid].slot
		var pos := MapData.cell_to_world(spawns[slot % spawns.size()], 0.05) if not spawns.is_empty() else Vector3(2, 0.1, 2)
		_spawn_player(pid, pos)
	_match_start_ms = Time.get_ticks_msec()
	GameState.set_state(GameState.State.PLAYING)
	capture_mouse(true)
	hud.hide_loading()
	if multiplayer.is_server():
		session.sync_all()
		rounds.start_game()


func _spawn_player(pid: int, pos: Vector3) -> void:
	if players.has(pid):
		return
	var p := Player.new()
	p.setup(pid, pid == multiplayer.get_unique_id())
	players_root.add_child(p)
	var rt := ReviveTarget.new()
	rt.setup(pid)
	interact.register(rt)
	p.add_child(rt)
	p.revive_target = rt
	p.teleport_to(pos, PI)
	players[pid] = p
	if p.is_local:
		local_player = p
		p.weapons = WeaponController.new()
		p.weapons.name = "Weapons"
		p.add_child(p.weapons)
		p.weapons.setup(p, self)
		hud.bind_player(p)
	if not p.is_local:
		_refresh_remote_weapon(pid)
	print("[Game] joueur %s (%d) apparu%s" % [Net.player_name(pid), pid, " (local)" if p.is_local else ""])


func _on_player_left(pid: int) -> void:
	_cl_remove_player.rpc(pid)


@rpc("authority", "call_local", "reliable")
func _cl_remove_player(pid: int) -> void:
	if players.has(pid) and players[pid].revive_target:
		interact.unregister(players[pid].revive_target)
	if players.has(pid):
		players[pid].queue_free()
		players.erase(pid)
	session.remove(pid)
	combat.forget_player(pid)
	if multiplayer.is_server():
		downed.forget(pid)
		check_game_over.call_deferred()


func _on_session_ended(reason: String) -> void:
	print("[Game] session terminée : " + reason)
	Router.back_to_menu(reason)


# --------------------------------------------------------------------------
# Utilitaires
# --------------------------------------------------------------------------

func capture_mouse(on: bool) -> void:
	if Autotest.active:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	# Le menu pause est géré par le HUD ; un clic recapture la souris.
	if event is InputEventMouseButton and event.pressed and GameState.is_in_game() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not hud.pause_menu.visible:
		capture_mouse(true)




# --------------------------------------------------------------------------
# Mort des joueurs et fin de partie
# --------------------------------------------------------------------------

const GAME_OVER_DELAY := 9.0
## Début de la partie (dossier de combat : temps de jeu).
var _match_start_ms := 0


## Serveur : un joueur est tombé à 0 PV : il passe à terre (DOWNED).
func _on_player_fell(pid: int) -> void:
	downed.srv_down(pid)


## Serveur : mort définitive (saignement terminé...). Retour à la manche suivante.
func kill_player(pid: int) -> void:
	var pd := session.get_data(pid)
	if pd == null:
		return
	pd.life = PlayerData.Life.DEAD
	perks.srv_clear(pid)
	session.sync_stats(pid)
	_cl_player_died.rpc(pid)
	check_game_over()


## Serveur : fin de partie si plus aucun joueur n'est debout.
func check_game_over() -> void:
	if not multiplayer.is_server() or GameState.state == GameState.State.GAME_OVER:
		return
	for pd: PlayerData in session.data.values():
		if pd.life == PlayerData.Life.ALIVE or downed.will_self_revive(pd.peer_id):
			return
	print("[Game] tous les joueurs sont tombés : GAME OVER")
	_cl_game_over.rpc(game_over_summary())


func game_over_summary() -> String:
	var kills := 0
	for pd: PlayerData in session.data.values():
		kills += pd.kills
	return "%d zombies abattus" % kills


@rpc("authority", "call_local", "reliable")
func _cl_player_died(pid: int) -> void:
	var p: Player = players.get(pid)
	if p:
		p.set_dead(true)
	if pid == multiplayer.get_unique_id():
		hud.show_center("VOUS ÊTES MORT", "", 0.35)


@rpc("authority", "call_local", "reliable")
func _cl_game_over(summary: String) -> void:
	if GameState.state != GameState.State.GAME_OVER:
		GameState.set_state(GameState.State.GAME_OVER)
	CareerStats.record_game(session.local_data(), rounds.round_n, Net.mode == Net.Mode.SOLO,
			(Time.get_ticks_msec() - _match_start_ms) / 1000.0)
	hud.show_center("GAME OVER", summary, 0.6)
	hud.show_game_over_table("VOUS AVEZ SURVÉCU %d MANCHE%s" % [rounds.round_n, "S" if rounds.round_n > 1 else ""])
	capture_mouse(false)
	Audio.play_2d("heartbeat", 0.0, 0.0)
	# Le serveur part en dernier pour que les clients ne voient pas « connexion perdue ».
	var delay := GAME_OVER_DELAY + (0.8 if multiplayer.is_server() else 0.0)
	get_tree().create_timer(delay).timeout.connect(_leave_after_game_over.bind(summary))


func _leave_after_game_over(summary: String) -> void:
	Router.back_to_menu("Partie terminée — " + summary)


## Serveur : les joueurs morts reviennent au début de chaque manche (pistolet
## de départ, points conservés).
func respawn_dead_players() -> void:
	var spawns: Array = map_data.markers.get(map_def.player_spawn_marker(), [])
	for pid in session.data:
		var pd: PlayerData = session.data[pid]
		if pd.life != PlayerData.Life.DEAD:
			continue
		pd.life = PlayerData.Life.ALIVE
		pd.health = pd.max_health
		pd.weapons = [WeaponDB.new_instance(WeaponDB.STARTING_WEAPON)]
		pd.slot = 0
		pd.knife = KnifeDB.DEFAULT  # le couteau de chasse est perdu (BO1)
		session.sync_stats(pid)
		session.sync_inventory(pid)
		var c: Vector2i = spawns[Net.player_slot(pid) % spawns.size()]
		_cl_respawn.rpc(pid, MapData.cell_to_world(c, 0.05))


@rpc("authority", "call_local", "reliable")
func _cl_respawn(pid: int, pos: Vector3) -> void:
	var p: Player = players.get(pid)
	if p == null:
		return
	p.set_dead(false)
	if p.is_local:
		p.teleport_to(pos)
		p._eye_height = Player.EYE_HEIGHT
		hud.show_center("", "", 0.0)


func _build_doors() -> void:
	var root := Node3D.new()
	root.name = "Doors"
	world.add_child(root)
	for id in map_def.doors:
		for group in MapDef.group_cells(map_data.markers.get(id, [])):
			var d := Door.new()
			d.setup(id, group, map_def.doors[id].cost, map_data)
			root.add_child(d)
			doors[id] = d
			interact.register(d)


func _build_wall_buys() -> void:
	var root := Node3D.new()
	root.name = "WallBuys"
	world.add_child(root)
	for marker in map_def.wall_buys:
		for c in map_data.markers.get(marker, []):
			var wb := WallBuy.new()
			wb.setup(marker, c, map_def.wall_buys[marker], map_data)
			root.add_child(wb)
			interact.register(wb)


func _build_power() -> void:
	var cells: Array = map_data.markers.get("G", [])
	if cells.is_empty():
		# Carte sans générateur : le courant est là dès le départ.
		props.power.apply_immediate(true)
		set_power(true)
		return
	props.power.apply_immediate(false)
	var sw := PowerSwitch.new()
	sw.setup(cells[0], map_data)
	world.add_child(sw)
	interact.register(sw)


func set_power(on: bool) -> void:
	if power_on == on:
		return
	power_on = on
	power_changed.emit(on)


func _build_perk_machines() -> void:
	var root := Node3D.new()
	root.name = "PerkMachines"
	world.add_child(root)
	for marker in map_def.perks:
		for c in map_data.markers.get(marker, []):
			var m := PerkMachine.new()
			m.setup(marker, c, map_def.perks[marker], map_data)
			interact.register(m)
			root.add_child(m)


func _build_mystery_box() -> void:
	var cells: Array = map_data.markers.get("X", [])
	if cells.is_empty():
		return
	var root := Node3D.new()
	root.name = "Box"
	world.add_child(root)
	var box := MysteryBox.new()
	box.setup(cells, map_def.box_start, map_data)
	interact.register(box)
	root.add_child(box)
	if nav:
		for c in cells:
			nav.set_blocked(MysteryBox.spot_cells(c, map_data), true)


func _build_pack_a_punch() -> void:
	var cells: Array = map_data.markers.get("K", [])
	if cells.is_empty():
		return
	var pap := PackAPunch.new()
	pap.setup(cells[0], map_data)
	interact.register(pap)
	world.add_child(pap)
	if nav:
		nav.set_blocked(MysteryBox.spot_cells(cells[0], map_data), true)


func _build_teleporter() -> void:
	teleporter = Teleporter.build(self)


## Serveur : téléporte un joueur (son client le déplace : autorité de mouvement).
func teleport_player(pid: int, pos: Vector3, outbound: bool) -> void:
	if multiplayer.is_server():
		_cl_teleport.rpc(pid, pos, outbound)


@rpc("authority", "call_local", "reliable")
func _cl_teleport(pid: int, pos: Vector3, outbound: bool) -> void:
	var p: Player = players.get(pid)
	if p == null:
		return
	Audio.play_3d("tele_warp", p.global_position + Vector3.UP, 0.0, 0.0)
	fx_root.explosion_light(p.global_position + Vector3.UP, Color(1.0, 0.7, 0.4))
	if p.is_local:
		p.teleport_to(pos)
		hud.teleport_flash()
		if outbound:
			hud.show_banner(map_def.teleport_banner, 1.5)
	else:
		p._snapshots.clear()
		p.global_position = pos


func _build_traps() -> void:
	# Chaque levier H commande le bloc de cases E le plus proche (KINO : deux
	# pièges ; le premier garde l'identifiant « trap »).
	var groups := MapDef.group_cells(map_data.markers.get("E", []))
	var levers: Array = map_data.markers.get("H", [])
	for i in levers.size():
		var best := -1
		var best_d := INF
		for g in groups.size():
			var d := MapData.cells_center(groups[g]).distance_to(MapData.cell_to_world(levers[i]))
			if d < best_d:
				best_d = d
				best = g
		if best < 0:
			return
		var trap := ElectricTrap.new()
		trap.setup(levers[i], groups[best], map_data, "trap" if i == 0 else "trap_%d" % (i + 1))
		interact.register(trap)
		world.add_child(trap)


func _build_barricades() -> void:
	barricades = BarricadeSystem.new()
	barricades.name = "Barricades"
	add_child(barricades)
	barricades.setup(self)


## Serveur : reconstruit toutes les fenêtres (bonus CHARPENTIER).
func repair_all_barricades() -> void:
	if multiplayer.is_server() and barricades:
		barricades.srv_repair_all()


## Serveur : au moins une planche manque (condition d'apparition du CHARPENTIER, comme BO1).
func barricades_need_repair() -> bool:
	if barricades == null:
		return false
	for b in barricades.windows:
		if b.mask != BarricadeRules.FULL_MASK:
			return true
	return false


## Arme tenue par un joueur distant (modèle 3e personne).
func _refresh_remote_weapon(pid: int) -> void:
	var p: Player = players.get(pid)
	var pd := session.get_data(pid)
	if p == null or p.is_local or pd == null:
		return
	var w := pd.current_weapon()
	p.visual.set_weapon(w.get("id", ""), w.get("pap", false))


# --------------------------------------------------------------------------
# Spectateur (joueur mort en multijoueur)
# --------------------------------------------------------------------------

var spectating: Player
var _spectate_index := 0


func _process(_delta: float) -> void:
	_update_spectator()


func _update_spectator() -> void:
	if local_player == null:
		return
	var pd := session.local_data()
	var is_dead := pd != null and pd.life == PlayerData.Life.DEAD and GameState.state != GameState.State.GAME_OVER
	var others: Array = []
	for p: Player in players.values():
		if not p.is_local:
			var opd := session.get_data(p.peer_id)
			if opd and opd.life != PlayerData.Life.DEAD:
				others.append(p)
	if not is_dead or others.is_empty():
		if spectating:
			spectating = null
			local_player.camera.make_current()
			hud.set_spectating("")
		return
	if Input.is_action_just_pressed("fire"):
		_spectate_index += 1
	var target: Player = others[_spectate_index % others.size()]
	if target != spectating:
		spectating = target
		target.camera.make_current()
		hud.set_spectating(Net.player_name(target.peer_id))
