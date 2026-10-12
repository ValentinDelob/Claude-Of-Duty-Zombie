extends TestCase
## JOUER du hub v2 (Partie.dc.html, PartieCoop.dc.html ; Hub2PlayPanel,
## Hub2PlayData, Hub2LobbyView, Hub2Equipment) : pastilles des vagues
## (rotation de WaveRules), carte du défi de la semaine, lignes de cartes,
## CARTES PERSONNALISÉES « POUR LE FUN », aperçu, ÉQUIPEMENT et choix des
## armes de départ (X), LANCER, vue COOP (adresse « IP:port »), salon de
## l'hôte (cartes de joueurs, PRÊT, ping, « N joueurs prêts sur M »,
## QUITTER en deux appuis, CHANGER DE CARTE et défi), ping du registre.

const PORT := 17991

var _saved := {}
var _frame: Control
var _host: FakeHost


class FakeHost extends MenuHost:
	var launched := 0

	func show_screen(_screen_name: String, _args := {}, _remember := true) -> void:
		pass

	func launch(_then: Callable, _duration := 1.8) -> void:
		launched += 1


func before_each() -> void:
	for k in ["menu_ui_scale", "using_pad", "language", "last_map", "player_name", "last_port", "last_ip"]:
		_saved[k] = Settings.get(k)
	Settings.using_pad = false
	Settings.language = "fr"
	Settings.menu_ui_scale = 1.0
	Settings.last_map = "bunker_k7"
	Settings.player_name = "Valentin"
	HubContractsView.day_override = HubData.parse_day("2026-11-18")
	WeeklyChallenge.now_override = HubData.parse_day("2026-11-18") * 86400.0 + 43200.0
	Hub2PlayPanel.last_view = Hub2PlayPanel.SOLO


func after_each() -> void:
	if is_instance_valid(_frame):
		_frame.queue_free()
	if Net.mode != Net.Mode.NONE:
		Net.leave()
	GameState.reset_to_menu()
	for k in _saved:
		Settings.set(k, _saved[k])
	HubContractsView.day_override = -1
	WeeklyChallenge.now_override = -1.0
	Hub2PlayPanel.last_view = Hub2PlayPanel.SOLO
	Hub2Screen.last_screen = "lab"
	Net.local_card = {}


static func demo_profile() -> PlayerProfile:
	var pr := PlayerProfile.new()
	pr.xp = PlayerProfile.xp_for_level(23) + 100
	return pr


func _open(pr: PlayerProfile = null) -> Hub2Screen:
	_frame = Control.new()
	_frame.size = Vector2(1280, 720)
	host.add_child(_frame)
	_host = FakeHost.new()
	_host.size = Vector2(1280, 720)
	_frame.add_child(_host)
	var hub := Hub2Screen.new()
	hub.menu = _host
	hub.size = Vector2(1280, 720)
	_host.add_child(hub)
	_host.current = hub
	_host.current_name = "hub"
	hub.enter({"screen": "play", "profile": pr if pr else demo_profile()})
	await wait_frames(3)
	return hub


## Textes visibles sous `n` (Hub2Text, Label).
func _texts(n: Node, out: PackedStringArray) -> PackedStringArray:
	if n is Hub2Text:
		out.append((n as Hub2Text).text)
	elif n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		if c is CanvasItem and not (c as CanvasItem).visible:
			continue
		_texts(c, out)
	return out


func _key(hub: Hub2Screen, physical: int) -> bool:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical as Key
	ev.keycode = physical as Key
	ev.pressed = true
	return hub.handle_event(ev)


# --------------------------------------------------------------------------
# Données
# --------------------------------------------------------------------------

func test_wave_chips_follow_rotation() -> void:
	var chips := Hub2PlayData.wave_chips(WaveRules.default_schedule())
	var got := chips.map(func(c): return [c.round, c.type])
	assert_eq(got, [[5, WaveRules.MEUTE], [10, WaveRules.BRANCARDIER], [15, WaveRules.CHIRURGIEN], [20, WaveRules.INFIRMIERE]],
			"maquette : 5 Meute, 10 Brancardier, 15 Chirurgien, 20 Infirmière")
	assert_eq(Hub2PlayData.wave_name(WaveRules.MEUTE), "Meute")
	assert_eq(Hub2PlayData.wave_color(WaveRules.BRANCARDIER), Color("4D9BFF"))
	# Carte qui n'a que la meute, sans boss : toutes les 4 manches.
	var only := WaveRules.parse({"speciale": {"premiere": 4, "intervalle": 4}, "boss": {"premiere": 0, "intervalle": 0},
		"types_speciaux": [WaveRules.MEUTE]})
	assert_eq(Hub2PlayData.wave_chips(only).map(func(c): return c.round), [4, 8, 12, 16])
	var none := WaveRules.parse({"speciale": {"premiere": 0, "intervalle": 0}, "boss": {"premiere": 0, "intervalle": 0}})
	assert_true(Hub2PlayData.wave_chips(none).is_empty(), "aucune vague spéciale")
	Settings.language = "en"
	assert_eq(Hub2PlayData.wave_name(WaveRules.CHIRURGIEN), "Surgeon")


