extends TestCase
## Onglets CONTRATS et ÉCHANGES du hub (docs/HUB_PLAN.md §3.4, §3.5, lot D) :
## accepter, abandonner (deux appuis), remettre (fenêtre « contrat remis »,
## consommation exacte, une écriture du profil), boutons grisés et leurs
## raisons, progression partagée, contrats expirés signalés une fois au LABO,
## échange en deux appuis, filtre « échangeables », pastille de l'onglet,
## invites manette en anglais, taille 130 % sans débordement. Profil préparé
## comme la maquette (niveau 7, 7 crocs / 2 touffes / 5 colliers, 18
## novembre 2026). Sans MainMenu : hôte d'écrans minimal.

const FILE := "user://profile_hub_contracts_unittest.json"
const SETTINGS_TMP := "user://settings_hub_contracts_unittest.cfg"

var _saved := {}
var _frame: Control
var _writes := 0


class FakeHost extends MenuHost:
	func show_screen(_screen_name: String, _args := {}, _remember := true) -> void:
		pass

	func set_hint(_t: String) -> void:
		pass


func before_each() -> void:
	Input.flush_buffered_events()
	for k in ["menu_ui_scale", "using_pad", "language"]:
		_saved[k] = Settings.get(k)
	Settings.using_pad = false
	Settings.language = "fr"
	Settings.menu_ui_scale = 1.0
	HubContractsView.day_override = HubData.parse_day("2026-11-18")
	ProfileStore.reset(FILE)
	_writes = 0


func after_each() -> void:
	if is_instance_valid(_frame):
		_frame.queue_free()
	for k in _saved:
		Settings.set(k, _saved[k])
	HubContractsView.day_override = -1
	HubScreen.last_tab = "lab"
	ProfileStore.reset(FILE)


## Profil de la maquette : niveau 7, échantillons 7 / 2 / 5, 3 contrats
## actifs (Dents de lait prêt, Analyse complète, Urgence au labo), 3
## propositions dont une nouvelle, Premier prélèvement déjà rempli.
static func mockup_profile() -> PlayerProfile:
	var pr := PlayerProfile.new()
	pr.xp = PlayerProfile.xp_for_level(7) + 2140
	pr.add_samples("dog_fang", 7)
	pr.add_samples("dog_fur", 2)
	pr.add_samples("dog_collar", 5)
	var st := pr.contracts
	st.draw_seed = 918273
	st.rotation = 3
	st.done = {"first_sample": 1}
	st.active.append({"id": "dog_fangs_small", "accepted": 1})
	st.active.append({"id": "pack_analysis", "accepted": 2})
	st.active.append({"id": "lab_emergency", "accepted": 3})
	st.offers.append({"id": "dog_fur_coat", "since": 2})
	st.offers.append({"id": "dog_collars", "since": 3})
	st.offers.append({"id": "jaw_series", "since": 2})
	return pr


## Hub ouvert sur `tab` avec le profil enregistré dans FILE.
func _open(tab: String, pr: PlayerProfile) -> HubScreen:
	ProfileStore.save_profile(pr, FILE)
	_frame = Control.new()
	_frame.size = Vector2(1280, 720)
	host.add_child(_frame)
	var h := FakeHost.new()
	h.size = Vector2(1280, 720)
	_frame.add_child(h)
	var hub := HubScreen.new()
	hub.menu = h
	hub.size = Vector2(1280, 720)
	h.add_child(hub)
	h.current = hub
	h.current_name = "hub"
	hub.enter({"tab": tab, "profile_path": FILE})
	hub.profile_changed.connect(func(): _writes += 1)
	await wait_frames(3)
	return hub


func _focus(hub: HubScreen) -> Control:
	return hub.get_viewport().gui_get_focus_owner()


func _card(p: HubContractsPanel, id: String) -> HubContractCard:
	for c in p.active_cards + p.offer_cards:
		if c.contract_id == id:
			return c
	return null


func _disk() -> PlayerProfile:
	return ProfileStore.load_profile(FILE)


