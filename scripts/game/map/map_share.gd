class_name MapShare
extends Node
## Envoi automatique d'une carte perso aux invités du salon (enfant de Net,
## chemin réseau /root/Net/MapShare). Protocole (docs/ARCHITECTURE.md) :
##   1. l'hôte choisit une carte perso : elle est contrôlée (CustomMapGuard),
##      mise en paquet canonique (les cinq JSON) et identifiée par son SHA-256,
##      copiée dans son cache ; annonce `_cl_offer` {sha, size, chunk, chunks, nom, n}
##      à tous (et à chaque nouvel arrivant), puis la carte du salon
##      « partage:<sha> » (Net._cl_lobby_map) ;
##   2. le client qui a déjà ce hash dans son cache (contrôlé à nouveau) répond
##      « prête » ; sinon il demande l'envoi (`_srv_request`) ;
##   3. l'hôte envoie des morceaux de 16 Ko sur un canal fiable dédié
##      (`_cl_chunk`, CHANNEL, avec le numéro n de l'annonce), au plus WINDOW morceaux non acquittés et
##      CHUNKS_PER_FRAME par image : ni le jeu ni le salon ne sont bloqués ;
##      le client acquitte chaque morceau (`_srv_ack`) ;
##   4. le client vérifie l'ordre et la taille des morceaux, la taille totale,
##      le SHA-256, la forme canonique, la légitimité et la jouabilité ; il
##      enregistre la carte dans user://maps_cache/<sha>/ et répond « prête »
##      (`_srv_status`), ou « refusée » avec un code (jamais chargée) ;
##   5. l'hôte diffuse l'état de chacun (`_cl_states`, 10 Hz au plus) ; la
##      partie ne démarre que quand tous les joueurs sont « prête »
##      (Net.start_match refuse sinon).
## Serveur autoritaire : aucun message ne permet à un client d'envoyer une
## carte ; les RPC du serveur vérifient l'expéditeur (joueur connu), le hash
## annoncé et limitent le débit ; ceux du client exigent l'expéditeur 1.

signal states_changed
signal offer_changed
## Client : la carte annoncée est refusée (message lisible, déjà traduit).
signal local_failed(message: String)

## Canal ENet des morceaux (les autres messages restent sur le canal 0).
const CHANNEL := 2
const WINDOW := 8
const CHUNKS_PER_FRAME := 4
## Messages acceptés par client et par seconde (seau à jetons).
const RATE := 120.0
const BURST := 240.0
## Demandes d'envoi par client pour une même carte.
const MAX_REQUESTS := 3
const STATES_INTERVAL := 0.1
const STATES := ["attente", "telechargement", "prete", "refusee"]

## Carte annoncée (vide : carte officielle) : {sha, size, chunk, chunks, nom, n}.
var offer: Dictionary = {}
## peer_id -> {etat, pct, raison} (tenu par le serveur, diffusé aux clients).
var states: Dictionary = {}
## Client : état et raison du refus de la carte annoncée, pour ce joueur.
var local_state := ""
var local_reason := ""
## Serveur : morceaux envoyés depuis le début (tests : cache réutilisé).
var sent_chunks := 0

## Réglages des tests (pris en compte seulement pendant un autotest) : taille
## des morceaux, débit (morceaux / s), morceau à corrompre à l'envoi.
var test_chunk_size := 0
var test_chunks_per_sec := 0.0
var test_corrupt_chunk := -1

var _package := PackedByteArray()
var _sending: Dictionary = {}   # peer -> {next, acked}
var _requests: Dictionary = {}  # peer -> nombre de demandes
var _tokens: Dictionary = {}    # peer -> jetons
var _rx: MapTransfer
var _dirty := false
var _states_t := 0.0
var _test_budget := 0.0
## Numéro de la dernière annonce (serveur) : les morceaux le portent, un client
## ignore ceux d'une annonce précédente (même carte annoncée deux fois).
var _serial := 0


func reset() -> void:
	offer = {}
	states = {}
	local_state = ""
	local_reason = ""
	_package = PackedByteArray()
	_sending.clear()
	_requests.clear()
	_tokens.clear()
	_rx = null
	_dirty = false


func _testing() -> bool:
	return Autotest.active


# ------------------------------------------------------------------ serveur