func test_weekly_card_texts() -> void:
	var ch := WeeklyChallenge.current()
	assert_true(ch != null and ch.key == "2026-W47")
	var d := Hub2PlayData.weekly_card(ch, demo_profile())
	assert_eq(d.kicker, "DÉFI DE LA SEMAINE · S47")
	assert_true(String(d.title).begins_with("Bunker K-7 · "), "carte · modificateurs : %s" % d.title)
	assert_true(String(d.line).begins_with("Évacue à la manche 10 ou plus : +") and String(d.line).ends_with("XP et des échantillons"), d.line)
	assert_true(String(d.left).contains(" j "), "temps restant : %s" % d.left)
	var pr := demo_profile()
	pr.weekly.record("2026-W47", 12, true)
	pr.weekly.mark_rewarded("2026-W47")
	assert_eq(Hub2PlayData.weekly_card(ch, pr).left, "réussi")


func test_addresses_and_ready_line() -> void:
	assert_eq(Hub2PlayData.parse_address("192.168.1.24:7777"), ["192.168.1.24", 7777])
	assert_eq(Hub2PlayData.parse_address(" 10.0.0.5 ", 8000), ["10.0.0.5", 8000], "port par défaut")
	assert_true(Hub2PlayData.parse_address("192.168.1:7777").is_empty(), "IP invalide")
	assert_true(Hub2PlayData.parse_address("192.168.1.24:80").is_empty(), "port invalide")
	assert_true(Hub2PlayData.parse_address("192.168.1.24:abc").is_empty())
	assert_eq(Hub2PlayData.ready_line(3, 3), "3 joueurs prêts sur 3", "maquette")
	assert_eq(Hub2PlayData.ready_line(1, 2), "1 joueur prêt sur 2")
	Settings.language = "en"
	assert_eq(Hub2PlayData.ready_line(1, 2), "1 of 2 players ready")


func test_lobby_cards_ready_and_ping() -> void:
	var players := {
		1: {"name": "Valentin", "slot": 0, "lvl": 23, "start": PackedStringArray(["m1911", "bat"])},
		5: {"name": "Mehdi", "slot": 1, "lvl": 31, "start": PackedStringArray(["bat"]), "ping": 24},
		9: {"name": "Sarah_K", "slot": 2, "lvl": 8, "away": true},
	}
	var cards := Hub2PlayData.lobby_cards(players, null, 5)
	assert_eq(cards.size(), 3)
	assert_eq(cards[0].ping, "—", "hôte : —")
	assert_true(cards[0].host and not cards[1].host)
	assert_eq(cards[1].ping, "24 ms")
	assert_true(cards[1].me)
	assert_true(cards[0].ready and cards[1].ready, "au salon : PRÊT")
	assert_false(cards[2].ready, "pas encore revenu : EN ATTENTE")
	assert_eq(cards[1].color, HudStyle.player_color(1), "couleur de la place")
	assert_eq(Hub2PlayData.status_text(false), "EN ATTENTE")
	assert_eq(Hub2PlayData.lobby_columns(1, 4), 4, "quatre places (maquette)")
	assert_eq(Hub2PlayData.lobby_columns(6, 8), 6)
	# Carte perso de l'hôte : prêt quand elle est reçue et vérifiée.
	var share := MapShare.new()
	share.offer = {"hash": "x"}
	share.states = {5: {"etat": "telechargement", "pct": 40}}
	assert_false(Hub2PlayData.player_ready(5, players[5], share), "téléchargement : en attente")
	share.states[5] = {"etat": "prete"}
	assert_true(Hub2PlayData.player_ready(5, players[5], share))
	share.free()


