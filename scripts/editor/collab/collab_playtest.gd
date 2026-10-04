class_name CollabPlaytest
extends Node
## TESTER À PLUSIEURS (docs/MAP_COLLAB.md § 5.3) : l'hôte d'une session
## d'édition appuie sur TESTER, tous les participants jouent ensemble la carte
## éditée, puis reviennent dans l'éditeur, toujours dans la même session.
## - Hôte : ouvre une partie réseau (Net.host, port UDP = celui de la session,
##   ou le suivant s'il est pris), annonce la carte (MapShare : envoyée et
##   vérifiée chez chacun) et prévient les invités par la session
##   (MapCollab.send_playtest). Lance la partie quand tous l'ont rejointe avec
##   la carte (30 s au plus sans progrès de son téléchargement : les
##   retardataires restent dans l'éditeur ; une grosse carte qui arrive
##   encore prolonge l'attente).
## - Invité : rejoint la partie sur l'adresse de l'hôte (Net.join) ; en cas
##   d'échec, il le dit à l'hôte et reste dans l'éditeur.
## - Pendant la partie, ce nœud (sous la racine, hors de la scène) tient la
##   session d'édition (MapCollab) : la connexion entre éditeurs n'est jamais
##   coupée. À la fin (fin de partie, ou départ d'un joueur), l'éditeur qui
##   revient la reprend (MapEditor._setup_collab : take) avec la carte,
##   l'historique et la vue d'avant le test.
## Un seul à la fois (CollabPlaytest.current).

enum Phase { PREPARING, JOINING, PLAYING }

## Attente des invités par l'hôte avant de lancer sans les retardataires
## (comptée depuis le dernier progrès d'un téléchargement de la carte :
## _download_mark).
const WAIT_SEC := 30.0
## Ports essayés pour la partie : celui de la session, puis les suivants.
const PORT_TRIES := 10

static var current: CollabPlaytest

var collab: MapCollab
var phase := Phase.PREPARING
var is_host := false
## Port UDP de la partie de test.
var game_port := 0
## État de l'éditeur à retrouver au retour : {map_dir, example, dirty,
## floor_k, selected, zoom, origin}.
var editor_state: Dictionary = {}
## Hôte : invités de la session qui n'ont pas pu rejoindre (id -> motif).
var failed: Dictionary = {}
## Dernier message de la session pendant la partie (affiché au retour).
var last_message := ""
var last_error := false
## Invité : l'hôte a quitté la partie pendant que la session continuait.
var ended_by_host := false
var _editor: MapEditor
var _t := 0.0
var _status_t := 0.0
## Dernier état des téléchargements de la carte (_download_mark).
var _mark := 0


# ------------------------------------------------------------------ API

## Hôte d'une session, carte écrite dans `map_dir` (copie de travail de
## TESTER, MapUnsaved.test_dir : jamais le dossier de la carte ; déjà vérifiée) :
## ouvre la partie de test et invite les participants. Faux si impossible
## (message dans la barre d'état).
static func host_start(ed: MapEditor, map_dir: String) -> bool:
	if current != null:
		ed.set_status(Lang.t("Test déjà en préparation", "Play test already being prepared"), true)
		return false
	var pt := CollabPlaytest.new()
	pt.is_host = true
	pt._attach(ed)
	var nick := ed.collab.my_name
	var guests := ed.collab.human_guests().size()
	var err := ERR_UNAVAILABLE
	for i in PORT_TRIES:
		var p := ed.collab.port + i
		if not Net.is_valid_port(p):
			break
		err = Net.host(p, mini(guests + 1, Net.MAX_SUPPORTED_PLAYERS), nick)
		if err == OK:
			pt.game_port = p
			break
	if err != OK:
		pt._abort(Lang.t("Test impossible : aucun port libre pour la partie (%d à %d)", "Cannot play test: no free port for the game (%d to %d)")
			% [ed.collab.port, ed.collab.port + PORT_TRIES - 1], false)
		return false
	GameState.set_state(GameState.State.LOBBY)
	var r := Net.set_lobby_map(EditorMapDef.CUSTOM_PREFIX + map_dir.get_file())
	if not r.ok:
		pt._abort(Lang.t("La carte est refusée par le contrôle du jeu :\n%s", "The map is refused by the game's check:\n%s")
			% CustomMapGuard.reasons_text(r.reasons), false)
		return false
	Router.return_scene = MapEditor.SCENE
	CrashGuard.context("éditeur de cartes : TESTER à plusieurs « %s »" % ed.doc.display_name(), true)
	ed.collab.send_playtest(pt.game_port)
	print("[Playtest] partie de test ouverte sur le port %d, %d invité(s) attendu(s)" % [pt.game_port, guests])
	pt._show_wait()
	return true


