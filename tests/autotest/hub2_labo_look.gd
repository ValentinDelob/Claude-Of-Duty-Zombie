extends AutotestScenario
## @rendu : écrans LABO, LABO › CONTRATS et LABO › ÉCHANGES du hub v2
## (maquettes docs/hub_v2/Main.dc.html, Contrats.dc.html, Echanges.dc.html)
## EN COURS DE DÉVELOPPEMENT : captures à comparer aux maquettes.
##   - *_mockup : même contenu que les maquettes (catalogue, profil et date
##     imposés : HubContractsView.data_override, StoryRules.data_override) ;
##   - données réelles (story.json, contracts.json, exchanges.json) :
##     histoire en cours, ACCEPTER au clavier, REMETTRE (fenêtre de remise),
##     ABANDONNER en deux appuis (X), ÉCHANGER en deux appuis, filtre (Tab) ;
##   - anglais, TAILLE DES MENUS 130 % (rien ne sort de l'écran).
## Captures : tests/_out/shots/hub2_labo_look_<écran>_<hauteur>.png.
## Scénario retiré (ou réduit aux vérifications logiques) une fois ces écrans
## validés (captures seulement pour un ajout en cours).

var menu: MainMenu
var hub: Hub2Screen
var _saved := {}


## Catalogue de la maquette Contrats.dc.html / Echanges.dc.html (XP de base
## choisie pour donner les valeurs de la maquette au niveau 23 : 900, 1 900).
const MOCK_CONTRACTS := {"format": "hub_contracts", "version": 1, "rules": {"lifetime_days": 7}, "contracts": [
	{"id": "fang_collection", "title": {"fr": "Crocs de collection", "en": "Collector's Fangs"},
		"text": {"fr": "Des crocs, beaucoup.", "en": "Fangs, lots."}, "samples": {"dog_fang": 6}, "xp": 625,
		"reward": {"kind": "part", "quality": "fine"}},
	{"id": "night_guard", "title": {"fr": "Garde de nuit", "en": "Night Watch"},
		"text": {"fr": "Sa voix, son badge.", "en": "Her voice, her badge."}, "samples": {"nurse_vocal_cords": 2, "nurse_badge": 1},
		"xp": 1320, "reward": {"kind": "weapon", "weapon": "spectre", "rarity": "epic"}},
	{"id": "leash_collar", "title": {"fr": "Laisse et collier", "en": "Leash and Collar"},
		"text": {"fr": "Promenade.", "en": "Walkies."}, "samples": {"dog_collar": 3, "dog_fur": 4}, "xp": 900,
		"reward": {"kind": "weapon", "weapon": "any", "rarity": "rare"}},
	{"id": "used_syringes", "title": {"fr": "Seringues usagées", "en": "Used Syringes"},
		"text": {"fr": "Piquant.", "en": "Prickly."}, "samples": {"nurse_syringe": 3}, "xp": 900,
		"reward": {"kind": "part", "quality": "fine"}},
	{"id": "staff_register", "title": {"fr": "Registre du personnel", "en": "Staff Register"},
		"text": {"fr": "Qui était là ?", "en": "Who was there?"}, "samples": {"nurse_badge": 2, "brancard_bracelet": 2}, "xp": 2000,
		"reward": {"kind": "weapon", "weapon": "any", "rarity": "legendary"}},
]}
const MOCK_EXCHANGES := {"format": "hub_exchanges", "version": 1, "exchanges": [
	{"id": "shoulder_strap", "title": {"fr": "Bandoulière en cuir", "en": "Leather Shoulder Strap"},
		"samples": {"brancard_strap": 4}, "reward": {"kind": "part", "mods": {"reload": 0.2}}, "min_level": 5},
	{"id": "trip_fang", "title": {"fr": "Croc-en-jambe", "en": "Tripping Fang"},
		"samples": {"dog_fang": 5, "dog_fur": 3}, "reward": {"kind": "weapon", "weapon": "stakeout", "rarity": "rare"}, "min_level": 3},
	{"id": "tagged_sights", "title": {"fr": "Mire étiquetée", "en": "Tagged Sights"},
		"samples": {"brancard_bracelet": 3, "brancard_strap": 2}, "reward": {"kind": "part", "mods": {"accuracy": 0.2, "damage": 0.05}},
		"min_level": 6},
	{"id": "choke_collar", "title": {"fr": "Collier étrangleur", "en": "Choke Collar"},
		"samples": {"dog_collar": 4, "dog_fang": 6}, "reward": {"kind": "weapon", "weapon": "mp40", "rarity": "epic"}, "min_level": 12},
	{"id": "taut_cords", "title": {"fr": "Cordes tendues", "en": "Taut Cords"},
		"samples": {"nurse_vocal_cords": 3, "nurse_syringe": 1}, "reward": {"kind": "part", "mods": {"fire_rate": 0.15, "mag": 0.1}},
		"min_level": 11},
	{"id": "giant_scalpel", "title": {"fr": "Bistouri géant", "en": "Giant Scalpel"},
		"samples": {"nurse_vocal_cords": 2, "brancard_strap": 4}, "reward": {"kind": "weapon", "weapon": "galil", "rarity": "legendary"},
		"min_level": 25},
]}
## Jour de la maquette (18 novembre 2026).
const MOCK_DAY := "2026-11-18"


