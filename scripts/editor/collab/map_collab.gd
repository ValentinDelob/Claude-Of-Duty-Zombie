class_name MapCollab
extends Node
## SESSION DE L'ÉDITEUR COLLABORATIF (docs/MAP_COLLAB.md § 1, 3, 5.1, 8) :
## seul (solo), hôte ou invité, sur un EditorMap. Transport séparé du réseau
## du jeu : TCP, une ligne JSON UTF-8 par message (2 Mo au plus). Sans
## interface : l'éditeur (ou un test, deux sessions dans le même processus)
## lit les signaux.
## - Hôte (et solo, qui est un hôte sans invité) : autorité. Applique les
##   changements dans leur ordre d'arrivée, leur donne un numéro `seq`, les
##   inscrit dans l'historique (MapHistory) et les rediffuse à tous.
## - Invité : applique ses changements tout de suite (attente optimiste) ; à
##   chaque changement reçu, retire ses changements en attente (inverses),
##   applique le reçu, puis les réapplique ; l'écho de son propre `cid` le
##   retire de l'attente. Même ordre que l'hôte, donc mêmes cartes partout.
## - Contrôle : toutes les 5 s l'hôte envoie l'empreinte de la carte ; un
##   invité sans attente qui diffère demande la carte entière (resync).

## La carte a changé du fait de la session (changement d'un autre, annulation,
## agent, rattrapage) : `ops` = état final des éléments touchés (MapOps.state_of
## ou les opérations appliquées), à reporter sur les copies tenues par
## l'éditeur (instantané « avant », glissement en cours). `local` : changement
## venu de cet éditeur (annulation, agent, écho de son propre changement).
signal applied(ops: Array, author: String, label: String, local: bool)
## Changement confirmé (dans l'ordre de l'hôte), déjà inscrit dans l'historique.
signal committed(change: Dictionary)
## Carte entière remplacée (arrivée dans une session, rattrapage).
signal map_replaced
signal peers_changed
signal presence_changed(peer: String)
## Message pour la barre d'état.
signal message(text: String, error: bool)
## Rôle changé (session ouverte, rejointe, quittée, perdue).
signal session_changed
## L'hôte a enregistré la carte.
signal saved(by: String)
## TESTER à plusieurs (CollabPlaytest, docs/MAP_COLLAB.md § 5.3) : message de
## test reçu, déjà contrôlé. Invité : {t: "playtest", port} (l'hôte lance une
## partie de test, à rejoindre sur son adresse et ce port UDP) ou {t:
## "playtest_cancel"} ; hôte : {t: "playtest_status", peer, ok, reason_fr,
## reason_en} (un invité n'a pas pu rejoindre).
signal playtest_message(m: Dictionary)

enum Role { SOLO, HOST, GUEST }

## 2 : messages du TESTER à plusieurs (§ 5.3) ; un éditeur de la v1 est
## refusé à l'arrivée (« version de l'éditeur différente ») au lieu de quitter
## la session au premier test.
const PROTO := 2
const DEFAULT_PORT := 7790
const MAX_LINE := MapOps.MAX_BYTES
const MAX_HUMANS := 8
## Connexions TCP ouvertes au plus chez l'hôte (poignées de main comprises).
const MAX_CONNS := 16
const CHANGE_RATE := 30.0
const PRESENCE_RATE := 20.0
const HANDSHAKE_SEC := 5.0
const SUM_EVERY := 5.0
const MAX_BAD_CODES := 5
## Présence envoyée au plus 10 fois par seconde.
const PRESENCE_EVERY := 0.1
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const COLORS := ["#e8b04a", "#4aa8e8", "#7be84a", "#e84a8c", "#4ae8d0", "#e8784a", "#e8e04a", "#8ca0ff"]
const AGENT_COLOR := "#a066ff"

var doc: EditorMap
var history := MapHistory.new()
var role := Role.SOLO
var my_id := "1"
var my_name := "Claude"
## Code de session (hôte) : 6 caractères à donner aux invités.
var session_code := ""
var port := 0
var seq := 0
## id -> {id, name, color, kind ("human" / "agent"), presence: {}}
var peers: Dictionary = {}
## Invité : changements appliqués ici, pas encore confirmés par l'hôte :
## [{change, inverse}], dans l'ordre d'envoi.
var pending: Array = []
## Un Claude (MapAgentLink) est rattaché à cet éditeur.
var agent_on := false

var _server: TCPServer
## Hôte : connexions des invités ; invité : [connexion à l'hôte].
var _conns: Array = []
var _next_peer := 2
var _cid_n := 0
var _bad_codes: Dictionary = {}
var _sum_t := 0.0
## Invité : annulations demandées pendant une attente (faites après l'écho).
var _queued: Array = []
var _presence_out: Dictionary = {}
var _presence_dirty := false
var _presence_t := 0.0
var _joining := false
var _join_code := ""
## Session gardée quand le nœud change de parent (partie de TESTER à
## plusieurs : CollabPlaytest la tient pendant la partie) ; sinon, sortir de
## l'arbre quitte la session.
var keep_alive := false


