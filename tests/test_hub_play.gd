extends TestCase
## Onglet PARTIE du hub (docs/HUB_PLAN.md lot E) : vue SOLO (cartes, aperçu,
## armes de départ, contrats « sur cette carte »), vue COOP (champs, erreurs),
## salon de l'hôte dans l'onglet, fiche de salon (niveau, armes de départ)
## bornée, ÉCRAN TITRE en deux appuis en coop, message « objectif atteint »
## en partie (ContractWatch : une fois par contrat, jamais pour un contrat
## déjà prêt au départ).

const PORT := 17977

var _saved := {}
var _frame: Control
var _host: FakeHost


class FakeHost extends MenuHost:
	var shown: Array = []
	var launched := 0

	func show_screen(screen_name: String, _args := {}, _remember := true) -> void:
		shown.append(screen_name)

	func launch(_then: Callable, _duration := 1.8) -> void:
		launched += 1


func before_each() -> void:
	for k in ["menu_ui_scale", "using_pad", "language", "last_map"]:
		_saved[k] = Settings.get(k)
	Settings.using_pad = false
	Settings.language = "fr"
	Settings.menu_ui_scale = 1.0
	Settings.last_map = "bunker_k7"
	HubContractsView.day_override = HubData.parse_day("2026-11-18")
	HubPlayPanel.last_view = HubPlayPanel.SOLO


func after_each() -> void:
	if is_instance_valid(_frame):
		_frame.queue_free()
	if Net.mode != Net.Mode.NONE:
		Net.leave()
	GameState.reset_to_menu()
	for k in _saved:
		Settings.set(k, _saved[k])
	HubContractsView.day_override = -1
	HubPlayPanel.last_view = HubPlayPanel.SOLO
	HubScreen.last_tab = "lab"
	Net.local_card = {}


## Profil de la maquette (niveau 7 ; 7 crocs, 2 touffes, 5 colliers ; Dents
## de lait prête, Analyse complète : il manque 1 touffe, Urgence au labo :
## il manque 3 colliers).
static func demo_profile() -> PlayerProfile:
	var pr := PlayerProfile.new()
	pr.xp = PlayerProfile.xp_for_level(7) + 2140
	pr.add_samples("dog_fang", 7)
	pr.add_samples("dog_fur", 2)
	pr.add_samples("dog_collar", 5)
	var st := pr.contracts
	st.draw_seed = 918273
	st.rotation = 3
	st.active.append({"id": "pack_analysis", "accepted": 1})
	st.active.append({"id": "lab_emergency", "accepted": 2})
	st.active.append({"id": "dog_fangs_small", "accepted": 3})
	return pr


func _open(tab := "play", pr: PlayerProfile = null) -> HubScreen:
	_frame = Control.new()
	_frame.size = Vector2(1280, 720)
	host.add_child(_frame)
	_host = FakeHost.new()
	_host.size = Vector2(1280, 720)
	_frame.add_child(_host)
	var hub := HubScreen.new()
	hub.menu = _host
	hub.size = Vector2(1280, 720)
	_host.add_child(hub)
	_host.current = hub
	_host.current_name = "hub"
	hub.enter({"tab": tab, "profile": pr if pr else demo_profile()})
	await wait_frames(3)
	return hub


func _texts(n: Node, out: PackedStringArray) -> PackedStringArray:
	if n is Label:
		out.append((n as Label).text)
	elif n is RichTextLabel:
		out.append((n as RichTextLabel).get_parsed_text())
	elif n is HubButton:
		out.append((n as HubButton).label)
	elif n is HubTag:
		out.append((n as HubTag).text)
	for c in n.get_children():
		_texts(c, out)
	return out


