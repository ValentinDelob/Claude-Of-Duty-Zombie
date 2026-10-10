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
	"test_levels": "res://scripts/game/map/maps/test_levels.gd",
	"draft_arena": "res://scripts/game/map/maps/draft_arena.gd",
}
const DEFAULT_MAP := "bunker_k7"
## Cartes proposées dans les menus (sélection solo, salon de l'hôte).
const MENU_MAPS := ["bunker_k7"]

## Carte à charger (les tests peuvent imposer l'arène avec --map=test_arena),
## sinon la dernière carte choisie dans le menu (Settings.last_map).
static func requested_map() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			return a.substr(6)
	return Settings.last_map if has_map(Settings.last_map) else DEFAULT_MAP


## Carte connue : du registre, ou carte du joueur faite dans l'éditeur
## (« perso:<id> », dossier user://maps/<id>/).
static func has_map(map_id: String) -> bool:
	if MAP_SCRIPTS.has(map_id):
		return true
	# Identifiant venu d'ailleurs (réseau, ligne de commande, réglages) : jamais
	# un chemin (CustomMapGuard.game_map_id_ok) avant de toucher au disque.
	if not CustomMapGuard.game_map_id_ok(map_id):
		return false
	# Carte perso reçue d'un hôte (MapShare) : dans le cache, nommée par son hash.
	if map_id.begins_with(EditorMapDef.SHARED_PREFIX):
		return CustomMapGuard.is_cached(map_id.trim_prefix(EditorMapDef.SHARED_PREFIX))
	return map_id.begins_with(EditorMapDef.CUSTOM_PREFIX) and EditorMap.is_map_dir(EditorMap.map_dir(map_id.trim_prefix(EditorMapDef.CUSTOM_PREFIX)))


## Définition d'une carte (null si inconnue ou si son identifiant est refusé).
static func make_map_def(map_id: String) -> MapDef:
	if MAP_SCRIPTS.has(map_id):
		return load(MAP_SCRIPTS[map_id]).new()
	if not CustomMapGuard.game_map_id_ok(map_id):
		return null
	if map_id.begins_with(EditorMapDef.CUSTOM_PREFIX):
		return EditorMapDef.custom(map_id)
	if map_id.begins_with(EditorMapDef.SHARED_PREFIX):
		return EditorMapDef.shared(map_id)
	return null

var map_def: MapDef
## Grille de la carte (cartes ASCII seulement, null sinon).
var map_data: MapData
## Géométrie de la carte vue par les systèmes de jeu (zones, emplacements,
## navigation, bloqueurs).
var layout: MapLayout
## Navigation des zombies (serveur uniquement).
var nav: MapNav
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
@onready var downed: DownedSystem = $Downed
var spawner: Spawner
var props: MapProps
var doors: Dictionary = {}  # id -> Door
## Courant rétabli ? (répliqué par PowerSwitch)
var power_on := false
var teleporter: Teleporter
## Fenêtres barricadées (marqueurs W).
var barricades: BarricadeSystem
## Objets de l'emplacement de grenade : grenades et PELUCHES LEURRES
## (chemin réseau : /root/Game/Throwables).
var throwables: ThrowableSystem
## Répliques des personnages (chemin réseau : /root/Game/Vox).
var vox: VoxSystem
## Butin des vagues spéciales (chemin réseau : /root/Game/Loot).
var loot: LootSystem
## XP de la partie, comptée par le serveur (chemin réseau : /root/Game/Xp).
var xp: XpSystem
## Porte d'évacuation (null : carte sans porte, aucune évacuation possible).
var evac: EvacDoor
## Station de construction (null : carte sans station, rien à construire).
var station: BuildStation
signal power_changed(on: bool)
## Chargement local terminé (préchauffage fait), juste avant de l'annoncer au
## serveur. Jamais émis si la session s'est terminée pendant le chargement.
signal loaded
## La session s'est terminée (retour au menu en cours).
var _session_over := false
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
	_load_map(Net.current_map if has_map(Net.current_map) else requested_map())
	throwables = ThrowableSystem.new()
	throwables.name = "Throwables"
	add_child(throwables)
	vox = VoxSystem.new()
	vox.name = "Vox"
	add_child(vox)
	loot = LootSystem.new()
	loot.name = "Loot"
	add_child(loot)
	xp = XpSystem.new()
	xp.name = "Xp"
	add_child(xp)
	spectator = SpectatorCamera.new()
	spectator.name = "Spectator"
	spectator.setup(self)
	add_child(spectator)
	Net.player_left.connect(_on_player_left)
	Net.session_ended.connect(_on_session_ended)
	session.inventory_changed.connect(_refresh_remote_weapon)
	if multiplayer.is_server():
		Net.all_loaded.connect(_on_all_loaded)
		combat.player_fell.connect(_on_player_fell)
	Audio.play_music(map_def.music, -6.0, 3.0)
	hud.show_loading(map_def.display_name)
	var warm_at := layout.warm_point()
	var t0 := Time.get_ticks_msec()
	await Warmup.run(self, warm_at)
	# Session terminée pendant le préchauffage (hôte perdu, « Quitter ») : le
	# retour au menu est en cours, rien à annoncer à une session disparue.
	if _session_over or not is_inside_tree() or Net.mode == Net.Mode.NONE:
		print("[Game] chargement abandonné : session terminée")
		return
	print("[Game] préchauffage des shaders : %d ms" % (Time.get_ticks_msec() - t0))
	loaded.emit()
	# Armes de départ et niveau du profil local, avant l'annonce de chargement
	# (même canal fiable : le serveur les a quand il fait apparaître les joueurs).
	session.send_local_loadout()
	Net.report_loaded()


