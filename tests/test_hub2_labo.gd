extends TestCase
## Écrans LABO, LABO › CONTRATS et LABO › ÉCHANGES du hub v2 (maquettes
## docs/hub_v2/Main.dc.html, Contrats.dc.html, Echanges.dc.html) branchés sur
## les vraies règles : anneaux et « 1 TERMINÉ » seulement quand un contrat est
## prêt, avancement de l'histoire, échanges possibles ; étape d'histoire
## (REMETTRE grisé / prêt, fenêtre de remise, étape suivante) ; contrats
## temporaires (ACCEPTER, ABANDONNER en deux appuis au clavier, remise) ;
## infobulle des tuiles au focus ; échange en deux appuis, filtre ; taille
## 130 % sans débordement ; anglais. Catalogue et histoire de test, profil
## en mémoire (aucune écriture), sans MainMenu (hôte minimal).

var _saved := {}
var _frame: Control

const CONTRACTS := {"format": "hub_contracts", "version": 1, "rules": {"offers": 3, "active_max": 2, "lifetime_days": 7},
	"contracts": [
		{"id": "t_fangs", "title": {"fr": "Crocs de collection", "en": "Collector's Fangs"}, "text": {"fr": "Des crocs.", "en": "Fangs."},
			"samples": {"dog_fang": 3}, "xp": 600, "reward": {"kind": "part", "quality": "fine"}},
		{"id": "t_fur", "title": {"fr": "Pelage", "en": "Coat"}, "text": {"fr": "Des poils.", "en": "Fur."},
			"samples": {"dog_fur": 2}, "xp": 500, "reward": {"kind": "weapon", "weapon": "any", "rarity": "rare"}},
		{"id": "t_collar", "title": {"fr": "Colliers", "en": "Collars"}, "text": {"fr": "Des colliers.", "en": "Collars."},
			"samples": {"dog_collar": 2}, "xp": 400, "reward": {"kind": "none"}},
	]}
const EXCHANGES := {"format": "hub_exchanges", "version": 1, "exchanges": [
	{"id": "x_sling", "title": {"fr": "Bandoulière en cuir", "en": "Leather Sling"}, "samples": {"brancard_strap": 4},
		"reward": {"kind": "part", "mods": {"reload": 0.2}}, "min_level": 1},
	{"id": "x_gun", "title": {"fr": "Croc-en-jambe", "en": "Tripping Fang"}, "samples": {"dog_fang": 5, "dog_fur": 3},
		"reward": {"kind": "weapon", "weapon": "stakeout", "rarity": "rare"}, "min_level": 1},
	{"id": "x_high", "title": {"fr": "Bistouri géant", "en": "Giant Scalpel"}, "samples": {"dog_fang": 1},
		"reward": {"kind": "weapon", "weapon": "galil", "rarity": "legendary"}, "min_level": 40},
]}
const STORY := {"format": "hub_story", "version": 1, "chapters": [
	{"id": "c1", "title": {"fr": "La meute", "en": "The Pack"}, "steps": [
		{"id": "s1", "short": {"fr": "Crocs", "en": "Fangs"}, "title": {"fr": "Premiers crocs", "en": "First Fangs"},
			"text": {"fr": "Rapportez des crocs.", "en": "Bring fangs."}, "ready": {"fr": "Prêt !", "en": "Ready!"},
			"samples": {"dog_fang": 2}, "xp": 300, "reward": {"kind": "weapon", "weapon": "cz75", "rarity": "rare"}},
		{"id": "s2", "short": {"fr": "Poils", "en": "Fur"}, "title": {"fr": "Poil à gratter", "en": "Itching Powder"},
			"text": {"fr": "Des poils.", "en": "Fur."}, "samples": {"dog_fur": 1}, "xp": 300, "reward": {"kind": "part", "quality": "fine"},
			"min_level": 2},
	]},
]}


class FakeHost extends MenuHost:
	func show_screen(_screen_name: String, _args := {}, _remember := true) -> void:
		pass


func before_each() -> void:
	Input.flush_buffered_events()
	for k in ["menu_ui_scale", "using_pad", "language", "player_name"]:
		_saved[k] = Settings.get(k)
	Settings.using_pad = false
	Settings.language = "fr"
	Settings.menu_ui_scale = 1.0
	Settings.player_name = "Valentin"
	HubContractsView.day_override = HubData.parse_day("2026-11-18")
	HubContractsView.data_override = HubData.from_texts(JSON.stringify(CONTRACTS, "", false), JSON.stringify(EXCHANGES, "", false))
	StoryRules.data_override = StoryData.from_text(JSON.stringify(STORY, "", false))