func test_solo_view_maps_and_preview() -> void:
	var hub := await _open()
	var p: HubPlayPanel = hub.panels.play
	assert_eq(p.view, HubPlayPanel.SOLO)
	for id in Game.MENU_MAPS:
		assert_true(p.map_rows.has(id), "carte du jeu %s listée" % id)
	assert_eq(p.selected, "bunker_k7", "carte mémorisée choisie")
	assert_true(p.map_rows.bunker_k7.selected, "ligne surlignée")
	assert_true(p.preview.texture != null, "plan de la carte")
	assert_eq(p.map_title.text, "BUNKER K-7")
	var t := " | ".join(_texts(p, PackedStringArray()))
	assert_true(t.contains("Vagues spéciales : meute de chiens, toutes les 5 manches"), "vagues spéciales : %s" % t)
	assert_true(t.contains("Vagues de boss : aucune"), "pas de boss")
	assert_true(t.contains("Porte d'évacuation : oui"), "porte d'évacuation")
	assert_true(t.contains("croc") and t.contains("touffe") and t.contains("collier"), "échantillons de la carte")
	assert_true(t.contains("VOUS PARTEZ AVEC") and t.contains("Pétoire") and t.contains("Batte"), "armes de départ")
	assert_true(t.contains("encore 1 touffe") and t.contains("sur cette carte"), "contrat : il manque 1 touffe, sur cette carte")
	assert_true(t.contains("encore 3 colliers · 12 j"), "contrat daté : 12 j")
	assert_true(t.contains("PRÊT") and t.contains("à remettre au labo"), "contrat prêt")
	assert_eq(p.first_focus(), p.launch_button, "focus sur LANCER LA PARTIE")
	assert_eq(Array(hub.prompts.describe())[0], "Entrée Lancer")


func test_launch_uses_menu_launch_and_remembers_map() -> void:
	var hub := await _open()
	var p: HubPlayPanel = hub.panels.play
	Settings.last_map = "x"
	p.launch_button.pressed.emit()
	assert_eq(_host.launched, 1, "fondu de lancement du menu")
	assert_eq(Settings.last_map, "bunker_k7", "choix mémorisé")
	p.launch_button.pressed.emit()
	assert_eq(_host.launched, 1, "un seul lancement")


func test_modify_opens_loadout_tab() -> void:
	var hub := await _open()
	var p: HubPlayPanel = hub.panels.play
	p.modify_button.pressed.emit()
	assert_eq(hub.tab, "loadout", "MODIFIER : onglet DÉPART")


func test_coop_view_and_field_errors() -> void:
	var hub := await _open()
	var p: HubPlayPanel = hub.panels.play
	p.coop_button.pressed.emit()
	assert_eq(p.view, HubPlayPanel.COOP)
	assert_eq(HubPlayPanel.last_view, HubPlayPanel.COOP, "choix retenu")
	assert_true(p.host_button != null and p.join_button != null and p.ip_edit != null)
	p.ip_edit.text = "300.1.2.3"
	p.join_button.pressed.emit()
	assert_true(p.status_label.text.contains("invalide"), "adresse refusée : %s" % p.status_label.text)
	assert_eq(Net.mode, Net.Mode.NONE, "aucune connexion")
	p.host_port_edit.text = "80"
	p.host_button.pressed.emit()
	assert_true(p.status_label.text.contains("Port invalide"), "port refusé : %s" % p.status_label.text)
	p.show_error("Connexion impossible", "Le serveur est inaccessible.\nVérifiez.")
	assert_true(p.status_label.text.begins_with("Connexion impossible : Le serveur"), "erreur sur place : %s" % p.status_label.text)
	p.solo_button.pressed.emit()
	assert_eq(p.view, HubPlayPanel.SOLO)


func test_host_lobby_in_tab() -> void:
	var hub := await _open()
	var p: HubPlayPanel = hub.panels.play
	p.coop_button.pressed.emit()
	p.host_port_edit.text = str(PORT)
	p.name_edit.text = "Hote"
	p.host_button.pressed.emit()
	await wait_frames(2)
	assert_eq(Net.mode, Net.Mode.HOST, "session hébergée")
	assert_eq(p.view, HubPlayPanel.LOBBY, "salon dans l'onglet")
	var lobby := p.lobby
	assert_true(lobby.is_host, "vue de l'hôte")
	assert_eq(Net.lobby_map, "bunker_k7", "carte annoncée")
	assert_eq(lobby.player_rows.size(), 1, "un joueur")
	assert_true(lobby.player_lines[0].contains("NIV.7") and lobby.player_lines[0].contains("AU SALON"), "ligne : %s" % lobby.player_lines[0])
	assert_eq(int(Net.players[1].lvl), 7, "niveau du profil dans le registre")
	assert_false(lobby.start_button.disabled, "seul : DÉMARRER possible")
	# Changer d'onglet ne quitte pas le salon.
	hub.select_tab("lab")
	assert_eq(Net.mode, Net.Mode.HOST, "toujours hébergé")
	hub.select_tab("play")
	# QUITTER LE SALON : deux appuis, Échap annule.
	lobby.quit_button.pressed.emit()
	assert_eq(Net.mode, Net.Mode.HOST, "premier appui : confirmation")
	assert_true(p.back(), "Échap : confirmation annulée")
	lobby.quit_button.pressed.emit()
	lobby.quit_button.pressed.emit()
	assert_eq(Net.mode, Net.Mode.NONE, "salon quitté")
	assert_eq(p.view, HubPlayPanel.COOP, "retour à la vue COOP")