class Conn:
	var tcp: StreamPeerTCP
	var buf := PackedByteArray()
	var id := ""
	var ip := ""
	var age := 0.0
	var ok := false
	var hello_sent := false
	var change_tokens := MapCollab.CHANGE_RATE * 2.0
	var presence_tokens := MapCollab.PRESENCE_RATE
	var need_map := false
	var map_t := 0.0
	var closed := false


func _init(map: EditorMap = null) -> void:
	doc = map if map != null else EditorMap.blank()
	_reset_peers()


func _exit_tree() -> void:
	if not keep_alive:
		leave()


# ------------------------------------------------------------------ état

func is_session() -> bool:
	return role != Role.SOLO


func role_name() -> String:
	return ["solo", "host", "guest"][role]


## Participants pour l'affichage et le protocole : [{id, name, color, kind}].
func peer_list() -> Array:
	var out := []
	for id in peers:
		var p: Dictionary = peers[id]
		out.append({"id": id, "name": p.name, "color": p.color, "kind": p.kind})
	return out


func peer_name(id: String) -> String:
	if peers.has(id):
		return String(peers[id].name)
	if MapHistory.is_agent(id):
		return Lang.t("Claude (%s)", "Claude (%s)") % peer_name(MapHistory.root_of(id))
	return id


func _reset_peers() -> void:
	peers = {my_id: {"id": my_id, "name": my_name, "color": COLORS[0], "kind": "human", "presence": {}}}
	if agent_on:
		_add_agent_peer(my_id)


func _add_agent_peer(owner: String) -> void:
	var nm := "Claude"
	if owner != my_id and peers.has(owner):
		nm = "Claude (%s)" % peers[owner].name
	peers[owner + ":claude"] = {"id": owner + ":claude", "name": nm, "color": AGENT_COLOR, "kind": "agent", "presence": {}}


## Nouvelle carte ouverte ici (Nouvelle, Ouvrir, Importer) : historique vidé ;
## un hôte l'envoie à ses invités ; un invité quitte la session (la carte de
## la session reste celle de l'hôte).
func reset_doc(map: EditorMap) -> void:
	if role == Role.GUEST:
		leave()
		message.emit(Lang.t("Session quittée : une autre carte a été ouverte", "Session left: another map was opened"), false)
	doc = map
	history.clear()
	pending.clear()
	if role == Role.HOST:
		seq += 1
		_broadcast({"t": "map", "map": doc.snapshot(), "seq": seq, "reset": true})


## Hôte : la carte entière renvoyée aux invités, même numéro, historique
## gardé (format 10 : bibliothèque des prefabs de la carte changée, qui ne
## passe pas par les opérations). Rien pour un invité ou en solo.
func broadcast_map() -> void:
	if role == Role.HOST:
		_broadcast({"t": "map", "map": doc.snapshot(), "seq": seq})


func _new_cid() -> String:
	_cid_n += 1
	return "%s-%d-%d" % [my_id, Time.get_ticks_msec() % 100000, _cid_n]


# ------------------------------------------------------------------ changements locaux

## Changement fait par l'éditeur (déjà appliqué à la carte) : `before` est la
## carte d'avant (instantané), pour l'inverse. Rend le changement.
func submit_local(ops: Array, label: String, before: Dictionary) -> Dictionary:
	var change := {"cid": _new_cid(), "author": my_id, "label": label, "ops": ops}
	var inv := MapOps.inverse(before, ops)
	if role == Role.GUEST:
		pending.append({"change": change, "inverse": inv})
		_send_host({"t": "change", "cid": change.cid, "label": label, "ops": ops})
		return change
	_record_and_broadcast(change, inv)
	return change


## Changement pas encore appliqué (agent, annulation) : appliqué ici, inscrit
## (hôte) ou mis en attente (invité). `author` : my_id ou « my_id:claude ».
func submit_ops(ops: Array, label: String, author := "", extra := {}) -> Dictionary:
	var change := {"cid": _new_cid(), "author": author if author != "" else my_id, "label": label, "ops": ops}
	change.merge(extra)
	if role == Role.GUEST:
		var inv := MapOps.inverse(doc, ops)
		MapOps.apply(doc, ops)
		pending.append({"change": change, "inverse": inv})
		var msg := {"t": "change", "cid": change.cid, "label": label, "ops": ops}
		if change.author != my_id:
			msg["author"] = change.author
		for k in ["undo", "redo"]:
			if change.has(k):
				msg[k] = change[k]
		_send_host(msg)
		applied.emit(ops, change.author, label, true)
		return change
	_commit(change, true)
	return change


## Hôte / solo : applique, inscrit, diffuse.
func _commit(change: Dictionary, local: bool) -> void:
	var ops: Array = change.ops
	var inv := MapOps.inverse(doc, ops)
	MapOps.apply(doc, ops)
	_record_and_broadcast(change, inv)
	applied.emit(ops, String(change.author), String(change.label), local)