func after_each() -> void:
	if is_instance_valid(_frame):
		_frame.queue_free()
	for k in _saved:
		Settings.set(k, _saved[k])
	HubContractsView.day_override = -1
	HubContractsView.data_override = null
	StoryRules.data_override = null
	Hub2Screen.last_screen = "lab"


func _profile(lvl := 5) -> PlayerProfile:
	var pr := PlayerProfile.new()
	pr.xp = PlayerProfile.xp_for_level(lvl) + 10
	return pr


func _open(screen: String, pr: PlayerProfile) -> Hub2Screen:
	_frame = Control.new()
	_frame.size = Vector2(1280, 720)
	host.add_child(_frame)
	var h := FakeHost.new()
	h.size = Vector2(1280, 720)
	_frame.add_child(h)
	var hub := Hub2Screen.new()
	hub.menu = h
	hub.size = Vector2(1280, 720)
	h.add_child(hub)
	h.current = hub
	h.current_name = "hub"
	hub.enter({"screen": screen, "profile": pr})
	await wait_frames(3)
	return hub


func _key(hub: Hub2Screen, physical: Key) -> bool:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical
	ev.pressed = true
	return hub.handle_event(ev)


func _outside(n: Node, screen: Rect2, bad: Array) -> void:
	if n is Control:
		var c := n as Control
		if not c.is_visible_in_tree():
			return
		if not (c is Hub2PulseRings) and not screen.encloses(c.get_global_rect()):
			bad.append("%s %s" % [c.name, c.get_global_rect()])
		if c is ScrollContainer:
			return
	for ch in n.get_children():
		_outside(ch, screen, bad)


# --- LABO -------------------------------------------------------------------------

func test_lab_rings_only_when_ready() -> void:
	var pr := _profile()
	pr.add_samples("brancard_strap", 4)
	var hub := await _open("lab", pr)
	var lab: Hub2LabPanel = hub.panels.lab
	assert_false(lab.rings.running, "rien de prêt : pas d'anneaux")
	assert_false(lab.ready_box.visible, "pas de « TERMINÉ »")
	assert_true(lab.active_label.visible)
	assert_eq(lab.active_label.text, "1 en cours", "l'étape d'histoire en cours")
	assert_eq(lab.story_label.text, "Histoire · chapitre 1, étape 1 sur 2")
	assert_eq(lab.exchanges_label.text, "1 possible", "Bandoulière seule possible")
	assert_false(lab.badge())
	assert_eq(lab.line_text, "Vous revoilà, entier en plus. Je note ça dans le registre des miracles.")
	assert_true(lab.hero.texture != null and lab.hero.size.y <= 640.0, "Dr Brown en grand")
	assert_eq(lab.hero.position.x, 70.0, "left 70")
	assert_near(lab.hero.position.y + lab.hero.size.y, 714.0, 0.5, "bottom 6")
	# L'étape devient prête.
	hub.profile.add_samples("dog_fang", 2)
	hub.save_profile()
	assert_true(lab.rings.running, "étape prête : anneaux pulsés")
	assert_true(lab.ready_box.visible and not lab.active_label.visible)
	assert_eq(lab.ready_tag.text, "1 TERMINÉ")
	assert_eq(lab.ready_sub.text, "récompense à récupérer")
	assert_eq(lab.line_text, "Prêt !", "réplique « prête » de l'étape")
	assert_true(lab.badge())
	assert_true(hub.top_bar.badges.get("lab", false), "pastille de l'onglet LABO")
	assert_eq(lab.contracts_button.hint, "Un contrat est terminé : la récompense t’attend au bureau des contrats.")
	Settings.using_pad = true
	assert_eq(Array(hub.prompts.describe()), ["A OUVRIR", "LB RB ONGLETS", "START JOUER"])
	lab.exchanges_button.pressed.emit()
	assert_eq(hub.current_id, "exchanges")


# --- CONTRATS : histoire --------------------------------------------------------