## Profil de la maquette : niveau 23 (64 %), histoire au chapitre 2, étape 3
## (Sangles en série), deux contrats temporaires en cours, trois
## propositions.
static func mock_profile(day: int) -> PlayerProfile:
	var pr := PlayerProfile.new()
	pr.xp = PlayerProfile.xp_for_level(23) + int(PlayerProfile.xp_to_next(23) * 0.643)
	for id in ["ch1_fangs", "ch1_fur", "ch1_collars", "ch1_pack_leader", "ch2_patient_zero", "ch2_trolley"]:
		pr.story.mark_done(id)
	pr.contracts.rotation = 1
	pr.contracts.active.append({"id": "fang_collection", "accepted": 1, "until": day + 2})
	pr.contracts.active.append({"id": "night_guard", "accepted": 1, "until": day + 5})
	pr.contracts.offers.append({"id": "leash_collar", "since": 1, "until": day + 4})
	pr.contracts.offers.append({"id": "used_syringes", "since": 1, "until": day + 3})
	pr.contracts.offers.append({"id": "staff_register", "since": 1, "until": day + 7})
	return pr


## Histoire de la maquette : l'étape 3 donne la GUÊPE rare et 1 650 XP au
## niveau 23.
static func mock_story() -> StoryData:
	var sd := StoryData.load_file(StoryData.PATH)
	var s := sd.step("ch2_straps")
	s.xp = 1146
	s.reward = {"kind": "weapon", "weapon": "cz75", "rarity": "rare"}
	return sd


