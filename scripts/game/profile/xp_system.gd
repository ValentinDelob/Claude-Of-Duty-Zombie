class_name XpSystem
extends Node
## XP gagnée pendant la partie (GAME_CONCEPT §4.15 ; barème : XpRules,
## docs/XP_RULES.md ; chemin réseau : /root/Game/Xp).
##
## Le SERVEUR compte l'XP de chaque joueur dans un relevé (XpRules, comme la
## ferraille : rien n'est calculé par le client) :
## * élimination : au joueur qui porte le coup fatal (Combat.zombie_damaged),
##   selon le type de l'ennemi (marcheur, coureur, sprinteur, rampant,
##   chien…) et la manche ; un piège compte pour celui qui l'a activé ;
## * fin de manche (RoundManager.round_ended) : manche survécue, et vague
##   spéciale ou de boss vaincue, pour chaque joueur non mort à ce moment ;
## * fin de partie (srv_close_all, appelé par Game.match_result) : relevés
##   clos, bonus d'évacuation, envoyés à tous dans le résultat (MatchResult).
## Chaque gain est envoyé au seul joueur concerné (_cl_xp : relevé complet,
## relu par XpRules.clean_ledger) ; le client l'affiche discrètement (« +9 XP »
## près du viseur, compteur d'XP de partie en haut à droite). Le profil est
## modifié UNE fois, à la fin de la partie (Game._show_match_end, MatchXp).

## Sources d'un gain (affichage).
const SRC_KILL := "kill"
const SRC_ROUND := "round"
## Durée d'affichage du « +N XP » (s) : les gains rapprochés s'additionnent.
const POP_TIME := 1.1

signal xp_changed

var game: Game
## Serveur : pid -> relevé (XpRules).
var ledgers: Dictionary = {}
## Joueur local : copie de son relevé (envoyée par le serveur).
var my_ledger: Dictionary = XpRules.new_ledger()
var _counter: Label
var _pop: Label
var _pop_sum := 0
var _pop_t := 0.0


func _ready() -> void:
	game = get_parent()
	if multiplayer.is_server():
		game.combat.zombie_damaged.connect(_on_zombie_damaged)
		game.rounds.round_ended.connect(_on_round_ended)
		Net.player_left.connect(_on_player_left)


# --------------------------------------------------------------------------
# Serveur
# --------------------------------------------------------------------------

## Relevé du joueur `pid` (créé au besoin).
func ledger(pid: int) -> Dictionary:
	if not ledgers.has(pid):
		ledgers[pid] = XpRules.new_ledger()
	return ledgers[pid]


## Type d'ennemi (XpRules) d'un zombie.
static func enemy_type_of(z: Zombie) -> String:
	if z == null:
		return XpRules.WALKER
	return XpRules.enemy_type(z is Hellhound, z.is_crawler(), z.speed_class)


func _on_zombie_damaged(pid: int, zid: int, _dmg: int, killed: bool, _headshot: bool, _kind: Combat.HitKind) -> void:
	if not killed or game.session.get_data(pid) == null:
		return
	# Le corps reste dans le gestionnaire jusqu'à sa dissolution : son type se lit encore.
	var type := enemy_type_of(game.zombies.get_zombie(zid))
	var gained := XpRules.add_kill(ledger(pid), type, game.rounds.round_n)
	_send(pid, gained, SRC_KILL)


## Fin de manche : manche survécue (et vague vaincue) pour chaque joueur non
## mort. Émis avant RoundManager._wave_cleared : `rounds.wave` est encore le
## type de la vague, et les morts ne sont pas encore revenus.
func _on_round_ended(n: int) -> void:
	if GameState.state == GameState.State.GAME_OVER:
		return
	var wave := game.rounds.wave
	for pid in game.session.data:
		var pd: PlayerData = game.session.data[pid]
		if pd.life == PlayerData.Life.DEAD:
			continue
		var l := ledger(pid)
		var gained := XpRules.add_round(l, n)
		if wave != "":
			gained += XpRules.add_wave(l, wave, n)
		_send(pid, gained, SRC_ROUND)


func _on_player_left(pid: int) -> void:
	ledgers.erase(pid)


