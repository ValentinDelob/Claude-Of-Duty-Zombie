extends Node
## Téléchargement d'une liste de fichiers vérifiés, avec reprise
## (docs/RELEASE.md § 4) : chaque fichier arrive dans « <chemin>.part », écrit
## au fil de la réception ; une coupure garde ce qui est reçu et le
## téléchargement suivant reprend à la suite (en-tête HTTP « Range », réponse
## 206 de GitHub). Le fichier ne prend son vrai nom qu'après vérification de
## sa taille ET de sa somme SHA-256 ; une somme fausse efface tout et
## recommence une fois depuis zéro.
## HTTPClient et non HTTPRequest : ce dernier efface le fichier partiel quand
## la connexion coupe (reprise impossible).
## Chaque adresse, redirections comprises, passe par `allow` (par défaut
## Releases.is_allowed_url : HTTPS, domaines GitHub seulement).

signal finished(ok: bool, error_key: String)

const Releases := preload("res://scripts/releases.gd")
const Store := preload("res://scripts/store.gd")
## Délai sans aucune donnée reçue avant d'abandonner (s).
const STALL_SEC := 30.0
## Temps de lecture par image (ms) : l'interface reste fluide.
const BUDGET_MS := 8

enum St { IDLE, CONNECTING, REQUESTING, BODY }

## Adresse autorisée ? (les tests y mettent leur serveur local.)
var allow: Callable = Releases.is_allowed_url
var headers := PackedStringArray(Releases.HEADERS)
## Octets des fichiers terminés / octets à recevoir en tout (progression).
var done_bytes := 0
var total_bytes := 0

var _queue: Array = []
var _cur: Dictionary = {}
var _offset := 0          # octets déjà dans le fichier partiel au départ
var _got := 0             # octets reçus pendant cette requête
var _hops := 0
var _retried := false
var _state := St.IDLE
var _client: HTTPClient
var _path := ""           # chemin de la requête sur le serveur
var _out: FileAccess
var _stall := 0.0
var _range_asked := false


func _ready() -> void:
	set_process(false)


## Lance la liste [{url, path, sha256, size}] ; `finished` à la fin.
func start(files: Array) -> void:
	_queue = files.duplicate()
	total_bytes = 0
	done_bytes = 0
	for f: Dictionary in _queue:
		total_bytes += int(f.size)
	_next()


func busy() -> bool:
	return not _cur.is_empty()


## Octets reçus en tout (progression affichée).
func progress_bytes() -> int:
	return done_bytes + (_offset + _got if not _cur.is_empty() else 0)


func _next() -> void:
	if _queue.is_empty():
		_cur = {}
		set_process(false)
		finished.emit(true, "")
		return
	_cur = _queue.pop_front()
	_retried = false
	_request()


func _part() -> String:
	return String(_cur.path) + ".part"


func _request() -> void:
	DirAccess.make_dir_recursive_absolute(String(_cur.path).get_base_dir())
	_offset = _file_size(_part())
	_got = 0
	if _offset >= int(_cur.size):
		if _offset > int(_cur.size):
			_remove(_part())     # partiel faux : plus grand que le fichier
			_offset = 0
		else:
			_finish_file()       # déjà tout reçu (coupure juste avant la vérification)
			return
	_hops = 0
	_connect(String(_cur.url))


## Connexion à l'hôte de `url` (http:// pour les tests locaux seulement,
## sinon https:// avec vérification du certificat).
func _connect(url: String) -> void:
	if not allow.call(url):
		push_warning("[launcher] adresse refusée : " + url.left(200))
		_fail("download_failed")
		return
	var tls := url.begins_with("https://")
	var rest := url.substr(8 if tls else 7)
	var slash := rest.find("/")
	var hostport := rest.substr(0, slash) if slash >= 0 else rest
	_path = rest.substr(slash) if slash >= 0 else "/"
	var host := hostport
	var port := 443 if tls else 80
	if ":" in hostport:
		host = hostport.get_slice(":", 0)
		port = int(hostport.get_slice(":", 1))
	_client = HTTPClient.new()
	_client.read_chunk_size = 1 << 18
	var err := _client.connect_to_host(host, port, TLSOptions.client() if tls else null)
	if err != OK:
		_fail("download_failed")
		return
	_state = St.CONNECTING
	_stall = 0.0
	set_process(true)


