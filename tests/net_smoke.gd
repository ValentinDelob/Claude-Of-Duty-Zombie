extends Node
## Test réseau multi-processus (lancé par tools/net_smoke.sh).
##   --role=host   --port=N --max=M   : héberge, attend M-1 clients, vérifie, quitte
##   --role=client --port=N --expect=ok|full : se connecte et vérifie le résultat

var role := ""
var port := 17801
var max_players := 2
var expect := "ok"
var _deadline := 20.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"role": role = kv[1]
			"port": port = kv[1].to_int()
			"max": max_players = kv[1].to_int()
			"expect": expect = kv[1]
	if role == "host":
		Net.host(port, max_players, "Hote")
		Net.players_changed.connect(_host_check)
		Net.peer_rejected.connect(func(_id, r): _rejections += 1; print("[smoke] refus: ", r))
	else:
		Net.joined_server.connect(_on_joined)
		Net.connection_error.connect(func(t, m): _result(expect == "full" and m.contains("plein"), "%s: %s" % [t, m]))
		Net.join("127.0.0.1", port, "Client")


func _host_check() -> void:
	if Net.players.size() == max_players:
		_was_full = true
		print("[smoke] host: %d joueurs : %s" % [Net.players.size(), Net.players])
	elif _was_full and Net.players.size() == 1:
		_result(_rejections >= 1, "plein atteint, %d refus, client parti proprement" % _rejections)


var _was_full := false
var _rejections := 0


func _result(ok: bool, info: String) -> void:
	print("[smoke] %s %s : %s" % [role, "OK" if ok else "ECHEC", info])
	Net.leave()
	get_tree().quit(0 if ok else 1)


func _process(delta: float) -> void:
	_deadline -= delta
	if _deadline <= 0.0:
		_result(false, "timeout du test")


func _on_joined() -> void:
	if expect != "ok":
		_result(false, "accepté alors que le serveur devait être plein")
		return
	# Reste connecté pendant que le 3e joueur tente sa chance.
	await get_tree().create_timer(2.5).timeout
	_result(Net.players.size() == 2 and Net.mode == Net.Mode.CLIENT, "accepté, %d joueurs vus" % Net.players.size())