## Invité : l'hôte a ouvert la partie de test sur `port` : on la rejoint.
static func guest_join(ed: MapEditor, port: int) -> void:
	var addr := ed.collab.host_address()
	if current != null or Net.mode != Net.Mode.NONE or not Net.is_valid_ipv4(addr):
		var why := ["déjà dans une partie", "already in a game"] if Net.is_valid_ipv4(addr) else ["adresse de l'hôte non IPv4", "host address is not IPv4"]
		ed.collab.send_playtest_status(false, why[0], why[1])
		ed.set_status(Lang.t("L'hôte lance un test, impossible de le rejoindre (%s)", "The host started a play test, cannot join it (%s)") % Lang.t(why[0], why[1]), true)
		return
	var pt := CollabPlaytest.new()
	pt.is_host = false
	pt.phase = Phase.JOINING
	pt.game_port = port
	pt._attach(ed)
	Router.return_scene = MapEditor.SCENE
	GameState.set_state(GameState.State.CONNECTING)
	if Net.join(addr, port, ed.collab.my_name) != OK:
		pt._guest_failed(Lang.t("connexion impossible", "cannot connect"), "connexion impossible", "cannot connect")
		return
	CrashGuard.context("éditeur de cartes : TESTER à plusieurs (invité)", true)
	print("[Playtest] connexion à la partie de test %s:%d" % [addr, port])
	ed.set_status(Lang.t("L'hôte lance un test : connexion à la partie…", "The host started a play test: joining the game…"))


## L'éditeur qui (re)vient reprend la session tenue pendant la partie
## (`ed` en devient le parent) ; null s'il n'y a rien à reprendre (pas de
## test, ou test pas encore lancé). Le test est alors terminé.
static func take(ed: MapEditor) -> CollabPlaytest:
	if current == null or current.phase != Phase.PLAYING or current.collab == null:
		return null
	var pt := current
	current = null
	pt._disconnect_all()
	if pt.collab.message.is_connected(pt._on_collab_message):
		pt.collab.message.disconnect(pt._on_collab_message)
	pt.collab.keep_alive = true
	pt.collab.reparent(ed, false)
	pt.collab.keep_alive = false
	pt.queue_free()
	print("[Playtest] retour dans l'éditeur : session d'édition reprise (%s)" % pt.collab.role_name())
	return pt


# ------------------------------------------------------------------ interne

func _attach(ed: MapEditor) -> void:
	name = "CollabPlaytest"
	process_mode = Node.PROCESS_MODE_ALWAYS
	current = self
	_editor = ed
	collab = ed.collab
	ed.get_tree().root.add_child(self)
	ed.tree_exiting.connect(_on_editor_exiting)
	GameState.state_changed.connect(_on_state_changed)
	Net.joined_server.connect(_on_joined)
	Net.connection_error.connect(_on_connection_error)
	Net.session_ended.connect(_on_session_ended)
	collab.playtest_message.connect(_on_playtest_message)
	collab.session_changed.connect(_on_collab_session_changed)


func _process(delta: float) -> void:
	if phase == Phase.PLAYING:
		return
	_t += delta
	# Grosse carte (modèles importés, aucun quota) : tant que son
	# téléchargement avance quelque part, l'attente repart de zéro.
	var mark := _download_mark()
	if mark != _mark:
		_mark = mark
		_t = 0.0
	if is_host:
		_host_wait(delta)
	elif _t > WAIT_SEC + 15.0:
		_guest_failed(Lang.t("la partie n'a pas démarré à temps", "the game did not start in time"), "partie non démarrée à temps", "game did not start in time")


## Avancement des téléchargements de la carte : morceaux reçus ici et
## pourcentages des joueurs qui la téléchargent (états diffusés par l'hôte).
## Change tant qu'une carte arrive quelque part.
func _download_mark() -> int:
	var share: MapShare = Net.map_share
	if share == null:
		return 0
	var m := share.local_received()
	for pid in share.states:
		var st: Dictionary = share.states[pid]
		if String(st.get("etat", "")) == "telechargement":
			m += 1000003 * (int(st.get("pct", 0)) + 1) + int(pid)
	return m