func _load_map(map_id: String) -> void:
	map_def = make_map_def(map_id)
	if map_def == null:
		# Carte perso refusée par le contrôle de légitimité (CustomMapGuard).
		push_warning("[Game] carte « %s » indisponible : %s" % [map_id, DEFAULT_MAP])
		map_def = make_map_def(DEFAULT_MAP)
	layout = map_def.create_layout()
	if layout is GridMapLayout:
		map_data = (layout as GridMapLayout).data
	if multiplayer.is_server():
		layout.create_nav()
		nav = layout.nav
		spawner = Spawner.new(self)
	props = layout.build(world) as MapProps
	WorldLook.setup_environment(world, map_def.look)
	_build_doors()
	_build_power()
	_build_mystery_box()
	_build_teleporter()
	_build_traps()
	_build_barricades()
	_build_evac()
	_build_station()
	if multiplayer.is_server():
		layout.finish_nav(world)
	print("[Game] carte « %s » construite" % map_def.display_name)


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
	var spawns := layout.player_spawns()
	for pid in roster:
		session.create(pid)
		if multiplayer.is_server():
			# Armes de départ choisies au profil et niveau (envoyés par
			# send_local_loadout), puis répliqués par sync_all.
			session.apply_loadout(pid)
	for pid in roster:
		var pos := MatchRules.spawn_for_slot(spawns, int(roster[pid].slot))
		_spawn_player(pid, pos)
	_match_start_ms = Time.get_ticks_msec()
	_match_start_clock = GameClock.now()
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
	p.teleport_to(pos, layout.player_spawn_yaw())
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
	_session_over = true
	print("[Game] session terminée : " + reason)
	# Hôte perdu en cours de partie : l'XP déjà gagnée est gardée (§4.15).
	keep_match_xp()
	Router.back_to_menu(reason)


# --------------------------------------------------------------------------
# Utilitaires
# --------------------------------------------------------------------------

func capture_mouse(on: bool) -> void:
	if Autotest.active:
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


## Menu pause (ou options en jeu) ou panneau d'inventaire ouvert : entrées du
## joueur local ignorées (la partie continue).
func menu_open() -> bool:
	return hud != null and ((hud.pause_menu != null and hud.pause_menu.visible)
		or (hud.inventory != null and hud.inventory.visible)
		or (hud.station_panel != null and hud.station_panel.visible))


func _unhandled_input(event: InputEvent) -> void:
	# Le menu pause est géré par le HUD ; un clic recapture la souris.
	if event is InputEventMouseButton and event.pressed and GameState.is_in_game() \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not menu_open():
		capture_mouse(true)




# --------------------------------------------------------------------------
# Mort des joueurs et fin de partie
# --------------------------------------------------------------------------

const GAME_OVER_DELAY := 9.0
## Début de la partie (dossier de combat : temps de jeu).
var _match_start_ms := 0
## Début de la partie en temps de jeu (durée du résultat de partie).
var _match_start_clock := 0.0


## Serveur : un joueur est tombé à 0 PV : il passe à terre (DOWNED).
func _on_player_fell(pid: int) -> void:
	downed.srv_down(pid)


## Serveur : mort définitive (saignement terminé...). Retour à la manche suivante.
func kill_player(pid: int) -> void:
	var pd := session.get_data(pid)
	if pd == null:
		return
	MatchRules.bleed_out(pd)
	session.sync_stats(pid)
	_cl_player_died.rpc(pid)
	check_game_over()