func test_ping_in_registry() -> void:
	var p := {"name": "A", "slot": 1}
	assert_true(Net.apply_ping(p, 30), "premier relevé")
	assert_false(Net.apply_ping(p, 33), "moins de 5 ms d'écart : rien")
	assert_true(Net.apply_ping(p, 40))
	assert_eq(int(p.ping), 40)
	var clean := Net.clean_players({2: {"name": "B", "slot": 1, "ping": 99999}, 3: {"name": "C", "slot": 2, "ping": "x"}})
	assert_eq(int(clean[2].ping), Net.PING_MAX, "borné")
	assert_false(clean[3].has("ping"), "illisible : ignoré")


func test_loadout_rules() -> void:
	var r := Hub2Equipment.toggled(PackedStringArray(["m1911"]), "m1911")
	assert_true((r[0] as PackedStringArray).is_empty(), "dernière arme : refusé")
	assert_eq(String(r[1]), Hub2Equipment.last_hint())
	r = Hub2Equipment.toggled(PackedStringArray(["m1911"]), "bat")
	assert_eq(r[0], PackedStringArray(["m1911", "bat"]))
	r = Hub2Equipment.toggled(PackedStringArray(["m1911", "bat"]), "m1911")
	assert_eq(r[0], PackedStringArray(["bat"]))
	assert_true((Hub2Equipment.toggled(PackedStringArray(["m1911"]), "mp40")[0] as PackedStringArray).is_empty(), "pas une arme de base")


# --------------------------------------------------------------------------
# Écran
# --------------------------------------------------------------------------

func test_solo_view_mockup_content() -> void:
	var hub := await _open()
	var p: Hub2PlayPanel = hub.panels.play
	assert_eq(p.view, Hub2PlayPanel.SOLO)
	assert_near(hub.veil.spec.color.a, 0.35, 0.001, "voile 0.35 (Partie)")
	assert_eq(p.selected, "bunker_k7", "carte mémorisée choisie")
	assert_true(p.map_buttons.has("bunker_k7"))
	assert_eq(p.preview_title.text, "Bunker K-7", "nom 40 px sur le dégradé")
	assert_eq(p.preview_waves.get_child_count(), 4, "quatre vagues")
	assert_false(p.preview_fun.visible, "carte du jeu : pas POUR LE FUN")
	var t := " | ".join(_texts(p, PackedStringArray()))
	for want in ["SOLO", "COOP", "DÉFI DE LA SEMAINE · S47", "CARTES DU JEU", "1 à 4 joueurs", "CARTES PERSONNALISÉES", "POUR LE FUN",
			"Créées avec l’éditeur. Aucune progression : ni XP, ni butin, ni contrat.", "ÉQUIPEMENT", "X · MODIFIER", "M1912",
			"BATTE", "Emplacement libre", "LANCER", "Meute", "Brancardier", "Chirurgien", "Infirmière"]:
		assert_true(t.contains(want), "« %s » dans : %s" % [want, t])
	Settings.using_pad = true
	assert_eq(Array(hub.prompts.describe()), ["A LANCER", "X ARMES DE DÉPART", "B RETOUR"], "invites de la maquette")
	# Tout tient dans le <main> (380 + 20 + aperçu, bas à 660).
	var main := p.content_rect()
	assert_eq(main, Rect2(28, 96, 1224, 564))
	assert_true(p.launch_button.get_global_rect().end.y <= 660.5, "LANCER au-dessus des invites")
	assert_near(p.launch_button.size.x, 220.0, 0.5, "LANCER : 220 px")


func test_launch_and_weekly() -> void:
	var hub := await _open()
	var p: Hub2PlayPanel = hub.panels.play
	p.weekly_button.pressed.emit()
	assert_eq(p.selected, Hub2PlayPanel.WEEKLY, "défi choisi")
	var t := " | ".join(_texts(p, PackedStringArray()))
	assert_true(t.contains("IMPOSÉ PAR LE DÉFI") and not t.contains("MODIFIER"), "armes imposées : %s" % t)
	p.open_loadout()
	assert_eq(p.modal, null, "défi : pas de choix des armes")
	p.launch_button.pressed.emit()
	assert_eq(_host.launched, 1, "fondu de lancement")
	assert_eq(Settings.last_map, "bunker_k7", "carte mémorisée inchangée")