# --------------------------------------------------------------------------
# CONTRATS
# --------------------------------------------------------------------------

func test_board_like_mockup() -> void:
	var hub := await _open("contracts", mockup_profile())
	var p: HubContractsPanel = hub.panels.contracts
	assert_true(p is HubContractsPanel, "panneau CONTRATS branché")
	assert_eq(p.active_cards.size(), 3)
	assert_eq(p.offer_cards.size(), 3)
	assert_eq(p.active_count_label.text, "3 / 3")
	assert_true("3 CONTRATS ACTIFS AU MAXIMUM" in p.offers_count_label.text, p.offers_count_label.text)
	# Focus initial : REMETTRE du premier contrat prêt (Dents de lait).
	var milk := _card(p, "dog_fangs_small")
	assert_eq(_focus(hub), milk.main_button, "focus sur REMETTRE de Dents de lait")
	assert_eq(milk.tag.text, "PRÊT")
	assert_false(milk.main_button.disabled)
	assert_eq(milk.main_button.label, "REMETTRE")
	assert_true(milk.shared_label != null and milk.shared_label.text == "Partagé avec : Analyse complète", "progression partagée signalée")
	# Récompense au niveau actuel (D9) : 1 200 × 1,12 = 1 340 XP.
	var full := _card(p, "pack_analysis")
	assert_eq(full.right_label.text, "8 / 9")
	assert_true(full.main_button.disabled)
	assert_eq(full.main_button.label, "IL MANQUE 1 TOUFFE")
	var urgent := _card(p, "lab_emergency")
	assert_eq(urgent.tag.text, "ENCORE 12 J")
	assert_eq(urgent.main_button.label, "IL MANQUE 3 COLLIERS")
	# Propositions : ACCEPTER grisé à 3 contrats actifs ; nouvelle proposition.
	for c in p.offer_cards:
		assert_true(c.main_button.disabled, "ACCEPTER grisé (%s)" % c.contract_id)
	assert_true(_card(p, "dog_collars").tag != null, "pastille NOUVEAU sur la proposition arrivée à la dernière partie")
	assert_true(_card(p, "dog_fur_coat").tag == null)
	# Pastille de l'onglet : contrats prêts.
	assert_eq(hub.tab_bar.badges.get(3, 0), 1, "pastille CONTRATS = 1")
	# Réserve et aide.
	assert_eq(p.column.qty_labels.dog_fang.text, "7")
	assert_true("il en restera 3, assez pour" in p.column.note.text, p.column.note.text)
	var d := hub.prompts.describe()
	assert_eq(d[0], "Entrée Remettre")
	assert_eq(d[1], "Suppr Abandonner")
	assert_eq(_writes, 0, "aucune écriture à l'ouverture d'un tableau déjà rempli")