func _record_and_broadcast(change: Dictionary, inv: Array) -> void:
	seq += 1
	change["seq"] = seq
	history.record(change, inv)
	var msg := change.duplicate()
	msg["t"] = "change"
	_broadcast(msg)
	committed.emit(change)


## Ctrl+Z : annule la dernière entrée de cet éditeur ou de son Claude
## (`agent_only` : seulement celle de son Claude). Rend {} si rien, {queued}
## si l'invité attend encore un écho (faite juste après), sinon
## {undo, label, ops, skipped, skipped_by, cid}.
func request_undo(agent_only := false) -> Dictionary:
	if role == Role.GUEST and not pending.is_empty():
		_queued.append(["undo", agent_only])
		return {"queued": true}
	var u := history.make_undo(my_id, agent_only)
	if u.is_empty():
		return {}
	var c := submit_ops(u.ops, u.label, my_id + (":claude" if agent_only else ""), {"undo": u.undo})
	u["cid"] = c.cid
	return u


## Ctrl+Y : rétablit la dernière entrée annulée par cet éditeur.
func request_redo() -> Dictionary:
	if role == Role.GUEST and not pending.is_empty():
		_queued.append(["redo", false])
		return {"queued": true}
	var r := history.make_redo(my_id)
	if r.is_empty():
		return {}
	var c := submit_ops(r.ops, r.label, my_id, {"redo": r.redo})
	r["cid"] = c.cid
	return r


## Annule l'entrée `cid` (bouton « Annuler cette action » du panneau
## Historique) si elle est à cet éditeur ou à son Claude et encore active.
## Rend {} si impossible, {queued} si l'invité attend encore un écho, sinon
## {undo, label, ops, skipped, skipped_by, cid}.
func request_undo_of(cid: String) -> Dictionary:
	var e := history.entry(cid)
	if not history.owned_by(cid, my_id) or not bool(e.get("active", false)) or bool(e.get("remote", false)):
		return {}
	if role == Role.GUEST and not pending.is_empty():
		_queued.append(["undo_of", cid])
		return {"queued": true}
	var u := history.make_undo_of(cid)
	if u.is_empty():
		return {}
	var c := submit_ops(u.ops, u.label, my_id, {"undo": u.undo})
	u["cid"] = c.cid
	return u


func _run_queued() -> void:
	while pending.is_empty() and not _queued.is_empty():
		var q: Array = _queued.pop_front()
		var r := {}
		match String(q[0]):
			"undo":
				r = request_undo(bool(q[1]))
			"undo_of":
				r = request_undo_of(String(q[1]))
			_:
				r = request_redo()
		if not r.is_empty():
			message.emit(String(r.label), false)


## Texte du conflit d'une annulation (« 2 élément(s) modifié(s) entre-temps
## par Bob : non annulé(s) ») ; "" sans conflit.
func conflict_text(r: Dictionary) -> String:
	if int(r.get("skipped", 0)) <= 0:
		return ""
	var names := (r.get("skipped_by", []) as Array).map(func(a): return peer_name(String(a)))
	return Lang.t("%d élément(s) modifié(s) entre-temps par %s : non annulé(s)", "%d element(s) changed meanwhile by %s: not undone") % [
		int(r.skipped), ", ".join(names)]


## Présence de cet éditeur (curseur [x, y] en mètres, étage, sélection,
## outil, aperçu `live` facultatif) : envoyée au plus 10 fois par seconde.
func set_presence(p: Dictionary) -> void:
	_presence_out = p
	_presence_dirty = true


## Un Claude se rattache à cet éditeur (ou s'en va) : pastille dans la liste.
func set_agent(on: bool) -> void:
	if agent_on == on:
		return
	agent_on = on
	if role == Role.GUEST:
		var p := _presence_out.duplicate()
		p["t"] = "presence"
		p["agent"] = on
		_send_host(p)
		return
	if on:
		_add_agent_peer(my_id)
	else:
		peers.erase(my_id + ":claude")
	_broadcast_peers()


## L'hôte a enregistré la carte : les invités sont prévenus.
func notify_saved() -> void:
	if role == Role.HOST:
		_broadcast({"t": "saved", "by": my_name, "time": int(Time.get_unix_time_from_system())})


## Invités humains de la session (ids), sans soi-même ni les Claude.
func human_guests() -> Array:
	return peers.keys().filter(func(id): return id != my_id and String(peers[id].kind) == "human")


## Invité : adresse IP de l'hôte (celle de la connexion) ; "" hors session.
func host_address() -> String:
	if role != Role.GUEST or _conns.is_empty():
		return ""
	var c: Conn = _conns[0]
	var a := c.tcp.get_connected_host() if c.tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED else ""
	return a if a != "" else c.ip


## Hôte : la partie de TESTER est ouverte sur `game_port` (UDP) : les invités
## la rejoignent (§ 5.3).
func send_playtest(game_port: int) -> void:
	_broadcast({"t": "playtest", "port": game_port})