## Serveur : fin de partie si plus aucun joueur n'est debout.
func check_game_over() -> void:
	if not multiplayer.is_server() or GameState.state == GameState.State.GAME_OVER:
		return
	if not MatchRules.is_game_over(session.data.values(), downed.will_self_revive):
		return
	print("[Game] tous les joueurs sont tombés : GAME OVER")
	srv_end_match(false)


## Serveur : fin de la partie, une des deux issues (§4.6) : évacuation réussie
## (EvacDoor) ou toute l'équipe morte. Le résultat (MatchResult) part en
## données, pas en texte : chaque client l'écrit dans sa langue.
func srv_end_match(evacuated: bool) -> void:
	if not multiplayer.is_server() or GameState.state == GameState.State.GAME_OVER:
		return
	_cl_match_end.rpc(match_result(evacuated).to_dict())


## Résultat de la partie en cours (serveur : manche, durée de jeu, zombies abattus).
func match_result(evacuated: bool) -> MatchResult:
	var r := MatchResult.new()
	r.evacuated = evacuated
	r.round_reached = rounds.round_n
	r.duration_sec = maxf(GameClock.now() - _match_start_clock, 0.0)
	r.kills = game_over_kills()
	# XP de chaque joueur, close (bonus d'évacuation) et envoyée à tous.
	r.xp_ledgers = xp.srv_close_all(evacuated)
	return r


func game_over_kills() -> int:
	return MatchRules.total_kills(session.data.values())


static func game_over_summary(kills: int) -> String:
	return Lang.t("%d zombies abattus", "%d zombies killed") % kills


static func survived_text(rounds_n: int) -> String:
	if rounds_n > 1:
		return Lang.t("VOUS AVEZ SURVÉCU %d MANCHES", "YOU SURVIVED %d ROUNDS") % rounds_n
	return Lang.t("VOUS AVEZ SURVÉCU %d MANCHE", "YOU SURVIVED %d ROUND") % rounds_n


@rpc("authority", "call_local", "reliable")
func _cl_player_died(pid: int) -> void:
	var p: Player = players.get(pid)
	if p:
		p.set_dead(true)
	if pid == multiplayer.get_unique_id():
		hud.show_center(Lang.t("VOUS ÊTES MORT", "YOU ARE DEAD"), "", 0.35)


## Ancien message de fin (toute l'équipe morte, zombies abattus seulement) :
## gardé pour les tests ; le serveur envoie _cl_match_end.
@rpc("authority", "call_local", "reliable")
func _cl_game_over(kills: int) -> void:
	var r := MatchResult.new()
	r.round_reached = rounds.round_n
	r.kills = kills
	r.duration_sec = maxf(GameClock.now() - _match_start_clock, 0.0)
	_show_match_end(r)


@rpc("authority", "call_local", "reliable")
func _cl_match_end(result: Dictionary) -> void:
	_show_match_end(MatchResult.from_dict(result))


## Dernier résultat de partie reçu (null pendant la partie) : rapport de fin,
## plus tard le butin gardé ou perdu (§4.16).
var last_result: MatchResult
## Partie déjà enregistrée (dossier de combat, XP du profil) : une seule fois
## par partie et par client, quelle que soit l'issue.
var _match_recorded := false


## Relevé d'XP du joueur local pour le résultat `r` : celui du serveur
## (MatchResult.xp_ledgers), sinon (ancien message de fin) sa copie locale,
## close ici.
func local_xp_ledger(r: MatchResult) -> Dictionary:
	var me := multiplayer.get_unique_id()
	if r.xp_ledgers.has(me):
		return r.xp_ledgers[me]
	var l := xp.my_ledger.duplicate(true)
	XpRules.close(l, r.evacuated)
	return l


## Ajoute au profil l'XP de la partie du joueur local, UNE seule fois par
## partie (fin de partie, ou départ en cours de partie : keep_match_xp).
## Rend le résultat de MatchXp.apply ({} si déjà fait).
func _record_xp(l: Dictionary) -> Dictionary:
	if _xp_recorded:
		return {}
	_xp_recorded = true
	return MatchXp.apply(l)


var _xp_recorded := false


## Le joueur quitte une partie en cours (menu pause, connexion perdue) :
## l'XP déjà gagnée est gardée (§4.6, §4.15), sans bonus d'évacuation.
func keep_match_xp() -> void:
	if _xp_recorded or xp == null or XpRules.total(xp.my_ledger) <= 0:
		return
	var l := xp.my_ledger.duplicate(true)
	XpRules.close(l, false)
	var res := _record_xp(l)
	print("[Game] partie quittée : %d XP gardée" % int(res.get("xp", 0)))