func run() -> void:
	timeout_sec = 180
	await until(func(): return tree().current_scene != null and tree().current_scene.name == "MainMenu", 5.0, "menu principal")
	menu = tree().current_scene
	await until(_settled, 5.0, "menu titre affiché")
	for k in ["player_name", "hub_v2", "language", "menu_ui_scale", "using_pad"]:
		_saved[k] = Settings.get(k)
	Settings.player_name = "Valentin"
	Settings.hub_v2 = true
	var day := HubData.parse_day(MOCK_DAY)
	HubContractsView.day_override = day
	HubContractsView.data_override = HubData.from_texts(JSON.stringify(MOCK_CONTRACTS, "", false),
			JSON.stringify(MOCK_EXCHANGES, "", false))
	at.check(HubContractsView.data_override.warnings.is_empty(), "catalogue de la maquette valide %s" % HubContractsView.data_override.warnings)
	StoryRules.data_override = mock_story()
	# --- LABO (Main.dc.html) ---------------------------------------------------
	var pr := mock_profile(day)
	_samples(pr, {"dog_fang": 5, "dog_fur": 7, "dog_collar": 3, "brancard_strap": 4, "brancard_bracelet": 2, "nurse_vocal_cords": 1})
	ProfileStore.save_profile(pr)
	await press("ui_accept")
	at.check(menu.current_name == "hub2", "JOUER : hub v2 (%s)" % menu.current_name)
	await until(_settled, 3.0, "hub v2 affiché")
	hub = menu.current
	var lab: Hub2LabPanel = hub.panels.lab
	at.check(lab.rings.running, "un contrat prêt : anneaux pulsés")
	at.check(lab.ready_tag.text == "1 TERMINÉ", "« 1 TERMINÉ » (%s)" % lab.ready_tag.text)
	at.check(lab.story_label.text == "Histoire · chapitre 2, étape 3 sur 5", "avancement de l'histoire (%s)" % lab.story_label.text)
	at.check(lab.exchanges_label.text == "2 possibles", "2 échanges possibles (%s)" % lab.exchanges_label.text)
	at.check(lab.line_text.begins_with("Vous avez rapporté les sangles"), "réplique de l'étape prête (%s)" % lab.line_text)
	await _mockup_frame()
	await shot("lab_mockup")
	# --- CONTRATS (Contrats.dc.html) -------------------------------------------
	_samples(hub.profile, {"dog_fang": 4, "nurse_vocal_cords": 1, "brancard_strap": 3})
	hub.save_profile()
	await press("ui_accept")
	at.check(hub.current_id == "contracts", "A sur CONTRATS : sous-écran (%s)" % hub.current_id)
	await seconds(0.4)
	var cp: Hub2ContractsPanel = hub.panels.contracts
	at.check(cp.chapter_text == "HISTOIRE · CHAPITRE 2", "chapitre (%s)" % cp.chapter_text)
	at.check(cp.step_label_text == "ÉTAPE 3 SUR 5", "étape (%s)" % cp.step_label_text)
	at.check(cp.unlock_text == "Débloque l’étape 4 : « Fiches patients »", "étape débloquée (%s)" % cp.unlock_text)
	at.check(cp.count_text == "2 / 3 en cours", "contrats en cours (%s)" % cp.count_text)
	at.check(_focused() == cp.hand_in_button and cp.hand_in_rings.running, "focus sur REMETTRE, anneaux pulsés")
	at.check(cp.story_tiles.size() == 2 and cp.story_tiles[0].spec.name == "GUÊPE" and cp.story_tiles[1].spec.cap == "+1 650",
			"tuiles : GUÊPE et +1 650 (%s)" % [cp.story_tiles.map(func(t): return t.spec.cap)])
	var d := hub.prompts.describe()
	at.check(Array(d) == ["A REMETTRE", "X ABANDONNER", "B LABO"], "invites (%s)" % ", ".join(d))
	await shot("contracts_mockup")
	# Infobulles (survol) : arme de l'histoire, arme d'un contrat temporaire.
	await hover(cp.story_tiles[0])
	at.check(cp.tooltip.visible and cp.tooltip.name_text.text == "GUÊPE", "infobulle de la GUÊPE")
	await shot("contracts_tooltip_story")
	var temp_tile: Hub2RewardTile = _tiles_of(cp.temp_cards["night_guard"])[0]
	await hover(temp_tile)
	at.check(cp.tooltip.visible and cp.tooltip.name_text.text == "FEU FOLLET", "infobulle du FEU FOLLET")
	await shot("contracts_tooltip_temp")
	await hover_end()
	# --- ÉCHANGES (Echanges.dc.html) -------------------------------------------
	_samples(hub.profile, {"dog_fang": 12, "dog_fur": 7, "dog_collar": 3, "brancard_strap": 4, "brancard_bracelet": 2,
		"nurse_vocal_cords": 1})
	hub.save_profile()
	hub.open("exchanges")
	await seconds(0.4)
	var xp_: Hub2ExchangesPanel = hub.panels.exchanges
	at.check(xp_.cards.size() == 6, "6 échanges (%d)" % xp_.cards.size())
	at.check(_focused() == xp_.cards["shoulder_strap"], "focus sur la Bandoulière en cuir")
	d = hub.prompts.describe()
	at.check(Array(d) == ["A ÉCHANGER", "Y FILTRER", "B RETOUR"], "invites (%s)" % ", ".join(d))
	await shot("exchanges_mockup")
	_mockup_frame_end()
	# --- Données réelles -------------------------------------------------------
	HubContractsView.data_override = null
	HubContractsView.day_override = -1
	StoryRules.data_override = null
	pr = PlayerProfile.new()
	pr.xp = PlayerProfile.xp_for_level(7) + 400
	for id in ["ch1_fangs", "ch1_fur", "ch1_collars", "ch1_pack_leader", "ch2_patient_zero", "ch2_trolley"]:
		pr.story.mark_done(id)
	_samples(pr, {"dog_fang": 9, "dog_fur": 5, "dog_collar": 4, "brancard_strap": 1, "brancard_bracelet": 3})
	ProfileStore.save_profile(pr)
	menu.show_screen("hub2", {"screen": "contracts"})
	await until(_settled, 3.0, "hub v2 (données réelles)")
	hub = menu.current
	cp = hub.panels.contracts
	at.check(cp.offer_buttons.size() == 5, "tableau rempli à la première ouverture (%d)" % cp.offer_buttons.size())
	at.check(cp.hand_in_button.disabled, "étape en cours : REMETTRE grisé")
	# ACCEPTER au clavier (Entrée sur la proposition qui a le focus).
	var first_offer: Control = _focused()
	at.check(cp.offer_buttons.values().has(first_offer), "focus sur une proposition (rien n'est prêt)")
	await press("ui_accept")
	await seconds(0.2)
	cp = hub.panels.contracts
	at.check(cp.temp_cards.size() == 1, "proposition acceptée (%d en cours)" % cp.temp_cards.size())
	await seconds(0.3)
	await shot("contracts")
	# ABANDONNER en deux appuis (X).
	var tid: String = cp.temp_cards.keys()[0]
	cp.temp_cards[tid].grab_focus()
	await key(KEY_X)
	at.check(cp.confirm_id == tid, "X : confirmation demandée")
	await shot("contracts_abandon")
	await key(KEY_X)
	cp = hub.panels.contracts
	at.check(cp.temp_cards.is_empty(), "X encore : contrat abandonné")
	# REMETTRE l'étape : fenêtre de remise.
	hub.profile.add_samples("brancard_strap", 2)
	hub.save_profile()
	await frames(2)  # focus remis après la reconstruction
	cp = hub.panels.contracts
	at.check(not cp.hand_in_button.disabled and cp.hand_in_rings.running, "étape prête : REMETTRE et anneaux")
	cp.hand_in_button.grab_focus()
	await frames(2)
	await press("ui_accept")
	await seconds(0.4)
	at.check(cp.popup_open(), "fenêtre de remise")
	at.check(hub.profile.story.is_done("ch2_straps"), "étape remise")
	await shot("contracts_popup")
	await press("ui_cancel")
	await seconds(0.2)
	cp = hub.panels.contracts
	at.check(not cp.popup_open() and cp.step_label_text == "ÉTAPE 4 SUR 5", "étape suivante (%s)" % cp.step_label_text)
	await shot("contracts_next")
	# ÉCHANGES : deux appuis, filtre.
	hub.open("exchanges")
	await seconds(0.3)
	xp_ = hub.panels.exchanges
	await shot("exchanges")
	var fid := ""
	for id in xp_.cards:
		if xp_.cards[id].get_meta("can"):
			fid = id
			break
	at.check(fid != "", "un échange possible")
	xp_.cards[fid].grab_focus()
	await frames(2)
	await press("ui_accept")
	at.check(xp_.confirm_id == fid, "premier appui : CONFIRMER")
	await shot("exchanges_confirm")
	await press("ui_accept")
	await seconds(0.3)
	at.check(xp_.popup_open(), "deuxième appui : échange fait")
	await shot("exchanges_popup")
	await press("ui_cancel")
	await key(KEY_TAB)
	xp_ = hub.panels.exchanges
	at.check(xp_.only_tradable, "Tab : POSSIBLES MAINTENANT")
	await seconds(0.2)
	await shot("exchanges_filter")
	await key(KEY_TAB)
	hub.open("lab")
	await seconds(0.4)
	await shot("lab")
	# --- TAILLE DES MENUS 130 % ------------------------------------------------
	Settings.menu_ui_scale = 1.3
	await frames(4)
	hub = menu.current
	for id in ["lab", "contracts", "exchanges"]:
		hub.open(id)
		await seconds(0.4)
		_check_inside(hub, "130 %% %s" % id)
		await shot(id + "_130")
	Settings.menu_ui_scale = 1.0
	await frames(3)
	# --- Anglais ---------------------------------------------------------------
	Settings.language = "en"
	for id in ["lab", "contracts", "exchanges"]:
		menu.show_screen("hub2", {"screen": id})
		await until(_settled, 3.0, "hub v2 en anglais")
		hub = menu.current
		await seconds(0.4)
		_check_inside(hub, "EN %s" % id)
		await shot(id + "_en")
	for k in _saved:
		Settings.set(k, _saved[k])
	ProfileStore.reset()


