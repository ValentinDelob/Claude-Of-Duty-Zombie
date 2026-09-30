extends SceneTree
## Téléchargement avec reprise (scripts/downloader.gd) contre un petit serveur
## HTTP LOCAL (127.0.0.1, aucun accès à Internet) qui sait : servir un fichier
## avec ou sans « Range », couper la connexion au milieu, envoyer des octets
## faux, rediriger (vers lui-même ou vers un domaine interdit).
##   godot --headless --path launcher -s res://tests/test_downloader.gd
## Fichiers écrits dans tests/_out/launcher_dl_test (supprimé à la fin).

const Downloader := preload("res://scripts/downloader.gd")
## Un dossier par processus : deux exécutions simultanées (check en parallèle
## d'un essai à la main) ne se marchent pas dessus.
var TMP := "res://tests/_out/launcher_dl_test_%d" % OS.get_process_id()
const SIZE := 3 * 1024 * 1024 + 123
const CUT_AT := 1024 * 1024

var failures := 0
var server := TCPServer.new()
var port := 0
var data := PackedByteArray()
var sha := ""
## Requêtes reçues : [chemin, en-tête Range].
var seen: Array = []
var _cut_done := false
var _clients: Array = []


func check(ok: bool, what: String) -> void:
	print(("OK    " if ok else "ÉCHEC ") + what)
	if not ok:
		failures += 1


func _initialize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	data.resize(SIZE)
	for i in SIZE:
		data[i] = rng.randi() & 255
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	sha = ctx.finish().hex_encode()
	for p in range(18610, 18640):
		if server.listen(p, "127.0.0.1") == OK:
			port = p
			break
	check(port > 0, "serveur local à l'écoute")
	_run.call_deferred()


func _process(_delta: float) -> bool:
	_serve()
	return false


func _run() -> void:
	var root := ProjectSettings.globalize_path(TMP)
	_rmdir(root)
	DirAccess.make_dir_recursive_absolute(root)
	var dl: Node = Downloader.new()
	dl.allow = func(url: String) -> bool: return url.begins_with("http://127.0.0.1:%d/" % port)
	root_node().add_child(dl)
	await process_frame
	var base := "http://127.0.0.1:%d" % port

	# 1. Téléchargement complet, vérifié, nom définitif seulement à la fin.
	var r: Array = await _fetch(dl, base + "/full", root + "/a.bin")
	check(r[0] and _sha(root + "/a.bin") == sha and not FileAccess.file_exists(root + "/a.bin.part"), "fichier complet reçu et vérifié")

	# 2. Coupure au milieu : partiel gardé ; le suivant reprend (Range) et finit.
	seen.clear()
	r = await _fetch(dl, base + "/cut", root + "/b.bin")
	var part := _size(root + "/b.bin.part")
	check(not r[0] and r[1] == "download_failed" and not FileAccess.file_exists(root + "/b.bin"), "coupure : échec signalé, rien d'installé")
	check(part > 0 and part < SIZE, "coupure : partiel gardé (%d octets)" % part)
	r = await _fetch(dl, base + "/cut", root + "/b.bin")
	var ranged: bool = seen.any(func(s): return s[1] == "bytes=%d-" % part)
	check(r[0] and ranged and _sha(root + "/b.bin") == sha, "reprise à l'octet %d (Range) puis fichier vérifié" % part)

	# 3. Serveur sans reprise (réponse 200 entière) : le partiel est remplacé.
	_write_part(root + "/c.bin.part", CUT_AT)
	r = await _fetch(dl, base + "/norange", root + "/c.bin")
	check(r[0] and _sha(root + "/c.bin") == sha, "serveur sans reprise : fichier entier repris, vérifié")

	# 4. Octets faux : refusé (après un nouvel essai), rien ne reste.
	r = await _fetch(dl, base + "/bad", root + "/d.bin")
	check(not r[0] and r[1] == "integrity_failed" and not FileAccess.file_exists(root + "/d.bin")
		and not FileAccess.file_exists(root + "/d.bin.part"), "somme fausse : refusé, aucun fichier gardé")

	# 5. Partiel faux (plus grand que le fichier) : effacé, retéléchargé.
	_write_part(root + "/e.bin.part", SIZE + 10)
	r = await _fetch(dl, base + "/full", root + "/e.bin")
	check(r[0] and _sha(root + "/e.bin") == sha, "partiel trop grand : effacé puis fichier vérifié")

	# 6. Redirections : vers le même serveur suivie ; vers un domaine interdit refusée.
	r = await _fetch(dl, base + "/redir", root + "/f.bin")
	check(r[0] and _sha(root + "/f.bin") == sha, "redirection autorisée suivie")
	r = await _fetch(dl, base + "/evil", root + "/g.bin")
	check(not r[0] and not FileAccess.file_exists(root + "/g.bin"), "redirection vers un domaine interdit refusée")

	# 7. Adresse de départ interdite : rien n'est demandé.
	seen.clear()
	r = await _fetch(dl, "https://evil.example/x.bin", root + "/h.bin")
	check(not r[0] and seen.is_empty(), "adresse interdite : aucune requête")

	# 8. Liste de deux fichiers : progression jusqu'au total.
	var got: Array = []
	dl.finished.connect(func(ok: bool, key: String) -> void: got.append([ok, key]), CONNECT_ONE_SHOT)
	dl.start([{"url": base + "/full", "path": root + "/i1.bin", "sha256": sha, "size": SIZE},
		{"url": base + "/full", "path": root + "/i2.bin", "sha256": sha, "size": SIZE}])
	while got.is_empty():
		await process_frame
	check(got[0][0] and dl.done_bytes == 2 * SIZE and dl.total_bytes == 2 * SIZE, "deux fichiers : progression complète")

	dl.queue_free()
	_rmdir(root)
	check(not DirAccess.dir_exists_absolute(root), "dossier temporaire supprimé")
	server.stop()
	print("DOWNLOADER: %d échec(s)" % failures)
	quit(1 if failures > 0 else 0)