func test_deliver_consumes_exactly_and_writes_once() -> void:
	var hub := await _open("contracts", mockup_profile())
	var p: HubContractsPanel = hub.panels.contracts
	var xp_before := hub.profile.xp
	var parts_before := hub.profile.parts.size()
	_card(p, "dog_fangs_small").main_button.pressed.emit()
	await wait_frames(3)
	assert_eq(_writes, 1, "une seule écriture du profil")
	var pr := _disk()
	assert_eq(pr.sample_count("dog_fang"), 3, "7 − 4 = 3 crocs")
	assert_eq(pr.sample_count("dog_fur"), 2, "touffes intactes")
	assert_eq(pr.xp - xp_before, 1340, "XP au niveau 7 (D9)")
	assert_eq(pr.parts.size(), parts_before + 1, "pièce reçue")
	assert_eq(pr.contracts.done_count("dog_fangs_small"), 1)
	assert_false(pr.contracts.is_active("dog_fangs_small"), "case libérée")
	# Fenêtre « contrat remis ».
	assert_true(p.popup_open(), "fenêtre de récompense ouverte")
	assert_eq(p.popup.title_text, "Dents de lait")
	assert_eq(p.popup.thanks_text, "Parfait, parfait. J'ai bricolé ceci pendant votre absence.", "réplique de remerciement des données")
	assert_true(p.popup.item_name != "", "objet reçu nommé")
	assert_true(hub.profile.is_new_part(hub.profile.parts[-1].uid), "pastille NOUVEAU")
	assert_eq(_focus(hub), p.popup.primary_button, "focus sur VOIR DANS LES PIÈCES")
	assert_eq(hub.prompts.describe()[0], "Entrée Voir dans les pièces")
	await wait_frames(3)
	var pr_rect: Rect2 = p.popup.panel.get_rect()
	assert_near(pr_rect.size.y, 470.0, 1.0, "fenêtre de 470 px (maquette)")
	assert_true(pr_rect.end.y <= p.popup.size.y + 1.0, "fenêtre au-dessus de la barre d'invites (%s)" % pr_rect)
	# Une case libre est apparue ; ACCEPTER possible maintenant.
	assert_eq(p.active_cards.size(), 2)
	assert_false(_card(p, "dog_collars").main_button.disabled, "ACCEPTER actif (2 contrats actifs)")
	hub.back()  # Échap : fermer la fenêtre
	await wait_frames(3)
	assert_false(p.popup_open(), "Échap : fenêtre fermée")
	assert_eq(hub.tab, "contracts")


func test_deliver_level_up_shown() -> void:
	var pr := mockup_profile()
	pr.xp = PlayerProfile.xp_for_level(8) - 100
	var hub := await _open("contracts", pr)
	var p: HubContractsPanel = hub.panels.contracts
	_card(p, "dog_fangs_small").main_button.pressed.emit()
	await wait_frames(3)
	assert_true("NIVEAU 8 ! NIVEAU SUPÉRIEUR" in p.popup.level_text, p.popup.level_text)


func test_view_in_parts_goes_to_tab() -> void:
	var hub := await _open("contracts", mockup_profile())
	var p: HubContractsPanel = hub.panels.contracts
	_card(p, "dog_fangs_small").main_button.pressed.emit()
	await wait_frames(3)
	p.popup.primary_button.pressed.emit()
	await wait_frames(3)
	assert_eq(hub.tab, "parts", "VOIR DANS LES PIÈCES : onglet PIÈCES")
	assert_false(p.popup_open())
	# La pièce reçue est choisie, a le focus, garde sa pastille pendant la
	# visite et est enregistrée « vue » en quittant l'onglet.
	var parts: HubPartsPanel = hub.panels.parts
	var uid: String = hub.profile.parts[-1].uid
	assert_eq(parts.selected_uid, uid, "pièce reçue choisie")
	assert_eq(_focus(hub), parts._row_of(uid), "focus sur la pièce reçue")
	assert_true(parts._seen_now.has(uid), "pastille NOUVEAU gardée pendant la visite")
	hub.select_tab("lab")
	await wait_frames(2)
	assert_false(_disk().is_new_part(uid), "vue enregistrée en quittant l'onglet")


## Une pièce reçue garde sa pastille NOUVEAU tant que l'onglet PIÈCES n'a pas
## été ouvert : changer d'onglet, enregistrer, quitter le hub ne la marquent
## pas vue (les panneaux cachés choisissent leur ligne d'office sans la voir).
func test_new_part_kept_until_parts_tab_opened() -> void:
	var pr := mockup_profile()
	pr.add_part(WeaponPart.create("damage", 1, {"damage": 0.05}))
	pr.mark_all_seen()
	var hub := await _open("contracts", pr)
	var p: HubContractsPanel = hub.panels.contracts
	_card(p, "dog_fangs_small").main_button.pressed.emit()
	await wait_frames(3)
	var uid: String = hub.profile.parts[-1].uid
	p.popup.close_button.pressed.emit()
	await wait_frames(2)
	for id in ["arsenal", "exchanges", "loadout", "lab"]:
		hub.select_tab(id)
		await wait_frames(2)
	hub.save_profile()
	hub.exit()
	assert_true(hub.profile.is_new_part(uid), "toujours NOUVEAU en mémoire")
	assert_true(_disk().is_new_part(uid), "toujours NOUVEAU sur le disque")
	hub.select_tab("parts")
	await wait_frames(2)
	hub.panels.parts._row_of(uid).grab_focus()
	await wait_frames(2)
	assert_false(hub.profile.is_new_part(uid), "vue une fois l'onglet ouvert et la pièce choisie")