## Hôte : test abandonné avant le lancement (les invités quittent la partie).
func send_playtest_cancel() -> void:
	_broadcast({"t": "playtest_cancel"})


## Invité : n'a pas pu rejoindre la partie de test (motif en deux langues).
func send_playtest_status(ok: bool, fr := "", en := "") -> void:
	_send_host({"t": "playtest_status", "ok": ok, "reason_fr": fr.left(160), "reason_en": en.left(160)})


# ------------------------------------------------------------------ hôte

## Ouvre la session sur `p` (toutes les interfaces) : code de session tiré au
## hasard. L'historique et la carte en cours sont gardés (l'hôte est l'id 1).
func host(p: int, nickname: String) -> Error:
	leave()
	var srv := TCPServer.new()
	var err := srv.listen(p, "*")
	if err != OK:
		return err
	_server = srv
	port = p
	role = Role.HOST
	_rename_me("1", nickname)
	session_code = make_code()
	_bad_codes.clear()
	_next_peer = 2
	_reset_peers()
	session_changed.emit()
	peers_changed.emit()
	return OK


static func make_code() -> String:
	var b := Crypto.new().generate_random_bytes(6)
	var s := ""
	for i in 6:
		s += CODE_CHARS[b[i] % CODE_CHARS.length()]
	return s


func _rename_me(id: String, nickname: String) -> void:
	if id != my_id:
		my_id = id
	my_name = clean_name(nickname)


static func clean_name(n: String) -> String:
	var out := ""
	for i in mini(n.length(), 64):
		var c := n.unicode_at(i)
		if c < 0x20 or c == 0x7F or (c >= 0x200B and c <= 0x200F) or (c >= 0x202A and c <= 0x202E) or (c >= 0x2066 and c <= 0x2069) or c in [0x5B, 0x5D, 0x3C, 0x3E]:
			continue
		out += n[i]
	out = out.strip_edges().left(20)
	return out if out != "" else "Survivant"


func _host_process(delta: float) -> void:
	while _server != null and _server.is_connection_available():
		var tcp := _server.take_connection()
		if _conns.size() >= MAX_CONNS:
			tcp.disconnect_from_host()
			continue
		var c := Conn.new()
		c.tcp = tcp
		c.ip = tcp.get_connected_host()
		_conns.append(c)
	for c: Conn in _conns.duplicate():
		c.age += delta
		c.change_tokens = minf(c.change_tokens + CHANGE_RATE * delta, CHANGE_RATE * 2.0)
		c.presence_tokens = minf(c.presence_tokens + PRESENCE_RATE * delta, PRESENCE_RATE)
		c.map_t -= delta
		if not c.ok and c.age > HANDSHAKE_SEC:
			_reject(c, "délai de connexion dépassé", "connection timed out")
			continue
		for m in _read(c):
			if c.closed:
				break
			if m == null:
				_kick(c)
				break
			_host_handle(c, m)
		if c.closed:
			continue
		if c.tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_drop(c)
			continue
		if c.need_map and c.map_t <= 0.0:
			c.need_map = false
			c.map_t = 1.0
			_send(c, {"t": "map", "map": doc.snapshot(), "seq": seq})
	_sum_t += delta
	if _sum_t >= SUM_EVERY:
		_sum_t = 0.0
		if _conns.any(func(x): return x.ok):
			_broadcast({"t": "sum", "seq": seq, "hash": MapOps.hash_of(doc)})


func _host_handle(c: Conn, m: Dictionary) -> void:
	var t := String(m.get("t", ""))
	if not c.ok:
		if t != "hello":
			_kick(c)
			return
		if int(_bad_codes.get(c.ip, 0)) >= MAX_BAD_CODES:
			_reject(c, "trop d'essais avec un code faux", "too many tries with a wrong code")
			return
		if not ((m.get("proto") is float or m.get("proto") is int) and int(m.proto) == PROTO):
			_reject(c, "version de l'éditeur différente", "different editor version")
			return
		if not (m.get("code") is String and String(m.code).strip_edges().to_upper() == session_code):
			_bad_codes[c.ip] = int(_bad_codes.get(c.ip, 0)) + 1
			_reject(c, "code de session faux", "wrong session code")
			return
		if peers.values().filter(func(p): return p.kind == "human").size() >= MAX_HUMANS:
			_reject(c, "session pleine (%d personnes)" % MAX_HUMANS, "session full (%d people)" % MAX_HUMANS)
			return
		var id := str(_next_peer)
		_next_peer += 1
		c.id = id
		c.ok = true
		var nm := clean_name(String(m.name) if m.get("name") is String else "")
		peers[id] = {"id": id, "name": nm, "color": COLORS[(int(id) - 1) % COLORS.size()], "kind": "human", "presence": {}}
		_send(c, {"t": "welcome", "you": id, "peers": peer_list(), "map": doc.snapshot(), "seq": seq, "history": history.export_light()})
		_broadcast_peers(c)
		message.emit(Lang.t("%s a rejoint la session", "%s joined the session") % nm, false)
		return
	match t:
		"change":
			_host_change(c, m)
		"presence":
			if c.presence_tokens < 1.0:
				return
			c.presence_tokens -= 1.0
			var p := clean_presence(m)
			if p.is_empty():
				_kick(c)
				return
			if m.has("agent"):
				if bool(m.agent) and not peers.has(c.id + ":claude"):
					_add_agent_peer(c.id)
					_broadcast_peers()
				elif not bool(m.agent) and peers.has(c.id + ":claude"):
					peers.erase(c.id + ":claude")
					_broadcast_peers()
			peers[c.id].presence = p
			presence_changed.emit(c.id)
			var out := p.duplicate()
			out["t"] = "presence"
			out["peer"] = c.id
			_broadcast(out, c)
		"resync":
			c.need_map = true
		"playtest_status":
			if not m.get("ok") is bool:
				_kick(c)
				return
			playtest_message.emit({"t": "playtest_status", "peer": c.id, "ok": m.ok,
				"reason_fr": _reason_text(m, "reason_fr"), "reason_en": _reason_text(m, "reason_en")})
		"ping":
			pass
		"bye":
			_drop(c)
		_:
			_kick(c)