## Hôte : invités de la session encore attendus (ni partis, ni en échec).
func _expected() -> int:
	return collab.human_guests().filter(func(id): return not failed.has(id)).size()


## Hôte : invités de la partie qui ont la carte.
func _ready_guests() -> int:
	var n := 0
	for pid in Net.players:
		if pid != 1 and String(Net.map_share.states.get(pid, {}).get("etat", "")) == "prete":
			n += 1
	return n


func _host_wait(delta: float) -> void:
	if collab.role != MapCollab.Role.HOST:
		_abort(Lang.t("Test annulé : session fermée", "Play test cancelled: session closed"))
		return
	var want := _expected()
	var joined := Net.players.size() - 1
	if want == 0 and joined == 0:
		# Plus personne à attendre : le test se joue seul.
		_launch()
		return
	if joined >= want and _ready_guests() == joined and Net.map_share.can_start()[0]:
		_launch()
		return
	if _t >= WAIT_SEC:
		# Retardataires : coupés de la partie, ils restent dans l'éditeur.
		var peer := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		for pid in Net.players.keys():
			if pid != 1 and String(Net.map_share.states.get(pid, {}).get("etat", "")) != "prete" and peer != null:
				peer.disconnect_peer(pid)
		_launch()
		return
	_status_t -= delta
	if _status_t <= 0.0:
		_show_wait()


func _show_wait() -> void:
	_status_t = 0.5
	if _editor != null and is_instance_valid(_editor):
		_editor.set_status(Lang.t("Test : en attente des participants (%d/%d prêt(s))…", "Play test: waiting for the others (%d/%d ready)…")
			% [_ready_guests(), _expected()])


func _launch() -> void:
	set_process(false)
	# Joueurs coupés à l'instant (retardataires) : retirés avant le lancement.
	for pid in Net.players.keys():
		if pid != 1 and String(Net.map_share.states.get(pid, {}).get("etat", "")) != "prete":
			Net._on_peer_disconnected(pid)
	print("[Playtest] lancement : %d joueur(s)" % Net.players.size())
	if not Net.start_match(Net.lobby_map):
		set_process(true)
		_abort(Lang.t("Test impossible : la partie n'a pas pu démarrer (%s)", "Cannot play test: the game could not start (%s)")
			% String(Net.map_share.can_start()[1]))


## Hôte : test abandonné avant le lancement (les invités sont prévenus).
func _abort(text: String, cancel_guests := true) -> void:
	if cancel_guests and collab != null and collab.role == MapCollab.Role.HOST:
		collab.send_playtest_cancel()
	print("[Playtest] abandon : %s" % text)
	_finish_prep()
	if _editor != null and is_instance_valid(_editor):
		_editor.set_status(text, true)


## Invité : la partie de test n'a pas pu être rejointe.
func _guest_failed(text: String, fr: String, en: String) -> void:
	if collab != null and collab.role == MapCollab.Role.GUEST:
		collab.send_playtest_status(false, fr, en)
	print("[Playtest] test non rejoint : %s (%s)" % [en, text])
	_finish_prep()
	if _editor != null and is_instance_valid(_editor):
		_editor.set_status(Lang.t("Test non rejoint : %s", "Play test not joined: %s") % text, true)


## Fin d'un test qui n'a pas démarré : partie fermée, on reste dans l'éditeur.
func _finish_prep() -> void:
	_disconnect_all()
	Net.leave()
	GameState.reset_to_menu()
	Router.return_scene = ""
	if current == self:
		current = null
	queue_free()


func _disconnect_all() -> void:
	set_process(false)
	for pair in [[GameState.state_changed, _on_state_changed], [Net.joined_server, _on_joined],
			[Net.connection_error, _on_connection_error], [Net.session_ended, _on_session_ended]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])
	if collab != null:
		if collab.playtest_message.is_connected(_on_playtest_message):
			collab.playtest_message.disconnect(_on_playtest_message)
		if collab.session_changed.is_connected(_on_collab_session_changed):
			collab.session_changed.disconnect(_on_collab_session_changed)
	if _editor != null and is_instance_valid(_editor) and _editor.tree_exiting.is_connected(_on_editor_exiting):
		_editor.tree_exiting.disconnect(_on_editor_exiting)