func _process(delta: float) -> void:
	if _client == null or _state == St.IDLE:
		return
	_client.poll()
	var s := _client.get_status()
	match _state:
		St.CONNECTING:
			if s == HTTPClient.STATUS_CONNECTED:
				var h := PackedStringArray(headers)
				_range_asked = _offset > 0
				if _range_asked:
					h.append("Range: bytes=%d-" % _offset)
				if _client.request(HTTPClient.METHOD_GET, _path, h) != OK:
					_broken()
					return
				_state = St.REQUESTING
			elif s in [HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CANT_RESOLVE,
					HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR]:
				_broken()
				return
		St.REQUESTING:
			if s == HTTPClient.STATUS_BODY or s == HTTPClient.STATUS_CONNECTED:
				_on_response()
				return
			if s != HTTPClient.STATUS_REQUESTING:
				_broken()
				return
		St.BODY:
			var t0 := Time.get_ticks_msec()
			while _client.get_status() == HTTPClient.STATUS_BODY and Time.get_ticks_msec() - t0 < BUDGET_MS:
				var chunk := _client.read_response_body_chunk()
				if chunk.is_empty():
					break
				if _offset + _got + chunk.size() > int(_cur.size):
					# Plus d'octets que prévu : fichier faux (ou serveur trompeur).
					_close_out()
					_remove(_part())
					_finish_file()
					return
				_out.store_buffer(chunk)
				_got += chunk.size()
				_stall = 0.0
				_client.poll()
			if _client.get_status() != HTTPClient.STATUS_BODY:
				_close_out()
				if _offset + _got == int(_cur.size):
					_finish_file()
				else:
					_broken()   # coupure : partiel gardé
				return
	_stall += delta
	if _stall > STALL_SEC:
		_broken()


func _on_response() -> void:
	var code := _client.get_response_code()
	var h := _client.get_response_headers()
	if code in [301, 302, 303, 307, 308]:
		var loc := Releases.header(h, "location")
		_hops += 1
		_client.close()
		if _hops <= Releases.MAX_REDIRECTS and allow.call(loc):
			_connect(loc)
			return
		push_warning("[launcher] redirection refusée : " + loc.left(200))
		_fail("download_failed")
		return
	if code == 206 and _range_asked and _range_start(Releases.header(h, "content-range")) == _offset:
		_out = FileAccess.open(_part(), FileAccess.READ_WRITE)
		if _out:
			_out.seek_end()
	elif code == 200:
		# Réponse entière (serveur sans reprise, ou départ de zéro).
		_offset = 0
		_out = FileAccess.open(_part(), FileAccess.WRITE)
	else:
		# Reprise refusée (416…) ou réponse inattendue : départ de zéro, une fois.
		_client.close()
		_remove(_part())
		if not _retried and code in [206, 416]:
			_retried = true
			_request()
			return
		_fail("download_failed")
		return
	if _out == null:
		_fail("download_failed")
		return
	_state = St.BODY


## Connexion perdue : ce qui est reçu reste dans le fichier partiel.
func _broken() -> void:
	_close_out()
	_fail("download_failed")


func _finish_file() -> void:
	_state = St.IDLE
	if _client:
		_client.close()
	if Store.verify_file(_part(), String(_cur.sha256), int(_cur.size)):
		_remove(String(_cur.path))
		if DirAccess.rename_absolute(_part(), String(_cur.path)) != OK:
			_fail("download_failed")
			return
		done_bytes += int(_cur.size)
		print("[launcher] fichier vérifié : ", String(_cur.path).get_file())
		_next()
		return
	# Somme ou taille fausse : rien n'est gardé ; un nouvel essai depuis zéro.
	print("[launcher] fichier NON conforme (taille ou SHA-256), supprimé : ", String(_cur.path).get_file())
	_remove(_part())
	if not _retried:
		_retried = true
		_request()
		return
	_fail("integrity_failed")


func _close_out() -> void:
	if _out:
		_out.close()
		_out = null


func _fail(key: String) -> void:
	_close_out()
	if _client:
		_client.close()
	_state = St.IDLE
	_cur = {}
	_queue.clear()
	set_process(false)
	finished.emit(false, key)


## Début annoncé par « Content-Range: bytes <début>-<fin>/<total> », -1 sinon.
static func _range_start(v: String) -> int:
	var m := RegEx.create_from_string("^bytes ([0-9]+)-[0-9]+/([0-9]+|\\*)$").search(v.strip_edges())
	return int(m.get_string(1)) if m else -1


static func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f else 0


static func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