func _host_change(c: Conn, m: Dictionary) -> void:
	var cid: Variant = m.get("cid")
	if not (cid is String and String(cid) != "" and String(cid).length() <= 64):
		_kick(c)
		return
	var author := c.id
	if m.has("author"):
		if m.author != c.id + ":claude":
			_kick(c)
			return
		author = String(m.author)
	var err := MapOps.validate(m.get("ops"))
	if err != "":
		push_warning("[MapCollab] changement refusé de %s : %s" % [c.id, err])
		_kick(c)
		return
	if c.change_tokens < 1.0:
		# Trop de changements : ignoré, l'invité reçoit la carte entière.
		c.need_map = true
		return
	c.change_tokens -= 1.0
	var ops: Array = m.ops
	MapOps.normalize(ops)
	var change := {"cid": cid, "author": author, "label": (String(m.label) if m.get("label") is String else "").left(120)}
	if m.get("undo") is String or m.get("redo") is String:
		# Annulation : l'hôte recalcule les opérations avec SON historique.
		var target := String(m.get("undo", m.get("redo", "")))
		var r := {}
		if history.owned_by(target, c.id):
			r = history.make_undo_of(target) if m.has("undo") else history.make_redo_of(target)
		if r.is_empty():
			ops = []
		else:
			ops = r.ops
			change["label"] = r.label
			change["undo" if m.has("undo") else "redo"] = target
			change["skipped"] = r.skipped
			change["skipped_by"] = r.skipped_by
	else:
		var chk := MapOps.check_elements(doc, ops)
		if not chk.invalid.is_empty():
			push_warning("[MapCollab] éléments refusés de %s : %s" % [c.id, str(chk.invalid)])
		ops = host_only_guard(doc, chk.ops)
	change["ops"] = ops
	_commit(change, false)


## Ouvrir ou enregistrer la carte est l'affaire de l'hôte : un invité n'envoie
## que des changements d'éléments (« change ») ; tout autre message (carte
## entière « map », « saved »...) le déconnecte (_host_handle). Dans un
## « carte » venu d'un invité, l'identifiant de la carte (nom de son dossier
## à l'enregistrement) reste celui de l'hôte.
static func host_only_guard(host_doc: Variant, ops: Array) -> Array:
	var cur: Dictionary = MapOps._carte(host_doc)
	for op in ops:
		if String(op.get("op", "")) == "carte" and op.get("carte") is Dictionary:
			var cd: Dictionary = op.carte
			if cur.has("id"):
				cd["id"] = cur.id
			else:
				cd.erase("id")
	return ops


func _broadcast(msg: Dictionary, except: Conn = null) -> void:
	if role != Role.HOST:
		return
	var line := _line(msg)
	if line.is_empty():
		return
	for c in _conns:
		if c.ok and c != except and not c.closed:
			c.tcp.put_data(line)


func _broadcast_peers(except: Conn = null) -> void:
	_broadcast({"t": "peers", "peers": peer_list()}, except)
	peers_changed.emit()


func _reject(c: Conn, fr: String, en: String) -> void:
	_send(c, {"t": "reject", "reason_fr": fr, "reason_en": en})
	_close(c)


## Message invalide : déconnexion du pair (§ 8).
func _kick(c: Conn) -> void:
	_send(c, {"t": "bye", "reason_fr": "message invalide", "reason_en": "invalid message"})
	push_warning("[MapCollab] pair %s (%s) déconnecté : message invalide" % [c.id, c.ip])
	_drop(c)