func test_story_card_and_hand_in() -> void:
	var pr := _profile()
	pr.add_samples("dog_fang", 1)
	var hub := await _open("contracts", pr)
	var cp: Hub2ContractsPanel = hub.panels.contracts
	assert_eq(cp.chapter_text, "HISTOIRE · CHAPITRE 1")
	assert_eq(cp.step_label_text, "ÉTAPE 1 SUR 2")
	assert_eq(cp.unlock_text, "Débloque l’étape 2 : « Poil à gratter »")
	assert_true(cp.hand_in_button.disabled, "échantillons manquants : REMETTRE grisé")
	assert_false(cp.hand_in_rings.running)
	assert_eq(cp.story_tiles.size(), 2, "arme et XP")
	assert_eq(cp.story_tiles[0].spec.name, "GUÊPE", "aperçu exact de l'arme")
	assert_eq(cp.story_tiles[0].spec.kind, "ARME RARE · PISTOLET · NIV. 8", "niveau de base de la GUÊPE (8)")
	assert_eq(cp.story_tiles[1].spec.cap, "+" + Hub2Style.num(StoryRules.xp_for(StoryRules.data().step("s1"), 5)))
	hub.profile.add_samples("dog_fang", 2)
	hub.save_profile()
	assert_false(cp.hand_in_button.disabled, "prête")
	assert_true(cp.hand_in_rings.running, "anneaux pulsés sur REMETTRE")
	assert_true(cp.first_focus() == cp.hand_in_button, "focus sur REMETTRE")
	cp.hand_in_button.pressed.emit()
	assert_true(cp.popup_open(), "fenêtre de remise")
	assert_true(hub.profile.story.is_done("s1"))
	assert_eq(hub.profile.sample_count("dog_fang"), 1, "consommation exacte (3 − 2)")
	assert_eq(hub.profile.weapons.size(), 1)
	assert_eq(hub.profile.weapons[0].weapon_id, "cz75", "l'arme montrée")
	assert_eq(cp.popup.head_text, "HISTOIRE · ÉTAPE 1 TERMINÉE")
	assert_eq(cp.popup.unlock_text, "Étape 2 débloquée : « Poil à gratter »")
	assert_eq(cp.popup.title_text, "Premiers crocs")
	Settings.using_pad = true
	assert_eq(Array(hub.prompts.describe()), ["A VOIR DANS L’ARSENAL", "B FERMER"])
	assert_true(_key(hub, KEY_E), "onglets bloqués sous la fenêtre (consommé)")
	assert_eq(hub.current_id, "contracts")
	hub.back()
	assert_false(cp.popup_open(), "B : fermée")
	assert_eq(hub.current_id, "contracts", "toujours sur CONTRATS")
	assert_eq(cp.step_label_text, "ÉTAPE 2 SUR 2", "étape suivante")


func test_story_level_lock() -> void:
	var pr := _profile(1)
	pr.story.mark_done("s1")
	pr.add_samples("dog_fur", 3)
	var hub := await _open("contracts", pr)
	var cp: Hub2ContractsPanel = hub.panels.contracts
	assert_true(cp.hand_in_button.disabled, "niveau 2 requis")
	assert_eq(cp.hand_in_button.hint, "Dr Brown attend que vous soyez niveau 2 pour cette étape.")
	assert_eq(cp.unlock_text, "Dernière étape de l’histoire")


# --- CONTRATS : temporaires -----------------------------------------------------

func test_temporary_accept_abandon_deliver() -> void:
	var pr := _profile()
	var hub := await _open("contracts", pr)
	var cp: Hub2ContractsPanel = hub.panels.contracts
	assert_eq(cp.offer_buttons.size(), 3, "tableau rempli à l'ouverture")
	assert_eq(cp.count_text, "0 / 2 en cours")
	cp.accept("t_fangs")
	assert_true(cp.temp_cards.has("t_fangs"), "acceptée")
	assert_eq(cp.count_text, "1 / 2 en cours")
	var card: Hub2Button = cp.temp_cards["t_fangs"]
	assert_eq((card.get_meta("time") as Hub2Text).text, "encore 6 j", "durée de vie de 7 jours")
	cp.accept("t_fur")
	assert_true(cp.offer_buttons["t_collar"].disabled, "2 contrats en cours au maximum : ACCEPTER grisé")
	# ABANDONNER : deux appuis sur X (après le focus remis par l'écran).
	await wait_frames(1)
	card = cp.temp_cards["t_fangs"]
	card.grab_focus()
	await wait_frames(1)
	assert_true(_key(hub, KEY_X), "X consommé")
	assert_eq(cp.confirm_id, "t_fangs", "premier appui : confirmation")
	assert_eq((card.get_meta("time") as Hub2Text).text, "ABANDONNER ?")
	Settings.using_pad = true
	assert_eq(Array(hub.prompts.describe()), ["X CONFIRMER L’ABANDON", "B ANNULER"])
	hub.back()
	assert_eq(cp.confirm_id, "", "B : annulé")
	assert_true(cp.temp_cards.has("t_fangs"))
	cp.temp_cards["t_fangs"].grab_focus()
	await wait_frames(1)
	_key(hub, KEY_X)
	_key(hub, KEY_X)
	assert_false(cp.temp_cards.has("t_fangs"), "deuxième appui : abandonné")
	assert_false(hub.profile.contracts.is_active("t_fangs"))
	# Remise d'un contrat temporaire prêt.
	hub.profile.add_samples("dog_fur", 2)
	hub.save_profile()
	assert_true(cp.temp_cards["t_fur"].get_meta("ready"), "prêt")
	assert_eq(Hub2LabKit.ready_total(hub.profile), 1)
	cp.temp_cards["t_fur"].pressed.emit()
	assert_true(cp.popup_open(), "fenêtre « contrat remis »")
	assert_eq(cp.popup.head_text, "CONTRAT REMIS")
	assert_eq(hub.profile.sample_count("dog_fur"), 0)
	assert_eq(hub.profile.contracts.done_count("t_fur"), 1)
	cp.popup.close()