func _show_match_end(r: MatchResult) -> void:
	if GameState.state != GameState.State.GAME_OVER:
		GameState.set_state(GameState.State.GAME_OVER)
	last_result = r
	if not _match_recorded:
		_match_recorded = true
		var lpd := session.local_data()
		CareerStats.record_game(lpd, r.round_reached, Net.mode == Net.Mode.SOLO,
				(Time.get_ticks_msec() - _match_start_ms) / 1000.0)
		# XP de la partie, comptée par le serveur et toujours gardée
		# (GAME_CONCEPT §4.6) : ajoutée une fois au profil du joueur local.
		r.xp_ledger = local_xp_ledger(r)
		var res := _record_xp(r.xp_ledger)
		if not res.is_empty():
			r.xp = int(res.xp)
			r.level_before = int(res.level_before)
			r.level_after = int(res.level_after)
			r.profile_xp = int(res.total_xp)
			print("[Game] XP de la partie : +%d (niveau %d -> %d)" % [r.xp, r.level_before, r.level_after])
		# Butin de la partie (§4.6, §4.7) : rapporté au profil seulement après
		# une évacuation (versions d'arsenal construites et améliorées mises à
		# jour, §4.11) ; rapport gardé ou perdu dans le résultat.
		var carried := ProfileLoot.carried(lpd, loot.my_parts, loot.my_samples)
		if r.evacuated:
			ProfileLoot.apply_evacuation(carried)
		r.loot = ProfileLoot.report(carried, r.evacuated)
	xp.hide_live()
	print("[Game] fin de partie : %s, manche %d, %s" % ["évacuation" if r.evacuated else "équipe morte",
			r.round_reached, MatchResult.time_text(r.duration_sec)])
	hud.show_match_end(r)
	capture_mouse(false)
	if returns_to_lobby():
		# Multijoueur : le groupe reste ensemble et revient au salon, sur
		# l'ordre du serveur après l'écran de fin (LobbyReturn).
		Router.lobby_message = Lang.t("Dernière partie : %s, %s", "Last game: %s, %s") \
			% [Lang.t("manche %d", "round %d") % r.round_reached,
				(Lang.t("évacuation réussie, ", "evacuated, ") if r.evacuated else "") + r.summary()]
		if multiplayer.is_server():
			get_tree().create_timer(GAME_OVER_DELAY).timeout.connect(_return_to_lobby)
		return
	# Solo, ou test à plusieurs lancé par l'éditeur (retour dans l'éditeur) :
	# fin de la session. Le serveur part en dernier pour que les clients ne
	# voient pas « connexion perdue ».
	var delay := GAME_OVER_DELAY + (0.8 if multiplayer.is_server() else 0.0)
	get_tree().create_timer(delay).timeout.connect(_leave_after_game_over.bind(r))


## Fin de partie suivie d'un retour au salon (multijoueur hors TESTER de
## l'éditeur, qui ramène dans l'éditeur : Router.return_scene).
static func returns_to_lobby() -> bool:
	return Net.is_online() and Router.return_scene == ""


## Serveur : écran de fin terminé, tout le groupe revient au salon.
func _return_to_lobby() -> void:
	if _session_over or not Net.is_online():
		return
	Net.lobby_return.srv_return_all()


func _leave_after_game_over(r: MatchResult) -> void:
	Router.back_to_menu((Lang.t("Évacuation réussie — ", "Evacuated — ") if r.evacuated
			else Lang.t("Partie terminée — ", "Game over — ")) + r.summary())


## Serveur : les joueurs morts reviennent au début de chaque manche, avec
## toutes leurs affaires (MatchRules.respawn, GAME_CONCEPT §4.6).
func respawn_dead_players() -> void:
	var spawns := layout.player_spawns()
	for pid in session.data:
		var pd: PlayerData = session.data[pid]
		if not MatchRules.should_respawn(pd):
			continue
		MatchRules.respawn(pd)
		session.sync_stats(pid)
		session.sync_inventory(pid)
		_cl_respawn.rpc(pid, MatchRules.spawn_for_slot(spawns, Net.player_slot(pid)))


## Point d'apparition d'une place de joueur (règle et repli sans point :
## MatchRules ; alias gardés pour les appelants).
const FALLBACK_SPAWN := MatchRules.FALLBACK_SPAWN


static func spawn_for_slot(spawns: Array[Vector3], slot: int) -> Vector3:
	return MatchRules.spawn_for_slot(spawns, slot)