func test_accept_then_refused_when_full() -> void:
	var pr := mockup_profile()
	pr.contracts.remove_active("lab_emergency")
	var hub := await _open("contracts", pr)
	var p: HubContractsPanel = hub.panels.contracts
	var collars := _card(p, "dog_collars")
	assert_false(collars.main_button.disabled)
	collars.main_button.pressed.emit()
	await wait_frames(3)
	assert_eq(_writes, 1)
	var st := _disk().contracts
	assert_true(st.is_active("dog_collars") and not st.is_offered("dog_collars"), "proposition acceptée")
	assert_eq(_focus(hub), _card(p, "dog_collars").main_button, "le focus suit le nouveau contrat actif")
	assert_eq(p.offer_cards.size(), 2, "la case reste vide jusqu'à la prochaine partie")
	# 3 actifs : refus expliqué dans l'aide.
	var fur := _card(p, "dog_fur_coat")
	assert_true(fur.main_button.disabled)
	assert_true(fur.main_button.hint.begins_with("3 CONTRATS ACTIFS AU MAXIMUM"), fur.main_button.hint)
	p.accept("dog_fur_coat")
	assert_eq(_writes, 1, "refus : aucune écriture")


func test_abandon_two_presses() -> void:
	var hub := await _open("contracts", mockup_profile())
	var p: HubContractsPanel = hub.panels.contracts
	var full := _card(p, "pack_analysis")
	full.abandon_button.pressed.emit()
	await wait_frames(2)
	assert_eq(p.confirm_id, "pack_analysis")
	assert_eq(full.abandon_button.label, "CONFIRMER")
	assert_eq(_writes, 0, "premier appui : rien n'est fait")
	assert_eq(hub.prompts.describe()[0], "Entrée Confirmer l'abandon")
	# Échap annule.
	hub.back()
	await wait_frames(2)
	assert_eq(p.confirm_id, "")
	assert_eq(full.abandon_button.label, "ABANDONNER")
	assert_false(hub.hub_menu.is_open(), "Échap annule le deuxième appui sans ouvrir le menu")
	# Suppr deux fois sur le contrat choisi.
	full.main_button.grab_focus()
	await wait_frames(1)
	p.on_prompt(HubPrompts.SECONDARY)
	await wait_frames(1)
	assert_eq(_focus(hub), full.abandon_button, "Suppr : focus sur CONFIRMER")
	p.on_prompt(HubPrompts.SECONDARY)
	await wait_frames(3)
	assert_eq(_writes, 1)
	var pr := _disk()
	assert_false(pr.contracts.is_active("pack_analysis"), "contrat abandonné")
	assert_false(pr.contracts.is_offered("pack_analysis"), "ni proposé de nouveau")
	assert_eq(pr.sample_count("dog_fang"), 7, "rien n'est consommé")
	assert_eq(pr.sample_count("dog_collar"), 5)


func test_missing_samples_and_shared_note() -> void:
	var pr := mockup_profile()
	pr.remove_samples("dog_fang", 4)  # 3 crocs : Dents de lait n'est plus prêt
	var hub := await _open("contracts", pr)
	var p: HubContractsPanel = hub.panels.contracts
	var milk := _card(p, "dog_fangs_small")
	assert_true(milk.main_button.disabled)
	assert_eq(milk.main_button.label, "IL MANQUE 1 CROC")
	assert_eq(hub.tab_bar.badges.get(3, 0), 0, "aucune pastille")
	# Note de la réserve pour une remise qui fait reculer un autre contrat.
	var pr2 := mockup_profile()
	pr2.remove_samples("dog_fang", 1)  # 6 crocs : il en resterait 2 < 3
	var note := HubContractsPanel.deliver_note(pr2, HubContractsView.data(), "dog_fangs_small")
	assert_true("il en restera 2" in note and "[bad]Analyse complète[/bad] n'en aura plus assez" in note, note)