## Liens entre écrans : VOIR DANS L'ARSENAL (fenêtre de remise) ouvre
## l'ARSENAL sur l'objet reçu ; A sur un échantillon de l'INVENTAIRE ouvre
## le contrat qui le demande (sinon l'échange), carte choisie.
func test_cross_screen_links() -> void:
	var pr := _profile()
	pr.add_samples("dog_fang", 1)
	pr.add_samples("brancard_strap", 1)
	var hub := await _open("contracts", pr)
	var cp: Hub2ContractsPanel = hub.panels.contracts
	cp.accept("t_fangs")
	cp.accept("t_fur")
	# INVENTAIRE -> CONTRATS : le contrat qui demande des crocs.
	hub.open("inventory")
	await wait_frames(1)
	var inv: Hub2InventoryPanel = hub.panels.inventory
	inv.open_request("dog_fang")
	await wait_frames(2)
	assert_eq(hub.current_id, "contracts", "A sur les crocs : CONTRATS")
	assert_eq(hub.get_viewport().gui_get_focus_owner(), cp.temp_cards["t_fangs"], "contrat des crocs choisi")
	# INVENTAIRE -> ÉCHANGES : aucun contrat ne demande la sangle.
	hub.open("inventory")
	await wait_frames(1)
	inv.open_request("brancard_strap")
	await wait_frames(2)
	assert_eq(hub.current_id, "exchanges", "A sur la sangle : ÉCHANGES")
	var xp_: Hub2ExchangesPanel = hub.panels.exchanges
	assert_eq(hub.get_viewport().gui_get_focus_owner(), xp_.cards["x_sling"], "échange de la sangle choisi")
	assert_false(xp_.select_item("pas_un_echange"), "échange inconnu : rien")
	# Remise d'un contrat qui donne une arme, puis VOIR DANS L'ARSENAL.
	hub.open("contracts")
	await wait_frames(1)
	hub.profile.add_samples("dog_fur", 2)
	hub.save_profile()
	cp.temp_cards["t_fur"].pressed.emit()
	assert_true(cp.popup_open() and cp.popup.primary_button != null, "fenêtre de remise avec VOIR DANS L'ARSENAL")
	var uid := cp.popup.target_uid
	assert_true(hub.profile.get_weapon(uid) != null, "arme reçue dans l'arsenal")
	cp.popup.primary_button.pressed.emit()
	await wait_frames(2)
	assert_eq(hub.current_id, "arsenal", "VOIR DANS L'ARSENAL : ARSENAL")
	var ap: Hub2ArsenalPanel = hub.panels.arsenal
	assert_eq(ap.tab, Hub2ArsenalPanel.WEAPONS)
	assert_eq(ap.selected_weapon().uid, uid, "arme reçue choisie")
	assert_eq(hub.get_viewport().gui_get_focus_owner(), ap.selected_card(), "focus sur sa carte")


func test_tile_tooltip_on_focus() -> void:
	var hub := await _open("contracts", _profile())
	var cp: Hub2ContractsPanel = hub.panels.contracts
	var tile: Hub2RewardTile = cp.story_tiles[0]
	assert_eq(tile.custom_minimum_size, Vector2(72, 72), "tuile 72 × 72")
	assert_eq(tile.color(), Hub2Style.rarity_color(1), "liseré de la rareté")
	tile.grab_focus()
	await wait_frames(2)
	assert_true(cp.tooltip.visible, "infobulle au focus")
	assert_eq(cp.tooltip.name_text.text, "GUÊPE")
	assert_eq(cp.tooltip.grid.get_child_count(), 6, "six statistiques")
	assert_eq(cp.tooltip.size.x, 260.0, "260 px")
	var tr := cp.tooltip.get_global_rect()
	assert_near(tr.end.y, tile.get_global_rect().position.y - 10.0, 1.0, "10 px au-dessus")
	assert_near(tr.position.x, tile.get_global_rect().position.x, 1.0, "aligné à gauche (histoire)")
	cp.story_tiles[1].grab_focus()
	await wait_frames(2)
	assert_eq(cp.tooltip.kind_text.text, "EXPÉRIENCE")
	tile.release_focus()
	cp.story_tiles[1].release_focus()
	await wait_frames(1)
	assert_false(cp.tooltip.visible, "cachée sans focus")