## Serveur : annonce la carte perso « perso:<dossier> » du joueur. {ok, sha,
## reasons} ; refusée si elle ne passe pas le contrôle (elle ne part pas).
func srv_offer_local(map_id: String) -> Dictionary:
	var folder := map_id.trim_prefix(EditorMapDef.CUSTOM_PREFIX)
	if folder.is_empty() or folder.contains("/") or folder.contains("\\") or folder.contains("..") or folder.contains(":"):
		return {"ok": false, "reasons": [["dossier de carte invalide", "invalid map folder"]]}
	var r := CustomMapGuard.load_local(EditorMap.map_dir(folder))
	if not r.ok:
		return r
	var pk := CustomMapGuard.package_of(r.map)
	# Le paquet canonique doit passer exactement le contrôle des invités.
	var chk := CustomMapGuard.check_package(pk.bytes, pk.sha)
	if not chk.ok:
		return chk
	if CustomMapGuard.store(pk.sha, pk.texts) != OK:
		return {"ok": false, "reasons": [CustomMapGuard.REASONS.cache]}
	var nom: Dictionary = r.map.carte.get("nom", {})
	var n := {"fr": String(nom.get("fr", r.map.id())), "en": String(nom.get("en", nom.get("fr", r.map.id())))}
	srv_offer_package(pk.bytes, n)
	return {"ok": true, "sha": pk.sha, "reasons": []}


## Serveur : annonce un paquet (déjà contrôlé ; les tests y passent aussi des
## paquets piégés pour vérifier le refus des invités).
func srv_offer_package(bytes: PackedByteArray, nom: Dictionary) -> void:
	_package = bytes
	var chunk := CustomMapGuard.CHUNK_BYTES
	if _testing() and test_chunk_size > 0:
		chunk = clampi(test_chunk_size, CustomMapGuard.MIN_CHUNK_BYTES, CustomMapGuard.CHUNK_BYTES)
	_serial += 1
	offer = {"sha": CustomMapGuard.sha256_hex(bytes), "size": bytes.size(), "chunk": chunk,
		"chunks": ceili(float(bytes.size()) / chunk), "nom": nom, "n": _serial}
	_sending.clear()
	_requests.clear()
	states = {}
	for pid in Net.players:
		states[pid] = _st("prete" if pid == 1 else "attente")
	print("[MapShare] carte annoncée : %s (%d octets, %d morceaux, %s)" % [nom.get("fr", "?"), bytes.size(), offer.chunks, offer.sha.substr(0, 12)])
	_cl_offer.rpc(offer)
	offer_changed.emit()
	_broadcast_states()


## Serveur : plus de carte perso (carte officielle choisie).
func srv_clear() -> void:
	if offer.is_empty():
		return
	offer = {}
	states = {}
	_package = PackedByteArray()
	_sending.clear()
	_cl_offer.rpc({})
	offer_changed.emit()
	states_changed.emit()


func srv_peer_joined(pid: int) -> void:
	if offer.is_empty():
		return
	states[pid] = _st("attente")
	_cl_offer.rpc_id(pid, offer)
	_dirty = true


func srv_peer_left(pid: int) -> void:
	_sending.erase(pid)
	_requests.erase(pid)
	_tokens.erase(pid)
	if states.has(pid):
		states.erase(pid)
		_dirty = true


## Tout le monde a la carte annoncée ? [ok, raison lisible].
func can_start() -> Array:
	if offer.is_empty():
		return [true, ""]
	var waiting := []
	var refused := []
	for pid in Net.players:
		var s: Dictionary = states.get(pid, {})
		match String(s.get("etat", "attente")):
			"prete":
				pass
			"refusee":
				refused.append(Net.player_name(pid))
			_:
				waiting.append(Net.player_name(pid))
	if not refused.is_empty():
		return [false, Lang.t("Carte refusée par : %s", "Map refused by: %s") % ", ".join(refused)]
	if not waiting.is_empty():
		return [false, Lang.t("En attente de la carte : %s", "Waiting for the map: %s") % ", ".join(waiting)]
	return [true, ""]


func _st(etat: String, pct := 0, raison := "") -> Dictionary:
	return {"etat": etat, "pct": pct, "raison": raison}


func _set_state(pid: int, etat: String, pct: int, raison: String) -> void:
	var s := _st(etat, pct, raison)
	if states.get(pid, {}) != s:
		states[pid] = s
		_dirty = true


func _broadcast_states() -> void:
	_dirty = false
	_states_t = 0.0
	_cl_states.rpc(states)
	states_changed.emit()