@rpc("authority", "call_local", "reliable")
func _cl_respawn(pid: int, pos: Vector3) -> void:
	var p: Player = players.get(pid)
	if p == null:
		return
	p.set_dead(false)
	if multiplayer.is_server() and not p.is_local:
		p.net_allow_warp()  # le client réapparaît ailleurs : saut voulu
	if p.is_local:
		p.teleport_to(pos)
		p.reset_eye_height()
		hud.show_center("", "", 0.0)


func _build_doors() -> void:
	var root := Node3D.new()
	root.name = "Doors"
	world.add_child(root)
	for m in layout.doors():
		var d := Door.new()
		d.setup_marker(m)
		root.add_child(d)
		doors[m.id] = d
		interact.register(d)


func _build_power() -> void:
	var m := layout.power_switch()
	if m == null:
		# Carte sans générateur : le courant est là dès le départ.
		props.power.apply_immediate(true)
		set_power(true)
		return
	props.power.apply_immediate(false)
	var sw := PowerSwitch.new()
	sw.setup_marker(m)
	world.add_child(sw)
	interact.register(sw)


func set_power(on: bool) -> void:
	if power_on == on:
		return
	power_on = on
	power_changed.emit(on)


## Caisse au hasard (GAME_CONCEPT §4.12 bis) : UNE seule caisse fixe par
## carte. Plusieurs emplacements déclarés (ancienne carte) : seul celui de
## départ (MapDef.box_start) est gardé, les autres sont ignorés.
func _build_mystery_box() -> void:
	var spots := layout.box_spots()
	if spots.is_empty():
		return
	var i := clampi(map_def.box_start, 0, spots.size() - 1)
	if spots.size() > 1:
		push_warning("[Game] %d emplacements de caisse : seul le n° %d est utilisé (une caisse fixe par carte)" % [spots.size(), i])
	var m: MapMarker = spots[i]
	var root := Node3D.new()
	root.name = "Box"
	world.add_child(root)
	var box := MysteryBox.new()
	box.setup_spot(m)
	interact.register(box)
	root.add_child(box)
	layout.set_blocked(m.block, true)


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
		p.clear_snapshots()
		p.global_position = pos
		if multiplayer.is_server():
			p.net_allow_warp()  # saut voulu par le serveur (Player._srv_accept_state)


func _build_traps() -> void:
	for m in layout.traps():
		var trap := ElectricTrap.new()
		trap.setup_marker(m)
		interact.register(trap)
		world.add_child(trap)
		# Second levier à l'autre bout (Kino der Toten).
		if m.data.has("lever2"):
			var lv := TrapLever.new()
			lv.setup(trap, m.data.lever2)
			interact.register(lv)
			world.add_child(lv)


## Porte d'évacuation (§4.5) : une par carte ; carte sans porte (KINO,
## carte ancienne) : aucune fenêtre d'évacuation, la partie ne finit qu'à la
## mort de l'équipe.
func _build_evac() -> void:
	var m := layout.evac_door()
	if m == null:
		print("[Game] carte sans porte d'évacuation")
		return
	evac = EvacDoor.new()
	evac.setup_marker(m)
	world.add_child(evac)
	interact.register(evac)


## Station de construction (§4.11) : une par carte ; carte sans station
## (carte ancienne) : rien à construire.
func _build_station() -> void:
	var m := layout.build_station()
	if m == null:
		print("[Game] carte sans station de construction")
		return
	station = BuildStation.new()
	station.setup_marker(m)
	world.add_child(station)
	interact.register(station)
	if m.block != "":
		layout.set_blocked(m.block, true)


func _build_barricades() -> void:
	barricades = BarricadeSystem.new()
	barricades.name = "Barricades"
	add_child(barricades)
	barricades.setup(self)


## Arme tenue par un joueur distant (modèle 3e personne).
func _refresh_remote_weapon(pid: int) -> void:
	var p: Player = players.get(pid)
	var pd := session.get_data(pid)
	if p == null or p.is_local or pd == null:
		return
	var w := pd.current_weapon()
	p.visual.set_weapon(w.get("id", ""), w.get("pap", false))


# --------------------------------------------------------------------------
# Spectateur (joueur mort en multijoueur) : SpectatorCamera
# --------------------------------------------------------------------------

## Caméra de spectateur (enfant « Spectator », sans RPC).
var spectator: SpectatorCamera
## Joueur regardé par le joueur local mort (null : sa propre vue).
var spectating: Player:
	get:
		return spectator.spectating if spectator else null