func test_title_screen_needs_confirmation_online() -> void:
	var hub := await _open()
	Net.host(PORT + 1, 4, "Hote")
	GameState.set_state(GameState.State.LOBBY)
	hub.open_menu()
	hub.hub_menu.title_button.pressed.emit()
	assert_eq(_host.shown, [], "premier appui : confirmation")
	assert_eq(Net.mode, Net.Mode.HOST)
	hub.hub_menu.title_button.pressed.emit()
	assert_eq(_host.shown, ["main"], "ÉCRAN TITRE")
	assert_eq(Net.mode, Net.Mode.NONE, "session quittée")


func test_lobby_card_bounds() -> void:
	var c := Net.clean_card(999, ["m1911", "m1911", "evil", "knife", 4])
	assert_eq(int(c.lvl), PlayerProfile.MAX_LEVEL, "niveau borné")
	assert_eq(Array(c.start), ["m1911", "bat"], "armes de base seulement, sans doublon ; ancien couteau -> batte")
	var players := Net.clean_players({2: {"name": "Jojo", "slot": 1, "lvl": "x", "start": "y", "away": true}, 3: {"name": "Old", "slot": 2}})
	assert_eq(int(players[2].lvl), 1, "niveau illisible : 1")
	assert_true(players[2].away, "état EN RETOUR gardé")
	assert_false(players[3].has("lvl"), "hôte d'avant : pas de fiche")


func test_rhythm_and_missing_texts() -> void:
	assert_eq(HubPlayView.rhythm_text({"premiere": 5, "intervalle": 5}), "toutes les 5 manches")
	assert_eq(HubPlayView.rhythm_text({"premiere": 10, "intervalle": 0}), "à la manche 10")
	assert_eq(HubPlayView.rhythm_text({"premiere": 3, "intervalle": 5}), "dès la manche 3, toutes les 5 manches")
	assert_eq(HubPlayView.rhythm_text({"premiere": 0, "intervalle": 5}), "")
	var pr := demo_profile()
	assert_eq(HubPlayView.missing_line(pr, {"dog_fur": 3}), "encore 1 touffe")
	assert_eq(HubPlayView.missing_line(pr, {"dog_collar": 8}, 12), "encore 3 colliers · 12 j")
	Settings.language = "en"
	assert_eq(HubPlayView.missing_line(pr, {"dog_fur": 3}), "1 tuft of fur to go")


func test_contract_watch_once_per_contract() -> void:
	var pr := demo_profile()
	var d := HubContractsView.data()
	var day := HubContractsView.day_override
	var w := ContractWatch.new()
	host.add_child(w)
	w.setup(pr, d, day)
	assert_true(w.announced.has("dog_fangs_small"), "contrat déjà prêt au départ : jamais annoncé")
	w.check({})
	assert_eq(w.shown.size(), 0, "rien de neuf")
	w.check({"dog_fur": 1})
	assert_eq(w.shown.size(), 1, "Analyse complète : objectif atteint")
	assert_true(w.shown[0].begins_with("CONTRAT « Analyse complète » : OBJECTIF ATTEINT — évacuez"), w.shown[0])
	w.check({"dog_fur": 2})
	assert_eq(w.shown.size(), 1, "une seule fois par contrat")
	w.check({"dog_fur": 2, "dog_collar": 3})
	assert_eq(w.shown.size(), 2, "Urgence au labo : objectif atteint")
	Settings.language = "en"
	assert_true(ContractRules.goal_message(d.contract("lab_emergency")).ends_with("evacuate to keep your samples"))
	w.queue_free()


func test_contract_watch_ignores_expired() -> void:
	var pr := demo_profile()
	var d := HubContractsView.data()
	var after := HubData.parse_day("2026-12-05")
	var got := ContractWatch.new_goals(pr, d, {"dog_collar": 3}, after, {})
	assert_false("lab_emergency" in got, "contrat expiré : pas de message")