func root_node() -> Node:
	return root


func _fetch(dl: Node, url: String, path: String) -> Array:
	var got: Array = []
	dl.finished.connect(func(ok: bool, key: String) -> void: got.append([ok, key]), CONNECT_ONE_SHOT)
	dl.start([{"url": url, "path": path, "sha256": sha, "size": SIZE}])
	var t := 0
	while got.is_empty() and t < 1200:
		await process_frame
		t += 1
	return got[0] if not got.is_empty() else [false, "timeout"]


# ------------------------------------------------------------------ serveur

func _serve() -> void:
	while server.is_connection_available():
		var c := server.take_connection()
		_clients.append({"peer": c, "buf": ""})
	for cl: Dictionary in _clients.duplicate():
		var c: StreamPeerTCP = cl.peer
		c.poll()
		if c.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_clients.erase(cl)
			continue
		var n := c.get_available_bytes()
		if n > 0:
			cl.buf += c.get_utf8_string(n)
		if "\r\n\r\n" in cl.buf:
			_clients.erase(cl)
			_answer(c, cl.buf)


func _answer(c: StreamPeerTCP, req: String) -> void:
	var lines := req.split("\r\n")
	var path := lines[0].get_slice(" ", 1)
	var range_h := ""
	for l in lines:
		if l.to_lower().begins_with("range:"):
			range_h = l.substr(6).strip_edges()
	seen.append([path, range_h])
	var start := 0
	if range_h.begins_with("bytes=") and path != "/norange":
		start = int(range_h.substr(6).get_slice("-", 0))
	match path:
		"/redir":
			_head(c, "302 Found", ["Location: http://127.0.0.1:%d/full" % port, "Content-Length: 0"])
		"/evil":
			_head(c, "302 Found", ["Location: https://evil.example/x.bin", "Content-Length: 0"])
		"/bad":
			var junk := data.duplicate()
			junk[100] = junk[100] ^ 0xFF
			_body(c, junk, 0)
		"/cut":
			if not _cut_done and start == 0:
				_cut_done = true
				_head(c, "200 OK", ["Content-Length: %d" % SIZE])
				c.put_data(data.slice(0, CUT_AT))
			else:
				_body(c, data, start)
		_:
			_body(c, data, start)
	c.disconnect_from_host()


func _head(c: StreamPeerTCP, status: String, h: Array) -> void:
	c.put_data(("HTTP/1.1 %s\r\n%s\r\nConnection: close\r\n\r\n" % [status, "\r\n".join(h)]).to_utf8_buffer())


func _body(c: StreamPeerTCP, bytes: PackedByteArray, start: int) -> void:
	if start > 0:
		if start >= bytes.size():
			_head(c, "416 Range Not Satisfiable", ["Content-Length: 0"])
			return
		_head(c, "206 Partial Content", ["Content-Length: %d" % (bytes.size() - start),
			"Content-Range: bytes %d-%d/%d" % [start, bytes.size() - 1, bytes.size()]])
	else:
		_head(c, "200 OK", ["Content-Length: %d" % bytes.size()])
	c.put_data(bytes.slice(start))


# ------------------------------------------------------------------ fichiers

func _write_part(path: String, n: int) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	var b := data.slice(0, mini(n, SIZE))
	if n > SIZE:
		b.resize(n)
	f.store_buffer(b)
	f.close()


func _size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f else 0


func _sha(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""


func _rmdir(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(dir)