## Expéditeur d'une requête : un joueur connu (jamais l'hôte lui-même), avec
## des jetons de débit ; 0 sinon (message ignoré).
func _srv_sender() -> int:
	if not multiplayer.is_server():
		return 0
	var pid := multiplayer.get_remote_sender_id()
	if pid == 1 or not Net.players.has(pid):
		return 0
	var t := float(_tokens.get(pid, BURST))
	if t < 1.0:
		return 0
	_tokens[pid] = t - 1.0
	return pid


func _process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server() or Net.mode != Net.Mode.HOST:
		return
	for pid in _tokens:
		_tokens[pid] = minf(BURST, float(_tokens[pid]) + RATE * delta)
	if not offer.is_empty() and not _sending.is_empty():
		var budget := CHUNKS_PER_FRAME
		if _testing() and test_chunks_per_sec > 0.0:
			_test_budget = minf(_test_budget + test_chunks_per_sec * delta, 1.0)
			budget = int(_test_budget)
			_test_budget -= budget
		var peers := multiplayer.get_peers()
		for pid in _sending.keys():
			if not pid in peers:
				_sending.erase(pid)
				continue
			var s: Dictionary = _sending[pid]
			while budget > 0 and s.next < offer.chunks and s.next - s.acked < WINDOW:
				var a: int = s.next * offer.chunk
				var data := _package.slice(a, mini(a + offer.chunk, _package.size()))
				if _testing() and s.next == test_corrupt_chunk and not data.is_empty():
					data[0] = data[0] ^ 0x5A
				_cl_chunk.rpc_id(pid, offer.sha, offer.n, s.next, data)
				s.next += 1
				sent_chunks += 1
				budget -= 1
	_states_t += delta
	if _dirty and _states_t >= STATES_INTERVAL:
		_broadcast_states()


@rpc("any_peer", "call_remote", "reliable")
func _srv_request(sha: Variant) -> void:
	var pid := _srv_sender()
	if pid == 0 or offer.is_empty() or not (sha is String and sha == offer.sha) or _sending.has(pid):
		return
	var n := int(_requests.get(pid, 0))
	if n >= MAX_REQUESTS:
		return
	_requests[pid] = n + 1
	_sending[pid] = {"next": 0, "acked": 0}
	_set_state(pid, "telechargement", 0, "")


@rpc("any_peer", "call_remote", "reliable")
func _srv_ack(sha: Variant, count: Variant) -> void:
	var pid := _srv_sender()
	if pid == 0 or not _sending.has(pid) or not (sha is String and sha == offer.sha) or not count is int:
		return
	var s: Dictionary = _sending[pid]
	if count < s.acked or count > s.next:
		return
	s.acked = count
	_set_state(pid, "telechargement", int(100.0 * count / offer.chunks), "")
	if count >= offer.chunks:
		_sending.erase(pid)


@rpc("any_peer", "call_remote", "reliable")
func _srv_status(sha: Variant, etat: Variant, code: Variant) -> void:
	var pid := _srv_sender()
	if pid == 0 or offer.is_empty() or not (sha is String and sha == offer.sha):
		return
	if not (etat is String and etat in ["prete", "refusee"]):
		return
	var raison := String(code) if code is String and CustomMapGuard.REASONS.has(code) else ""
	_sending.erase(pid)
	var pct := 100 if etat == "prete" else int(states.get(pid, {}).get("pct", 0))
	_set_state(pid, etat, pct, raison)
	if etat == "refusee":
		print("[MapShare] %s a refusé la carte : %s" % [Net.player_name(pid), CustomMapGuard.reason_text(raison)])
	else:
		print("[MapShare] %s a la carte" % Net.player_name(pid))


# ------------------------------------------------------------------ client

func _from_host() -> bool:
	return multiplayer.get_remote_sender_id() == 1 and not multiplayer.is_server()