# --- ÉCHANGES --------------------------------------------------------------------

func test_exchanges_two_presses_and_filter() -> void:
	var pr := _profile()
	pr.add_samples("brancard_strap", 5)
	var hub := await _open("exchanges", pr)
	var xp_: Hub2ExchangesPanel = hub.panels.exchanges
	assert_eq(xp_.cards.size(), 3, "catalogue entier (TOUS)")
	assert_true(xp_.first_focus() == xp_.cards["x_sling"], "focus sur le premier échange possible")
	assert_near(xp_.cards["x_high"].modulate.a, 0.55, 0.001, "niveau trop bas : estompé")
	assert_eq(Hub2ExchangesPanel.kind_text(HubContractsView.data().exchange("x_sling").reward), "PIÈCE SOIGNÉE")
	assert_eq(Hub2ExchangesPanel.effect_text(HubContractsView.data().exchange("x_gun").reward, pr), "Fusil à pompe · niv. 5")
	xp_.cards["x_sling"].pressed.emit()
	assert_eq(xp_.confirm_id, "x_sling", "premier appui : CONFIRMER")
	assert_eq(hub.profile.sample_count("brancard_strap"), 5, "rien consommé")
	xp_.cards["x_sling"].pressed.emit()
	assert_true(xp_.popup_open(), "deuxième appui : échangé")
	assert_eq(hub.profile.sample_count("brancard_strap"), 1, "coût exact")
	assert_eq(hub.profile.parts.size(), 1)
	assert_eq(xp_.popup.head_text, "ÉCHANGE CONCLU")
	hub.back()
	assert_false(xp_.popup_open())
	xp_.cards["x_gun"].pressed.emit()
	assert_eq(xp_.confirm_id, "", "impossible : pas de confirmation")
	xp_.toggle_filter()
	assert_true(xp_.only_tradable)
	assert_eq(xp_.cards.size(), 0, "plus rien de possible")
	assert_true(xp_.empty_label != null)
	Settings.using_pad = true
	hub.refresh_prompts()
	assert_eq(Array(hub.prompts.describe()), ["A ÉCHANGER", "Y FILTRER", "B RETOUR"])
	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_Y
	ev.pressed = true
	assert_true(hub.handle_event(ev), "Y : filtre")
	assert_false(xp_.only_tradable)


# --- Taille des menus, anglais ---------------------------------------------------

func test_scale_130_fits() -> void:
	Settings.menu_ui_scale = 1.3
	var pr := _profile()
	pr.add_samples("dog_fang", 9)
	pr.add_samples("dog_fur", 9)
	var hub := await _open("lab", pr)
	for id in ["lab", "contracts", "exchanges"]:
		hub.open(id)
		if id == "contracts":
			hub.panels.contracts.accept("t_fangs")
			hub.panels.contracts.accept("t_fur")
		await wait_frames(4)
		var bad := []
		_outside(hub, Rect2(0, 0, 1280, 720).grow(1.0), bad)
		assert_true(bad.is_empty(), "130 %% %s : rien hors de l'écran %s" % [id, str(bad.slice(0, 4))])


func test_english() -> void:
	Settings.language = "en"
	var pr := _profile()
	pr.add_samples("dog_fang", 2)
	var hub := await _open("contracts", pr)
	var cp: Hub2ContractsPanel = hub.panels.contracts
	assert_eq(cp.chapter_text, "STORY · CHAPTER 1")
	assert_eq(cp.step_label_text, "STEP 1 OF 2")
	assert_eq(cp.unlock_text, "Unlocks step 2: “Itching Powder”")
	assert_eq(cp.count_text, "0 / 2 ongoing")
	hub.open("lab")
	assert_eq(hub.panels.lab.ready_tag.text, "1 DONE")
	assert_eq(hub.panels.lab.story_label.text, "Story · chapter 1, step 1 of 2")
	assert_eq(hub.panels.lab.line_text, "Ready!")