static func _samples(pr: PlayerProfile, s: Dictionary) -> void:
	pr.samples.clear()
	for k in s:
		pr.samples[k] = int(s[k])


## Cadre comme la maquette : XP 8 420 / 13 100, pastilles, invites manette.
func _mockup_frame() -> void:
	var tb := hub.top_bar
	tb.xp_in = 8420
	tb.xp_need = 13100
	for id in ["lab", "arsenal", "codex"]:
		tb.set_badge(id, true)
	tb._layout()
	Settings.using_pad = true
	hub.refresh_prompts()
	hub.panels.lab.rings.t = 0.5
	await seconds(0.6)


func _mockup_frame_end() -> void:
	Settings.using_pad = false
	hub.set_hint("")
	hub.top_bar.show_profile(hub.profile)
	hub.refresh_badges()
	hub.top_bar._layout()


func _tiles_of(n: Node) -> Array:
	var out := []
	for c in n.get_children():
		if c is Hub2RewardTile:
			out.append(c)
		out.append_array(_tiles_of(c))
	return out


func _check_inside(root: Control, what: String) -> void:
	var screen := Rect2(Vector2.ZERO, root.get_viewport_rect().size).grow(1.0)
	var bad := []
	_scan_inside(root, screen, bad)
	at.check(bad.is_empty(), "%s : rien ne sort de l'écran %s" % [what, str(bad.slice(0, 4))])