@rpc("authority", "call_remote", "reliable")
func _cl_offer(o: Variant) -> void:
	if not _from_host():
		return
	_rx = null
	local_reason = ""
	if o is Dictionary and o.is_empty():
		offer = {}
		local_state = ""
		offer_changed.emit()
		states_changed.emit()
		return
	var code := CustomMapGuard.check_offer(o)
	if code != "":
		offer = {}
		offer_changed.emit()
		_fail(code, [], String(o.get("sha", "")) if o is Dictionary and o.get("sha") is String else "")
		return
	var nom: Dictionary = o["nom"]
	offer = {"sha": o["sha"], "size": o["size"], "chunk": o["chunk"], "chunks": o["chunks"], "n": o["n"],
		"nom": {"fr": CustomMapGuard.clean_display(String(nom.get("fr", "?"))), "en": CustomMapGuard.clean_display(String(nom.get("en", nom.get("fr", "?"))))}}
	offer_changed.emit()
	# Déjà dans le cache (contrôlé à nouveau : empreinte, légitimité, jouabilité).
	var cached := CustomMapGuard.load_cached(offer.sha, true)
	if cached.ok:
		local_state = "prete"
		print("[MapShare] carte %s déjà en cache" % offer.sha.substr(0, 12))
		_srv_status.rpc_id(1, offer.sha, "prete", "")
		states_changed.emit()
		return
	_rx = MapTransfer.new()
	_rx.begin(offer)
	local_state = "telechargement"
	print("[MapShare] téléchargement de la carte %s (%d octets)" % [offer.sha.substr(0, 12), offer["size"]])
	_srv_request.rpc_id(1, offer.sha)
	states_changed.emit()


@rpc("authority", "call_remote", "reliable", CHANNEL)
func _cl_chunk(sha: Variant, n: Variant, index: Variant, data: Variant) -> void:
	# Morceau d'une autre carte ou d'une annonce précédente : ignoré.
	if not _from_host() or _rx == null or not (sha is String and sha == _rx.sha) or not (n is int and n == int(offer.get("n", -1))):
		return
	if not (index is int and data is PackedByteArray):
		_fail("morceau")
		return
	var err := _rx.add(index, data)
	if err != "":
		_fail(err)
		return
	_srv_ack.rpc_id(1, sha, _rx.received)
	if _rx.complete():
		_finish()


func _finish() -> void:
	var res := _rx.finish()
	if not res.ok:
		_fail(res.code)
		return
	var sha := _rx.sha
	var chk := CustomMapGuard.check_package(res.bytes, sha)
	if not chk.ok:
		_fail(chk.code, chk.reasons)
		return
	if CustomMapGuard.store(sha, chk.texts) != OK:
		_fail("cache")
		return
	_rx = null
	local_state = "prete"
	print("[MapShare] carte %s reçue, vérifiée et enregistrée" % sha.substr(0, 12))
	_srv_status.rpc_id(1, sha, "prete", "")
	states_changed.emit()


## Refus local : la carte n'est jamais chargée, l'hôte est prévenu.
func _fail(code: String, reasons: Array = [], sha := "") -> void:
	if sha == "":
		sha = _rx.sha if _rx != null else String(offer.get("sha", ""))
	_rx = null
	local_state = "refusee"
	local_reason = CustomMapGuard.reason_text(code)
	var detail := CustomMapGuard.reasons_text(reasons.slice(0, 2))
	if detail != "" and detail != local_reason:
		local_reason += "\n" + detail
	print("[MapShare] carte refusée (%s) : %s" % [code, local_reason.replace("\n", " ; ")])
	if CustomMapGuard.sha_ok(sha):
		_srv_status.rpc_id(1, sha, "refusee", code)
	local_failed.emit(local_reason)
	states_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _cl_states(s: Variant) -> void:
	if not _from_host() or not s is Dictionary or s.size() > Net.MAX_SUPPORTED_PLAYERS + 2:
		return
	var clean := {}
	for pid in s:
		var v = s[pid]
		if not (pid is int and v is Dictionary and v.get("etat") is String and v.etat in STATES and v.get("pct") is int and v.get("raison") is String):
			continue
		clean[pid] = _st(v.etat, clampi(v.pct, 0, 100), v.raison if CustomMapGuard.REASONS.has(v.raison) else "")
	states = clean
	states_changed.emit()


## Texte d'état d'un joueur pour le salon ("" : pas de carte perso).
func state_text(pid: int) -> String:
	if offer.is_empty():
		return ""
	var s: Dictionary = states.get(pid, {})
	match String(s.get("etat", "attente")):
		"prete":
			return Lang.t("carte prête", "map ready")
		"telechargement":
			return Lang.t("télécharge %d %%", "downloading %d%%") % int(s.get("pct", 0))
		"refusee":
			return Lang.t("carte refusée", "map refused")
	return Lang.t("en attente de la carte", "waiting for the map")