func test_loadout_picker() -> void:
	var pr := demo_profile()
	pr.set_starting_weapons(PackedStringArray(["m1911"]))
	var hub := await _open(pr)
	var p: Hub2PlayPanel = hub.panels.play
	assert_true(_key(hub, KEY_X), "X : armes de départ")
	assert_true(p.modal != null, "fenêtre ouverte")
	assert_true(" | ".join(_texts(p.modal, PackedStringArray())).contains("ARMES DE DÉPART"))
	assert_false(p.toggle_weapon("m1911"), "dernière arme : refusée")
	assert_true(p.toggle_weapon("bat"), "batte ajoutée")
	assert_eq(hub.profile.starting_weapons, PackedStringArray(["m1911", "bat"]))
	assert_true(p.back(), "B : fenêtre fermée")
	await wait_frames(1)
	assert_eq(p.modal, null)
	var t := " | ".join(_texts(p, PackedStringArray()))
	assert_true(t.contains("M1912") and t.contains("BATTE"), "ÉQUIPEMENT relu : %s" % t)


func test_coop_form_errors() -> void:
	var hub := await _open()
	var p: Hub2PlayPanel = hub.panels.play
	p.coop_tab.pressed.emit()
	assert_eq(p.view, Hub2PlayPanel.COOP)
	p.address_edit.text = "pas une adresse"
	p.join_button.pressed.emit()
	assert_true(p.status_label.text.begins_with("Adresse invalide"), p.status_label.text)
	assert_eq(Net.mode, Net.Mode.NONE)
	p.port_edit.text = "80"
	p.host_button.pressed.emit()
	assert_true(p.status_label.text.begins_with("Port invalide"), p.status_label.text)
	p.solo_tab.pressed.emit()
	assert_eq(p.view, Hub2PlayPanel.SOLO)


func test_host_lobby() -> void:
	var hub := await _open()
	var p: Hub2PlayPanel = hub.panels.play
	p.coop_tab.pressed.emit()
	p.port_edit.text = str(PORT)
	p.name_edit.text = "Valentin"
	p.host_button.pressed.emit()
	await wait_frames(2)
	assert_eq(Net.mode, Net.Mode.HOST, "session hébergée")
	assert_eq(p.view, Hub2PlayPanel.LOBBY, "salon")
	assert_near(hub.veil.spec.color.a, 0.45, 0.001, "voile 0.45 (PartieCoop)")
	var lobby := p.lobby
	assert_eq(Net.lobby_map, "bunker_k7", "carte annoncée")
	assert_eq(lobby.cards.size(), 1)
	assert_eq(lobby.cards_row.get_child_count(), 4, "un joueur et trois places libres")
	var t := " | ".join(_texts(lobby, PackedStringArray()))
	for want in ["Salon de Valentin", "Tu héberges · adresse ", ":%d" % PORT, "COPIER L’ADRESSE", "QUITTER LE SALON", "HÔTE", "23",
			"Niveau 23 · —", "PRÊT", "PLACE LIBRE", "Donne ton adresse à un ami pour qu’il rejoigne le salon.",
			"CARTE · CHOISIE PAR L’HÔTE", "Bunker K-7", "CHANGER DE CARTE", "LANCER", "1 joueur prêt sur 1"]:
		assert_true(t.contains(want), "« %s » dans : %s" % [want, t])
	assert_false(lobby.launch_button.disabled, "seul : LANCER possible")
	Settings.using_pad = true
	hub.refresh_prompts()
	assert_eq(Array(hub.prompts.describe()), ["A LANCER", "Y CHANGER DE CARTE", "B QUITTER LE SALON"], "invites de la maquette")
	# CHANGER DE CARTE : défi de la semaine pour le groupe.
	lobby.open_picker()
	assert_true(p.modal != null)
	lobby._pick(HubMaps.WEEKLY_ROW)
	assert_eq(Net.lobby_challenge, "2026-W47", "défi annoncé")
	assert_eq(lobby.map_label.text, "CARTE · DÉFI DE LA SEMAINE")
	lobby.open_picker()
	lobby._pick("bunker_k7")
	assert_eq(Net.lobby_challenge, "", "autre carte : plus de défi")
	# Changer d'écran ne quitte pas le salon.
	hub.open("lab")
	assert_eq(Net.mode, Net.Mode.HOST, "toujours hébergé")
	hub.open("play")
	# QUITTER LE SALON (B) : deux appuis.
	hub.back()
	assert_eq(Net.mode, Net.Mode.HOST, "premier appui : confirmation")
	assert_eq(Hub2Ui.button_text(lobby.quit_button).text, "CONFIRMER : QUITTER")
	hub.back()
	assert_eq(Net.mode, Net.Mode.NONE, "salon quitté")
	assert_eq(p.view, Hub2PlayPanel.COOP, "retour à la vue COOP")