func _drop(c: Conn) -> void:
	var was := c.ok
	_close(c)
	if was and peers.has(c.id):
		var nm := String(peers[c.id].name)
		peers.erase(c.id)
		peers.erase(c.id + ":claude")
		_broadcast_peers()
		message.emit(Lang.t("%s a quitté la session", "%s left the session") % nm, false)


func _close(c: Conn) -> void:
	c.closed = true
	c.tcp.disconnect_from_host()
	_conns.erase(c)


# ------------------------------------------------------------------ invité

## Rejoint la session de `address`:`p` avec le code de session : la carte de
## l'hôte remplace celle d'ici à l'arrivée (signal map_replaced).
func join(address: String, p: int, code: String, nickname: String) -> Error:
	leave()
	var tcp := StreamPeerTCP.new()
	var err := tcp.connect_to_host(address.strip_edges(), p)
	if err != OK:
		return err
	var c := Conn.new()
	c.tcp = tcp
	c.ip = address
	_conns = [c]
	role = Role.GUEST
	port = p
	_joining = true
	_join_code = code
	my_name = clean_name(nickname)
	session_changed.emit()
	return OK


func _send_host(msg: Dictionary) -> void:
	if role == Role.GUEST and not _conns.is_empty() and not _joining:
		_send(_conns[0], msg)


func _guest_process(delta: float) -> void:
	if _conns.is_empty():
		return
	var c: Conn = _conns[0]
	c.age += delta
	c.tcp.poll()
	var st := c.tcp.get_status()
	if st == StreamPeerTCP.STATUS_CONNECTING:
		if c.age > HANDSHAKE_SEC:
			_lost(Lang.t("Connexion impossible : pas de réponse de l'hôte", "Cannot connect: no answer from the host"))
		return
	if st != StreamPeerTCP.STATUS_CONNECTED:
		_lost(Lang.t("Connexion impossible", "Cannot connect") if _joining else Lang.t("Connexion à l'hôte perdue", "Connection to the host lost"))
		return
	if not c.hello_sent:
		c.hello_sent = true
		c.age = 0.0
		_send(c, {"t": "hello", "proto": PROTO, "name": my_name, "code": _join_code,
			"app_version": String(ProjectSettings.get_setting("application/config/version", ""))})
	if _joining and c.age > HANDSHAKE_SEC:
		_lost(Lang.t("Connexion impossible : l'hôte ne répond pas", "Cannot connect: the host does not answer"))
		return
	for m in _read(c):
		if role != Role.GUEST:
			return
		if m == null:
			_lost(Lang.t("Message invalide de l'hôte : session quittée", "Invalid message from the host: session left"))
			return
		_guest_handle(m)


func _guest_handle(m: Dictionary) -> void:
	var t := String(m.get("t", ""))
	if _joining:
		if t == "welcome" and m.get("you") is String and m.get("map") is Dictionary and MapOps.value_ok(m.map, -3) \
				and (m.get("seq") is float or m.get("seq") is int) and m.get("peers") is Array:
			_joining = false
			my_id = String(m.you).left(32)
			_set_map(m.map)
			seq = int(m.seq)
			history.import_light(m.history if m.get("history") is Dictionary else {})
			_set_peers(m.peers)
			pending.clear()
			map_replaced.emit()
			session_changed.emit()
			peers_changed.emit()
			message.emit(Lang.t("Session rejointe : %d participant(s)", "Session joined: %d participant(s)") % peers.size(), false)
			if agent_on:
				_send_host({"t": "presence", "agent": true})
		elif t == "reject":
			_lost(Lang.t("Refusé par l'hôte : %s", "Refused by the host: %s") % _reason(m))
		else:
			_lost(Lang.t("Réponse invalide de l'hôte", "Invalid answer from the host"))
		return
	match t:
		"change":
			_guest_change(m)
		"presence":
			var id: Variant = m.get("peer")
			if id is String and peers.has(id) and id != my_id:
				var p := clean_presence(m)
				if not p.is_empty():
					peers[id].presence = p
					presence_changed.emit(String(id))
		"peers":
			if m.get("peers") is Array:
				_set_peers(m.peers)
				peers_changed.emit()
		"sum":
			if pending.is_empty() and (m.get("seq") is float or m.get("seq") is int) and int(m.seq) == seq \
					and m.get("hash") is String and MapOps.hash_of(doc) != String(m.hash):
				push_warning("[MapCollab] carte différente de celle de l'hôte (seq %d) : rattrapage" % seq)
				_send_host({"t": "resync"})
		"map":
			if m.get("map") is Dictionary and MapOps.value_ok(m.map, -3) and (m.get("seq") is float or m.get("seq") is int):
				_set_map(m.map)
				seq = int(m.seq)
				pending.clear()
				_queued.clear()
				if m.get("reset", false):
					history.clear()
				map_replaced.emit()
		"saved":
			saved.emit(clean_name(String(m.get("by", ""))))
		"playtest":
			var gp: Variant = m.get("port")
			if not ((gp is float or gp is int) and float(gp) == floorf(float(gp)) and Net.is_valid_port(int(gp))):
				_lost(Lang.t("Message invalide de l'hôte : session quittée", "Invalid message from the host: session left"))
				return
			playtest_message.emit({"t": "playtest", "port": int(gp)})
		"playtest_cancel":
			playtest_message.emit({"t": "playtest_cancel"})
		"bye":
			_lost(Lang.t("Session terminée par l'hôte (%s)", "Session ended by the host (%s)") % _reason(m))
		"ping", "pong":
			pass
		_:
			_lost(Lang.t("Message invalide de l'hôte : session quittée", "Invalid message from the host: session left"))


