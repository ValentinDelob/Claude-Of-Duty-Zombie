class_name SpectatorCamera
extends Node
## Spectateur (joueur mort en multijoueur) : la vue passe sur un coéquipier
## encore en vie ([Tir] : joueur suivant), retour à sa propre caméra à la
## réapparition ou quand plus personne n'est à regarder. Nœud enfant de Game
## (« Spectator »), sans RPC.

var game: Game
## Joueur regardé (null : vue du joueur local).
var spectating: Player
var _index := 0


func setup(g: Game) -> void:
	game = g


func _process(_delta: float) -> void:
	update()


func update() -> void:
	if game == null or game.local_player == null:
		return
	var session := game.session
	var pd := session.local_data()
	var is_dead := pd != null and pd.life == PlayerData.Life.DEAD and GameState.state != GameState.State.GAME_OVER
	var others: Array = []
	for p: Player in game.players.values():
		if not p.is_local:
			var opd := session.get_data(p.peer_id)
			if opd and opd.life != PlayerData.Life.DEAD:
				others.append(p)
	if not is_dead or others.is_empty():
		if spectating:
			spectating = null
			game.local_player.camera.make_current()
			game.hud.set_spectating("")
		return
	if Input.is_action_just_pressed("fire") and not game.menu_open():
		_index += 1
	var target: Player = others[_index % others.size()]
	if target != spectating:
		spectating = target
		target.camera.make_current()
		game.hud.set_spectating(Net.player_name(target.peer_id))