## Serveur, fin de partie : clôt le relevé de chaque joueur (bonus
## d'évacuation si `evacuated`) ; rend pid -> relevé (MatchResult).
func srv_close_all(evacuated: bool) -> Dictionary:
	var out := {}
	for pid in game.session.data:
		var l := ledger(pid)
		XpRules.close(l, evacuated)
		out[pid] = l.duplicate(true)
	return out


func _send(pid: int, gained: int, source: String) -> void:
	if gained <= 0:
		return
	if pid == multiplayer.get_unique_id():
		_cl_xp(ledger(pid).duplicate(true), gained, source)
	elif multiplayer.has_multiplayer_peer():
		_cl_xp.rpc_id(pid, ledger(pid), gained, source)


# --------------------------------------------------------------------------
# Joueur local
# --------------------------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _cl_xp(l: Variant, gained: Variant, source: Variant) -> void:
	my_ledger = XpRules.clean_ledger(l)
	var g := ProfileValues.to_int(gained, 0, 0, 1 << 30)
	xp_changed.emit()
	if GameState.state == GameState.State.GAME_OVER or game.hud == null:
		return
	_refresh_counter()
	if g > 0 and source is String and String(source) in [SRC_KILL, SRC_ROUND]:
		_show_pop(g)


## XP de la partie du joueur local (avant le bonus d'évacuation).
func my_total() -> int:
	return XpRules.total(my_ledger)


## Compteur discret de l'XP de la partie, en haut à droite (au-dessus du
## compteur d'échantillons et de pièces, LootSystem).
func _refresh_counter() -> void:
	if _counter == null:
		_counter = HudStyle.label("", 16, HudStyle.TEXT_DIM, "text", 3)
		_counter.name = "MatchXp"
		_counter.anchor_left = 1.0
		_counter.anchor_right = 1.0
		_counter.offset_left = -520
		_counter.offset_right = -24
		_counter.offset_top = 128
		_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		game.hud.add_child(_counter)
	_counter.text = counter_text(my_total())
	_counter.visible = _counter.text != ""


## Texte du compteur : « XP DE PARTIE 1 240 » ("" : rien gagné). Pure.
static func counter_text(xp: int) -> String:
	if xp <= 0:
		return ""
	return Lang.t("XP DE PARTIE %s", "MATCH XP %s") % group(xp)


## « +N XP » léger sous le viseur ; les gains rapprochés s'additionnent.
func _show_pop(gained: int) -> void:
	if _pop == null:
		_pop = HudStyle.label("", 18, XP_COLOR, "condensed", 3)
		_pop.name = "XpPop"
		_pop.set_anchors_preset(Control.PRESET_CENTER)
		_pop.position = Vector2(34, 22)
		_pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		game.hud.add_child(_pop)
	_pop_sum = (_pop_sum if _pop_t > 0.0 else 0) + gained
	_pop_t = POP_TIME
	_pop.text = pop_text(_pop_sum)
	_pop.modulate.a = 0.9
	_pop.visible = true


## Couleur de l'XP (bleu pâle, distincte de l'or de la ferraille).
const XP_COLOR := Color(0.55, 0.8, 1.0)


static func pop_text(xp: int) -> String:
	return "+%d XP" % xp


## Fin de partie : compteur et « +N XP » masqués (le rapport de l'écran de
## fin prend le relais).
func hide_live() -> void:
	_pop_t = 0.0
	_pop_sum = 0
	if _pop:
		_pop.visible = false
	if _counter:
		_counter.visible = false


## Texte du « +N XP » affiché ("" : aucun ; tests).
func pop_shown() -> String:
	return _pop.text if _pop and _pop.visible else ""


## Texte du compteur affiché ("" : aucun ; tests).
func counter_shown() -> String:
	return _counter.text if _counter and _counter.visible else ""


func _process(delta: float) -> void:
	if _pop_t <= 0.0 or _pop == null:
		return
	_pop_t -= delta
	# Fondu sur le dernier tiers.
	_pop.modulate.a = clampf(_pop_t / (POP_TIME / 3.0), 0.0, 0.9)
	if _pop_t <= 0.0:
		_pop.visible = false
		_pop_sum = 0


## Nombre avec espaces de milliers (« 12 450 »).
static func group(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = " " + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out