func _guest_change(m: Dictionary) -> void:
	if not ((m.get("seq") is float or m.get("seq") is int) and m.get("cid") is String and m.get("author") is String) \
			or MapOps.validate(m.get("ops")) != "":
		_lost(Lang.t("Message invalide de l'hôte : session quittée", "Invalid message from the host: session left"))
		return
	if int(m.seq) != seq + 1:
		# Trou dans la suite : la carte entière sera renvoyée.
		_send_host({"t": "resync"})
		return
	var ops: Array = m.ops
	MapOps.normalize(ops)
	var change := {"cid": String(m.cid), "author": String(m.author).left(40), "label": String(m.get("label", "")).left(120),
		"ops": ops, "seq": int(m.seq)}
	for k in ["undo", "redo"]:
		if m.get(k) is String:
			change[k] = m[k]
	for k in ["skipped"]:
		if m.get(k) is float or m.get(k) is int:
			change[k] = int(m[k])
	if m.get("skipped_by") is Array:
		change["skipped_by"] = (m.skipped_by as Array).filter(func(x): return x is String)
	# Attente retirée (inverses, de la plus récente à la plus ancienne).
	var keys := MapOps.touched(ops)
	for i in range(pending.size() - 1, -1, -1):
		MapOps.apply(doc, pending[i].inverse)
		keys.append_array(MapOps.touched(pending[i].change.ops))
	if not change.has("undo") and not change.has("redo"):
		change.ops = MapOps.check_elements(doc, ops).ops
	var inv := MapOps.inverse(doc, change.ops)
	MapOps.apply(doc, change.ops)
	history.record(change, inv)
	seq = int(m.seq)
	var own: bool = not pending.is_empty() and String(pending[0].change.cid) == change.cid
	if own:
		pending.pop_front()
	# Attente réappliquée par-dessus.
	for p in pending:
		p.inverse = MapOps.inverse(doc, p.change.ops)
		MapOps.apply(doc, p.change.ops)
	committed.emit(change)
	applied.emit(MapOps.state_of(doc, keys), change.author, change.label, own)
	_run_queued()


func _set_map(map: Dictionary) -> void:
	doc.restore(map)
	for coll in ["pieces", "ouvertures", "objets", "zones"]:
		var l: Array = MapOps.list(doc, coll)
		for i in range(l.size() - 1, -1, -1):
			if not l[i] is Dictionary:
				l.remove_at(i)
				continue
			l[i]["id"] = str(l[i].get("id", ""))
			if coll != "zones":
				l[i]["etage"] = int(l[i].get("etage", 0)) if (l[i].get("etage") is float or l[i].get("etage") is int) else 0


func _set_peers(list: Array) -> void:
	var old := peers
	peers = {}
	for p in list.slice(0, MAX_HUMANS * 2 + 2):
		if not (p is Dictionary and p.get("id") is String):
			continue
		var id := String(p.id).left(40)
		var col := String(p.get("color", COLORS[0]))
		if not Color.html_is_valid(col):
			col = COLORS[0]
		peers[id] = {"id": id, "name": clean_name(String(p.get("name", ""))), "color": col,
			"kind": "agent" if p.get("kind") == "agent" else "human", "presence": old[id].presence if old.has(id) else {}}
	if not peers.has(my_id):
		peers[my_id] = {"id": my_id, "name": my_name, "color": COLORS[0], "kind": "human", "presence": {}}


func _lost(text: String) -> void:
	var was_joining := _joining
	_to_solo()
	message.emit(text, true)
	if not was_joining:
		push_warning("[MapCollab] " + text)


static func _reason(m: Dictionary) -> String:
	return clean_name(Lang.t(String(m.get("reason_fr", "")), String(m.get("reason_en", ""))).left(80))


## Motif reçu (`key`), borné : texte d'une ligne, 160 caractères au plus.
static func _reason_text(m: Dictionary, key: String) -> String:
	var v: Variant = m.get(key, "")
	if not v is String:
		return ""
	var s: String = v
	var out := ""
	for i in mini(s.length(), 160):
		var c := s.unicode_at(i)
		if c >= 0x20 and c != 0x7F and not (c >= 0x200B and c <= 0x200F) and not (c >= 0x202A and c <= 0x202E) and not (c >= 0x2066 and c <= 0x2069):
			out += s[i]
	return out.strip_edges()


# ------------------------------------------------------------------ commun