func test_expired_signaled_once() -> void:
	var pr := mockup_profile()
	HubContractsView.day_override = HubData.parse_day("2026-12-01")  # après le 30 novembre
	var hub := await _open("lab", pr)
	assert_eq(Array(hub.expired_notice), ["Urgence au labo"], "contrat actif expiré signalé")
	var lab: HubLabPanel = hub.panels.lab
	assert_true("expiré" in lab.line_text, lab.line_text)
	var disk := _disk()
	assert_false(disk.contracts.is_active("lab_emergency"), "supprimé des contrats actifs")
	assert_eq(disk.contracts.expired_unseen.size(), 0, "signalement enregistré (une fois)")
	assert_eq(disk.sample_count("dog_collar"), 5, "échantillons jamais touchés")
	_frame.queue_free()
	await wait_frames(2)
	var hub2 := await _open("lab", disk)
	assert_eq(hub2.expired_notice.size(), 0, "pas signalé une deuxième fois")


func test_first_open_fills_board() -> void:
	var pr := PlayerProfile.new()
	var hub := await _open("contracts", pr)
	var st := _disk().contracts
	assert_eq(st.rotation, 1, "tableau rempli la toute première fois")
	assert_true(st.is_offered("first_sample"), "contrat tuto proposé")
	var p: HubContractsPanel = hub.panels.contracts
	assert_eq(p.offer_cards.size(), st.offers.size())
	assert_eq(p.active_cards.size(), 0)
	assert_eq(_focus(hub), p.offer_cards[0].main_button, "focus sur ACCEPTER")
	assert_eq(HubContractsView.new_offer_count(hub.profile), st.offers.size(), "toutes nouvelles")


func test_lab_shows_contracts() -> void:
	var hub := await _open("lab", mockup_profile())
	var lab: HubLabPanel = hub.panels.lab
	assert_eq(lab.contract_rows.size(), 3, "contrats actifs réels")
	assert_eq(lab.contracts_box.right_label.text, "3 / 3")
	assert_eq(lab.stats.contracts_done.text, "1", "contrats remplis")
	assert_true("sens" in lab.line_text, "réplique : contrat prêt")


func test_english_pad_prompts() -> void:
	Settings.language = "en"
	Settings.using_pad = true
	var hub := await _open("contracts", mockup_profile())
	var p: HubContractsPanel = hub.panels.contracts
	var milk := _card(p, "dog_fangs_small")
	assert_eq(milk.main_button.label, "HAND IN")
	assert_eq(_card(p, "pack_analysis").main_button.label, "1 TUFT OF FUR MISSING")
	assert_eq(_card(p, "lab_emergency").tag.text, "12 DAYS LEFT")
	var d := hub.prompts.describe()
	assert_eq(d[0], "A Hand in")
	assert_eq(d[1], "X Abandon")


func test_scale_130_stays_on_screen() -> void:
	Settings.menu_ui_scale = 1.3
	var hub := await _open("contracts", mockup_profile())
	await wait_frames(2)
	_check_inside(hub, "CONTRATS 130 %")
	hub.select_tab("exchanges")
	await wait_frames(3)
	_check_inside(hub, "ÉCHANGES 130 %")


# --------------------------------------------------------------------------
# ÉCHANGES
# --------------------------------------------------------------------------

