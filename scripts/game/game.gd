class_name Game
extends Node3D
## Racine d'une partie (chemin réseau : /root/Game).
##
## Construit la carte de façon déterministe sur chaque machine (mêmes chemins de
## nœuds partout, indispensable aux RPC), attend que tout le monde ait chargé,
## puis fait apparaître les joueurs.

static var instance: Game

const MAP_SCRIPTS := {
	"test_arena": "res://scripts/game/map/maps/test_arena.gd",
}

var map_def: MapDef
var map_data: MapData
var players: Dictionary = {}  # peer_id -> Player
var local_player: Player

@onready var world: Node3D = $World
@onready var players_root: Node3D = $Players
@onready var fx_root: Node3D = $Fx
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
	_load_map("test_arena")
	Net.player_left.connect(_on_player_left)
	Net.session_ended.connect(_on_session_ended)
	if multiplayer.is_server():
		Net.all_loaded.connect(_on_all_loaded)
	Net.report_loaded()


func _load_map(map_id: String) -> void:
	map_def = load(MAP_SCRIPTS[map_id]).new()
	map_data = MapData.parse(map_def.rows)
	var builder := MapBuilder.new(map_data)
	builder.materials = WorldLook.map_materials()
	builder.build(world)
	WorldLook.setup_environment(world)
	WorldLook.place_lamps(world, map_data)
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
		var slot: int = roster[pid].slot
		var pos := MapData.cell_to_world(spawns[slot % spawns.size()], 0.05) if not spawns.is_empty() else Vector3(2, 0.1, 2)
		_spawn_player(pid, pos)
	GameState.set_state(GameState.State.PLAYING)
	capture_mouse(true)


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
		hud.bind_player(p)
	print("[Game] joueur %s (%d) apparu%s" % [Net.player_name(pid), pid, " (local)" if p.is_local else ""])


func _on_player_left(pid: int) -> void:
	_cl_remove_player.rpc(pid)


@rpc("authority", "call_local", "reliable")
func _cl_remove_player(pid: int) -> void:
	if players.has(pid):
		players[pid].queue_free()
		players.erase(pid)


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
