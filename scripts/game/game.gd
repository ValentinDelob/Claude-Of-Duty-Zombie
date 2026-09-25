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
}
const DEFAULT_MAP := "bunker_k7"

## Carte à charger (les tests peuvent imposer l'arène avec --map=test_arena).
static func requested_map() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			return a.substr(6)
	return DEFAULT_MAP

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
var spawner: Spawner
var props: PropBuilder
var doors: Dictionary = {}  # id -> Door
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
	Net.player_left.connect(_on_player_left)
	Net.session_ended.connect(_on_session_ended)
	if multiplayer.is_server():
		Net.all_loaded.connect(_on_all_loaded)
		combat.player_fell.connect(_on_player_fell)
	Audio.play_music("ambience_bunker", -6.0, 3.0)
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
	WorldLook.setup_environment(world)
	_build_doors()
	print("[Game] carte « %s » construite (%dx%d)" % [map_def.display_name, map_data.width, map_data.height])


# --------------------------------------------------------------------------
# Démarrage de la manche / apparition des joueurs
# --------------------------------------------------------------------------

func _on_all_loaded() -> void:
	if not multiplayer.is_server() or not players.is_empty():
		return
	print("[Game] tout le monde a chargé, lancement")
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
	GameState.set_state(GameState.State.PLAYING)
	capture_mouse(true)
	if multiplayer.is_server():
		session.sync_all()
		rounds.start_game()


func _spawn_player(pid: int, pos: Vector3) -> void:
	if players.has(pid):
		return
	var p := Player.new()
	p.setup(pid, pid == multiplayer.get_unique_id())
	players_root.add_child(p)
	p.teleport_to(pos, PI)
	players[pid] = p
	if p.is_local:
		local_player = p
		p.weapons = WeaponController.new()
		p.weapons.name = "Weapons"
		p.add_child(p.weapons)
		p.weapons.setup(p, self)
		hud.bind_player(p)
	print("[Game] joueur %s (%d) apparu%s" % [Net.player_name(pid), pid, " (local)" if p.is_local else ""])


func _on_player_left(pid: int) -> void:
	_cl_remove_player.rpc(pid)


@rpc("authority", "call_local", "reliable")
func _cl_remove_player(pid: int) -> void:
	if players.has(pid):
		players[pid].queue_free()
		players.erase(pid)
	session.remove(pid)
	combat.forget_player(pid)


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
	if event.is_action_pressed("pause"):
		capture_mouse(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)
	elif event is InputEventMouseButton and event.pressed and GameState.is_in_game() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		capture_mouse(true)




# --------------------------------------------------------------------------
# Mort des joueurs et fin de partie
# --------------------------------------------------------------------------

const GAME_OVER_DELAY := 9.0


## Serveur : un joueur est tombé à 0 PV.
func _on_player_fell(pid: int) -> void:
	var pd := session.get_data(pid)
	if pd == null:
		return
	pd.life = PlayerData.Life.DEAD
	pd.downs += 1
	session.sync_stats(pid)
	_cl_player_died.rpc(pid)
	check_game_over()


## Serveur : fin de partie si plus aucun joueur n'est debout.
func check_game_over() -> void:
	if not multiplayer.is_server() or GameState.state == GameState.State.GAME_OVER:
		return
	for pd: PlayerData in session.data.values():
		if pd.life == PlayerData.Life.ALIVE:
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
	hud.show_center("GAME OVER", summary, 0.6)
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