## Quitte la session (l'hôte prévient ses invités) ; la carte reste ici, en solo.
func leave() -> void:
	if role == Role.HOST:
		_broadcast({"t": "bye", "reason_fr": "l'hôte a fermé la session", "reason_en": "the host closed the session"})
	elif role == Role.GUEST and not _joining:
		_send_host({"t": "bye"})
	if role != Role.SOLO:
		_to_solo()


func _to_solo() -> void:
	for c: Conn in _conns.duplicate():
		_close(c)
	_conns.clear()
	if _server != null:
		_server.stop()
		_server = null
	var was := role
	role = Role.SOLO
	_joining = false
	session_code = ""
	pending.clear()
	_queued.clear()
	_reset_peers()
	if was != Role.SOLO:
		session_changed.emit()
		peers_changed.emit()


func _process(delta: float) -> void:
	if role == Role.HOST:
		_host_process(delta)
	elif role == Role.GUEST:
		_guest_process(delta)
	_presence_t -= delta
	if _presence_dirty and _presence_t <= 0.0 and role != Role.SOLO and not _joining:
		_presence_dirty = false
		_presence_t = PRESENCE_EVERY
		var p := clean_presence(_presence_out)
		if p.is_empty():
			return
		p["t"] = "presence"
		if role == Role.HOST:
			peers[my_id].presence = p
			var out := p.duplicate()
			out["peer"] = my_id
			_broadcast(out)
		else:
			if agent_on:
				p["agent"] = true
			_send_host(p)


## Présence reçue, bornée : {cursor: [x, y], floor, selection: [ids], tool,
## live?, agent?} ; {} si elle est invalide.
static func clean_presence(m: Dictionary) -> Dictionary:
	var out := {}
	var cur: Variant = m.get("cursor", [0.0, 0.0])
	if not (cur is Array and cur.size() == 2 and (cur[0] is float or cur[0] is int) and (cur[1] is float or cur[1] is int)
			and is_finite(float(cur[0])) and is_finite(float(cur[1]))):
		return {}
	out["cursor"] = [clampf(float(cur[0]), -1000.0, 1000.0), clampf(float(cur[1]), -1000.0, 1000.0)]
	var fl: Variant = m.get("floor", 0)
	out["floor"] = clampi(int(fl), 0, CustomMapGuard.MAX_FLOORS - 1) if (fl is float or fl is int) and is_finite(float(fl)) else 0
	var sel: Variant = m.get("selection", [])
	out["selection"] = (sel as Array).slice(0, 64).filter(func(x): return x is String and (x as String).length() <= 64) if sel is Array else []
	out["tool"] = String(m.get("tool", "")).left(32) if m.get("tool") is String else ""
	if m.has("live"):
		if not (m.live is Dictionary and MapOps.value_ok(m.live, 0)):
			return {}
		out["live"] = m.live
	if m.has("agent") and m.agent is bool:
		out["agent"] = m.agent
	# Vues multiples (docs/EDITOR_VIEWS.md § 6.4) : plan de la vue survolée et
	# hauteur du curseur (m) ; une version plus ancienne les ignore.
	if m.get("vue") is String and String(m.vue) in MapView.PLANES:
		out["vue"] = String(m.vue)
	var zv: Variant = m.get("z")
	if (zv is float or zv is int) and is_finite(float(zv)):
		out["z"] = clampf(float(zv), -100.0, 300.0)
	return out


func _line(msg: Dictionary) -> PackedByteArray:
	var b := (JSON.stringify(msg, "", false, true) + "\n").to_utf8_buffer()
	if b.size() > MAX_LINE:
		push_warning("[MapCollab] message trop gros (%d octets) : non envoyé" % b.size())
		message.emit(Lang.t("Carte trop grosse pour la session (2 Mo au plus)", "Map too big for the session (2 MB at most)"), true)
		return PackedByteArray()
	return b


func _send(c: Conn, msg: Dictionary) -> void:
	if c.closed:
		return
	var b := _line(msg)
	if not b.is_empty():
		c.tcp.put_data(b)


## Messages complets reçus sur `c` (dictionnaires) ; un null dans la liste :
## message invalide ou trop long (déconnexion).
func _read(c: Conn) -> Array:
	var out := []
	c.tcp.poll()
	if c.tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return out
	var n := c.tcp.get_available_bytes()
	if n > 0:
		var r: Array = c.tcp.get_partial_data(mini(n, MAX_LINE + 1))
		if r[0] == OK:
			c.buf.append_array(r[1])
	while true:
		var i := c.buf.find(10)
		if i < 0:
			if c.buf.size() > MAX_LINE:
				out.append(null)
			break
		var line := c.buf.slice(0, i)
		c.buf = c.buf.slice(i + 1)
		if line.is_empty():
			continue
		var j := JSON.new()
		if j.parse(line.get_string_from_utf8()) != OK or not j.data is Dictionary or not (j.data as Dictionary).get("t") is String:
			out.append(null)
			break
		out.append(j.data)
	return out