## Contrôles visibles hors de l'écran (le contenu d'un défilement est coupé
## à sa fenêtre : seul le ScrollContainer compte).
func _scan_inside(n: Node, screen: Rect2, bad: Array) -> void:
	if n is Control:
		var c := n as Control
		if not c.is_visible_in_tree():
			return
		if not (c is Hub2PulseRings) and not screen.encloses(c.get_global_rect()):
			bad.append("%s %s" % [c.name, c.get_global_rect()])
		if c is ScrollContainer:
			return
	for ch in n.get_children():
		_scan_inside(ch, screen, bad)


func shot(n: String) -> void:
	await at.screenshot("%s_%d" % [n, DisplayServer.window_get_size().y])


func _settled() -> bool:
	return is_instance_valid(menu) and menu.current != null and menu.current.modulate.a >= 0.999 \
		and menu._fade_amount < 0.001


func _focused() -> Control:
	return at.get_viewport().gui_get_focus_owner()


func press(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await frames(3)


func key(physical: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical as Key
	ev.keycode = physical as Key
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	await frames(3)


## Souris sur le contrôle `c` (survol réel : infobulle).
func hover(c: Control) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = c.get_global_rect().get_center()
	ev.global_position = ev.position
	at.get_viewport().push_input(ev, true)
	await frames(3)
	await seconds(0.2)


func hover_end() -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = Vector2(4, 700)
	ev.global_position = ev.position
	at.get_viewport().push_input(ev, true)
	await frames(3)