func test_exchange_rows_like_mockup() -> void:
	var hub := await _open("exchanges", mockup_profile())
	var p: HubExchangesPanel = hub.panels.exchanges
	assert_true(p is HubExchangesPanel)
	assert_eq(Array(p.order), ["fang_trim", "fur_padding", "collar_strap", "sharpened_fangs", "pack_weapon",
		"leather_sling", "tagged_sights", "taut_cords", "night_kit"])
	assert_eq(p.rows.fang_trim.button.label, "IL MANQUE 1 TOUFFE")
	assert_eq(p.rows.fur_padding.button.label, "IL MANQUE 4 TOUFFES")
	assert_eq(p.rows.collar_strap.button.label, "ÉCHANGER")
	assert_eq(p.rows.sharpened_fangs.button.label, "IL MANQUE 1 CROC")
	assert_eq(p.rows.pack_weapon.button, null, "niveau trop haut : pas de bouton")
	assert_eq(p.rows.pack_weapon.tag.text, "NIV. 8 REQUIS")
	assert_eq(_focus(hub), p.rows.collar_strap.button, "focus sur le premier échange possible")
	assert_eq(p.catalog.right_label.text, "objets au niveau du joueur (7)")


func test_exchange_two_presses() -> void:
	var hub := await _open("exchanges", mockup_profile())
	var p: HubExchangesPanel = hub.panels.exchanges
	var b: HubButton = p.rows.collar_strap.button
	b.pressed.emit()
	await wait_frames(2)
	assert_eq(b.label, "CONFIRMER : 4 COLLIERS + 2 TOUFFES")
	assert_eq(_writes, 0)
	assert_eq(hub.prompts.describe()[0], "Entrée Confirmer l'échange")
	assert_true("[color=#%s]" % HubStyle.BAD.to_html(false) in p.column.note.text and "Analyse complète" in p.column.note.text,
			"conséquence sur le contrat actif signalée")
	b.pressed.emit()
	await wait_frames(3)
	assert_eq(_writes, 1, "une écriture")
	var pr := _disk()
	assert_eq(pr.sample_count("dog_collar"), 1, "5 − 4")
	assert_eq(pr.sample_count("dog_fur"), 0, "2 − 2")
	assert_eq(pr.exchanges_done.get("collar_strap", 0), 1)
	assert_eq(pr.xp, mockup_profile().xp, "pas d'XP (D10)")
	assert_true(p.popup_open(), "fenêtre de l'objet reçu")
	assert_eq(p.popup.item_name, "BRIDE DE COLLIER")
	p.popup.close()
	await wait_frames(2)


func test_exchange_cancel_and_filter() -> void:
	var hub := await _open("exchanges", mockup_profile())
	var p: HubExchangesPanel = hub.panels.exchanges
	p.rows.collar_strap.button.pressed.emit()
	await wait_frames(2)
	hub.back()
	await wait_frames(2)
	assert_eq(p.confirm_id, "")
	assert_eq(p.rows.collar_strap.button.label, "ÉCHANGER", "Échap annule")
	p.on_prompt(HubPrompts.FILTER)
	await wait_frames(3)
	assert_true(p.only_tradable)
	assert_eq(Array(p.order), ["collar_strap"], "filtre ÉCHANGEABLES MAINTENANT")
	assert_true(p.chip_tradable.on and not p.chip_all.on)
	p.toggle_filter()
	await wait_frames(2)
	assert_eq(p.order.size(), 9)


# --------------------------------------------------------------------------

## Aucun contrôle visible ne sort de l'écran (contenu des listes qui
## défilent excepté).
func _check_inside(root: Control, what: String) -> void:
	var screen := Rect2(Vector2.ZERO, Vector2(1280, 720)).grow(1.0)
	var bad := []
	_scan(root, screen, bad)
	assert_true(bad.is_empty(), "%s : rien ne sort de l'écran %s" % [what, str(bad.slice(0, 4))])


func _scan(n: Node, screen: Rect2, bad: Array) -> void:
	if n is Control:
		var c := n as Control
		if not c.is_visible_in_tree():
			return
		var r := c.get_global_rect()
		r.position -= _frame.global_position
		if not screen.encloses(r):
			bad.append("%s %s" % [c.name, r])
		if c is ScrollContainer:
			return
	for ch in n.get_children():
		_scan(ch, screen, bad)