## La partie se charge (_cl_load_game) : la session d'édition quitte la scène
## de l'éditeur (qui va disparaître) pour ce nœud, sans être fermée.
func _on_state_changed(_from: int, to: int) -> void:
	if to != GameState.State.LOADING or phase == Phase.PLAYING:
		return
	phase = Phase.PLAYING
	set_process(false)
	var ed := _editor
	editor_state = ed.playtest_state()
	if ed.tree_exiting.is_connected(_on_editor_exiting):
		ed.tree_exiting.disconnect(_on_editor_exiting)
	_editor = null
	# Plus aucun lien vers l'éditeur qui part (signaux branchés sur lui).
	for s in collab.get_signal_list():
		for c in collab.get_signal_connection_list(s.name):
			var cb: Callable = c.callable
			if cb.get_object() != self:
				collab.disconnect(s.name, cb)
	collab.message.connect(_on_collab_message)
	collab.keep_alive = true
	collab.reparent(self, false)
	collab.keep_alive = false
	print("[Playtest] partie de test : session d'édition gardée (%s, %d participant(s))" % [collab.role_name(), collab.peers.size()])


func _on_editor_exiting() -> void:
	# L'éditeur se ferme avant le lancement (retour au menu, fermeture).
	if phase != Phase.PLAYING:
		if is_host:
			_abort("")
		else:
			_guest_failed("", "éditeur fermé", "editor closed")


func _on_joined() -> void:
	if not is_host and phase == Phase.JOINING:
		GameState.set_state(GameState.State.LOBBY)
		print("[Playtest] partie de test rejointe, attente de la carte")


func _on_connection_error(_title: String, msg: String) -> void:
	if not is_host and phase == Phase.JOINING:
		_guest_failed(msg.replace("\n", " "), "connexion refusée ou impossible", "connection refused or impossible")


func _on_session_ended(_reason: String) -> void:
	if is_host:
		return
	if phase == Phase.JOINING:
		_guest_failed(Lang.t("le test a commencé sans vous (carte pas reçue à temps)", "the test started without you (map not received in time)"),
			"coupé avant le lancement", "dropped before the start")
	elif collab != null and collab.role == MapCollab.Role.GUEST:
		ended_by_host = true


func _on_playtest_message(m: Dictionary) -> void:
	match String(m.get("t", "")):
		"playtest_status":
			if is_host and phase == Phase.PREPARING and not bool(m.ok):
				failed[String(m.peer)] = Lang.t(String(m.reason_fr), String(m.reason_en))
				print("[Playtest] %s ne rejoint pas le test : %s" % [collab.peer_name(String(m.peer)), m.reason_en])
				# Aussi affiché au retour du test (la partie peut démarrer sans lui).
				last_message = Lang.t("%s n'a pas pu rejoindre le test : %s", "%s could not join the play test: %s") \
					% [collab.peer_name(String(m.peer)), failed[String(m.peer)]]
				last_error = true
				if _editor != null and is_instance_valid(_editor):
					_editor.set_status(last_message, true)
					_status_t = 3.0
		"playtest_cancel":
			if not is_host and phase == Phase.JOINING:
				_disconnect_all()
				Net.leave()
				GameState.reset_to_menu()
				Router.return_scene = ""
				current = null
				queue_free()
				if _editor != null and is_instance_valid(_editor):
					_editor.set_status(Lang.t("L'hôte a annulé le test", "The host cancelled the play test"))


func _on_collab_session_changed() -> void:
	if phase == Phase.PLAYING:
		return
	# Session perdue pendant la préparation : test annulé.
	if is_host and collab.role != MapCollab.Role.HOST:
		_abort(Lang.t("Test annulé : session fermée", "Play test cancelled: session closed"), false)
	elif not is_host and collab.role != MapCollab.Role.GUEST:
		_guest_failed(Lang.t("session perdue", "session lost"), "session perdue", "session lost")


func _on_collab_message(text: String, error: bool) -> void:
	last_message = text
	last_error = error


## Message à afficher dans l'éditeur au retour ("" : celui de la partie).
func return_message() -> String:
	if ended_by_host and collab.role == MapCollab.Role.GUEST:
		return Lang.t("Test terminé : l'hôte a quitté la partie", "Play test over: the host left the game")
	return ""


func _exit_tree() -> void:
	if current == self:
		current = null
