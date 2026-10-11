extends TestCase
## Hub v2 : INVENTAIRE et CODEX (docs/hub_v2/Inventaire.dc.html,
## Codex.dc.html). Fiches des échantillons (SampleCatalog : noms de
## LootRules, descriptions FR / EN, demandes des contrats actifs et des
## échanges, taux lus dans LootRules, sortes inconnues), cartes du bestiaire
## (CodexData.cards : groupe « Les zombies », ordre par manche), écrans
## Hub2InventoryPanel et Hub2CodexPanel dans Hub2Screen (grille, choix au
## focus, fiche, A -> contrat, pastille NOUVEAU vue puis enregistrée, onglet,
## anglais, 130 %).

var _saved := {}
var _frame: Control


class FakeHost extends MenuHost:
	func show_screen(_screen_name: String, _args := {}, _remember := true) -> void:
		pass


func before_each() -> void:
	for k in ["menu_ui_scale", "using_pad", "language"]:
		_saved[k] = Settings.get(k)
	Settings.using_pad = false
	Settings.language = "fr"
	Settings.menu_ui_scale = 1.0


func after_each() -> void:
	if is_instance_valid(_frame):
		_frame.queue_free()
	for k in _saved:
		Settings.set(k, _saved[k])
	HubContractsView.data_override = null
	Hub2Screen.last_screen = "lab"


## Catalogue de test : 3 contrats (2 actifs), 3 échanges (un à la limite
## atteinte, un terminé).
func _data() -> HubData:
	var c := {"format": "hub_contracts", "version": 1, "contracts": [
		_contract("c_strap", {"brancard_strap": 3}),
		_contract("c_both", {"brancard_strap": 3, "brancard_bracelet": 1}),
		_contract("c_fang", {"dog_fang": 2}),
	]}
	var x := {"format": "hub_exchanges", "version": 1, "exchanges": [
		_exchange("x_strap", {"brancard_strap": 4}, {}),
		_exchange("x_limited", {"brancard_strap": 2}, {"limit": 1}),
		_exchange("x_old", {"brancard_strap": 1}, {"ends": "2000-01-02"}),
		_exchange("x_fur", {"dog_fur": 1}, {}),
	]}
	var d := HubData.from_texts(JSON.stringify(c), JSON.stringify(x))
	assert_eq(d.warnings.size(), 0, "catalogue de test valide : %s" % ", ".join(d.warnings))
	return d


func _contract(id: String, samples: Dictionary) -> Dictionary:
	return {"id": id, "title": {"fr": "Contrat " + id, "en": "Contract " + id}, "text": {"fr": "t", "en": "t"},
		"samples": samples, "xp": 10, "reward": {"kind": "none"}, "min_level": 1}


func _exchange(id: String, samples: Dictionary, extra: Dictionary) -> Dictionary:
	var e := {"id": id, "title": {"fr": "Échange " + id, "en": "Exchange " + id}, "samples": samples,
		"reward": {"kind": "part", "mods": {"damage": 0.1}}, "min_level": 1}
	e.merge(extra)
	return e


## Profil : 4 sangles, 12 crocs, Brancardier et meute rencontrés, contrats
## c_strap et c_both actifs, c_fang seulement proposé, x_limited déjà fait.
func _profile() -> PlayerProfile:
	var pr := PlayerProfile.new()
	pr.xp = PlayerProfile.xp_for_level(10)
	pr.add_samples("brancard_strap", 4)
	pr.add_samples("dog_fang", 12)
	pr.codex.add_kills("brancardier", 7)
	pr.codex.add_kills("dog", 54)
	pr.codex.add_kills("walker", 100)
	pr.codex.add_kills("runner", 36)
	pr.codex.mark_seen("brancardier")
	pr.codex.mark_seen("walker")
	pr.codex.mark_seen("runner")
	pr.contracts.active.append({"id": "c_strap", "accepted": 0})
	pr.contracts.active.append({"id": "c_both", "accepted": 0})
	pr.contracts.offers.append({"id": "c_fang", "since": 0})
	pr.exchanges_done["x_limited"] = 1
	return pr


func _open(screen: String, pr: PlayerProfile) -> Hub2Screen:
	HubContractsView.data_override = _data()
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
	h.current_name = "hub2"
	hub.enter({"screen": screen, "profile": pr})
	await wait_frames(3)
	return hub


func _texts(n: Node, out: Array) -> Array:
	if n is Label:
		out.append((n as Label).text)
	elif n is Hub2Text:
		out.append((n as Hub2Text).text)
	for c in n.get_children():
		_texts(c, out)
	return out


func _find(n: Node, node_name: String) -> Node:
	return n.find_child(node_name, true, false)


# --- Fiches des échantillons ------------------------------------------------------

func test_catalog_names_and_texts() -> void:
	var ids := SampleCatalog.ids()
	assert_eq(ids.size(), 10, "10 sortes au butin")
	for id in ids:
		assert_true(SampleCatalog.INFO.has(id), "fiche de %s" % id)
		for en in [false, true]:
			Settings.language = "en" if en else "fr"
			var loot := LootRules.sample_name(id)
			assert_eq(SampleCatalog.display_name(id).to_upper(), loot.to_upper(), "nom de LootRules (%s, %s)" % [id, Settings.language])
			assert_eq(SampleCatalog.display_name(id).left(1), loot.left(1), "majuscule initiale")
			var t := SampleCatalog.description(id)
			assert_true(t.length() > 30, "description %s %s" % [id, Settings.language])
			for ch in t:
				assert_false(ch.is_valid_int(), "pas de chiffre dans la description de %s" % id)
	Settings.language = "fr"
	assert_eq(SampleCatalog.display_name("brancard_strap"), "Sangle de cuir")
	assert_eq(SampleCatalog.color("brancard_strap").to_html(false), "8a5a2b", "couleur de la maquette")
	assert_eq(SampleCatalog.where_title("brancard_strap"), "OÙ LA TROUVER")
	assert_eq(SampleCatalog.where_title("dog_fang"), "OÙ LE TROUVER")
	assert_eq(SampleCatalog.asked_title("nurse_vocal_cords"), "DEMANDÉES PAR")
	assert_eq(SampleCatalog.asked_title("brancard_strap"), "DEMANDÉE PAR")


func test_usage_counts() -> void:
	var d := _data()
	var pr := _profile()
	var day := HubData.today()
	var u := SampleCatalog.uses(pr, "brancard_strap", d, day)
	var got := []
	for e in u:
		got.append("%s:%s:%d/%d" % [e.kind, e.id, e.have, e.need])
	assert_eq(got, ["contract:c_strap:4/3", "contract:c_both:4/3", "exchange:x_strap:4/4"],
			"contrats actifs puis échanges ; ni proposition, ni limite atteinte, ni échange terminé")
	assert_eq(SampleCatalog.use_line(u), "2 contrats · 1 échange")
	assert_eq(SampleCatalog.use_line(SampleCatalog.uses(pr, "brancard_bracelet", d, day)), "1 contrat")
	assert_eq(SampleCatalog.use_line(SampleCatalog.uses(pr, "dog_fang", d, day)), "Aucune demande", "c_fang n'est que proposé")
	assert_eq(SampleCatalog.use_line(SampleCatalog.uses(pr, "dog_fur", d, day)), "1 échange")
	Settings.language = "en"
	assert_eq(SampleCatalog.use_line(u), "2 contracts · 1 exchange")
	Settings.language = "fr"
	assert_eq(SampleCatalog.total(pr), 16, "16 en réserve")


func test_rates_from_loot_rules() -> void:
	var codex := CodexData.default()
	assert_eq(SampleCatalog.percent(0.2), "20" + String.chr(0xA0) + "%")
	assert_eq(SampleCatalog.percent(1.0), "100" + String.chr(0xA0) + "%")
	var normal := SampleCatalog.loot_rate("brancard_strap", codex)
	assert_eq(normal.rate, SampleCatalog.percent(LootRules.SAMPLE_CHANCE), "taux de LootRules.SAMPLE_CHANCE")
	assert_eq(normal.note, "par zombie tué pendant sa vague")
	var boss := SampleCatalog.loot_rate("surgeon_heart", codex)
	assert_eq(boss.rate, SampleCatalog.percent(LootRules.BOSS_SAMPLE_CHANCE), "boss : LootRules.BOSS_SAMPLE_CHANCE")
	assert_eq(boss.note, "sur le boss · %s sur son escorte" % SampleCatalog.percent(LootRules.SAMPLE_CHANCE))
	assert_true(SampleCatalog.from_boss("surgeon_scalpel", codex) and not SampleCatalog.from_boss("dog_fang", codex))
	assert_eq(SampleCatalog.where_text("brancard_strap", codex), "Vague du Brancardier, dès la manche %d : %s sur chaque zombie de la vague."
			% [int(codex.entry("brancardier").round), SampleCatalog.percent(LootRules.SAMPLE_CHANCE)], "maquette")
	assert_true(SampleCatalog.where_text("surgeon_heart", codex).contains("%s sur le boss" % SampleCatalog.percent(LootRules.BOSS_SAMPLE_CHANCE)))
	Settings.language = "en"
	assert_eq(SampleCatalog.percent(0.2), "20%")
	assert_eq(SampleCatalog.loot_rate("dog_fang", codex).note, "per zombie killed during its wave")
	assert_true(SampleCatalog.where_text("dog_fang", codex).begins_with("Stray Pack wave, from round"))


func test_unknown_samples() -> void:
	var codex := CodexData.default()
	var pr := PlayerProfile.new()
	assert_eq(SampleCatalog.known_count(pr, codex), 0, "profil neuf : rien de connu")
	assert_false(SampleCatalog.is_known(null, "dog_fang", codex))
	pr.codex.encounter("nurse")
	assert_true(SampleCatalog.is_known(pr, "nurse_syringe", codex), "ennemi rencontré : ses sortes sont connues (même à 0)")
	assert_false(SampleCatalog.is_known(pr, "surgeon_heart", codex))
	pr.add_samples("surgeon_heart", 1)
	assert_true(SampleCatalog.is_known(pr, "surgeon_heart", codex), "en réserve : connue")
	assert_eq(SampleCatalog.known_count(pr, codex), 4)
	assert_eq(String(SampleCatalog.enemy_of("dog_collar", codex).id), "dog")


# --- Cartes du bestiaire ------------------------------------------------------------

func test_codex_cards_grouping() -> void:
	CodexData.clear_cache()
	var d := CodexData.default()
	assert_eq(d.warnings.size(), 0, "codex.json (groupes compris) sans avertissement : %s" % ", ".join(d.warnings))
	var cards := d.cards()
	var ids := []
	for c in cards:
		ids.append(c.id)
	assert_eq(ids, ["zombies", "dog", "brancardier", "surgeon", "nurse"], "maquette : une carte « Les zombies », ordre des manches")
	var z: Dictionary = cards[0]
	assert_eq(Array(z.members), ["walker", "crawler", "runner", "sprinter"])
	assert_eq(String(z.name.fr), "Les zombies")
	assert_eq(int(z.round), 1)
	assert_eq(z.category, XpRules.COMMON)
	assert_eq(int(z.xp_min), XpRules.base_xp(XpRules.WALKER), "XP du barème")
	assert_true((z.samples as PackedStringArray).is_empty())
	assert_eq(int(cards[3].xp_max), XpRules.base_xp(XpRules.SURGEON))
	assert_eq(Hub2CodexPanel.xp_text(z), Hub2Style.num(XpRules.base_xp(XpRules.WALKER)))
	assert_eq(Hub2CodexPanel.xp_text({"xp_min": 1, "xp_max": 3}), "1 à 3")
	# Groupes invalides écartés.
	var bad := CodexData.from_text(JSON.stringify({"format": "hub_codex", "version": 1, "enemies": [
		{"id": "walker", "name": {"fr": "A", "en": "A"}, "text": {"fr": "a", "en": "a"}, "round": 1},
		{"id": "runner", "name": {"fr": "B", "en": "B"}, "text": {"fr": "b", "en": "b"}, "round": 4}],
		"groups": [
			{"id": "g", "name": {"fr": "G", "en": "G"}, "text": {"fr": "g", "en": "g"}, "members": ["walker", "ghost"]},
			{"id": "walker", "name": {"fr": "G", "en": "G"}, "text": {"fr": "g", "en": "g"}, "members": ["walker", "runner"]},
			{"id": "h", "name": {"fr": "H"}, "text": {"fr": "h", "en": "h"}, "members": ["walker", "runner"]},
			{"id": "ok", "name": {"fr": "O", "en": "O"}, "text": {"fr": "o", "en": "o"}, "members": ["walker", "runner"]},
			{"id": "again", "name": {"fr": "O", "en": "O"}, "text": {"fr": "o", "en": "o"}, "members": ["walker", "runner"]}]}))
	assert_eq(bad.groups.size(), 1, "seul le groupe valide reste")
	assert_eq(bad.warnings.size(), 4)
	assert_eq(bad.cards().size(), 1, "deux fiches -> une carte")


# --- Écran INVENTAIRE ---------------------------------------------------------------

func test_inventory_screen() -> void:
	var pr := _profile()
	var hub := await _open("inventory", pr)
	var inv: Hub2InventoryPanel = hub.panels.inventory
	assert_eq(inv.header_count.text, "16 en réserve · 5 sortes connues sur 10", "crocs, touffes, colliers, sangles, bracelets")
	assert_eq(inv.columns, 4, "4 colonnes de la maquette")
	assert_near(inv.cards.dog_fang.size.x, 197.0, 1.0, "carte de 197,5 px (820 − 3 × 10) / 4")
	assert_true(inv.cards.dog_fang.size.y >= 70.0, "padding 8 + rendu 52 + 8 + liseré : 70 px au moins")
	_assert_names_readable(inv, "100 %")
	assert_eq(inv.cards.size(), 10)
	assert_eq(inv.selected_id, "dog_fang", "première sorte en réserve")
	assert_true(at_focus(inv.cards.dog_fang), "focus sur la carte choisie")
	var strap: Hub2Button = inv.cards.brancard_strap
	var t := _texts(strap, [])
	assert_true("Sangle de cuir" in t and "2 contrats · 1 échange" in t and "4" in t, "carte : nom, demandes, quantité (%s)" % str(t))
	var unknown := _texts(inv.cards.surgeon_heart, [])
	assert_true("???" in unknown and "jamais obtenu" in unknown and "–" in unknown, "inconnue : %s" % str(unknown))
	var imgs := (inv.cards.surgeon_heart as Node).find_children("*", "Hub2ShadowRender", true, false)
	assert_eq(imgs.size(), 1)
	assert_near((imgs[0] as Hub2ShadowRender).silhouette, 0.5, 0.001, "silhouette noire brightness(0) opacity(0.5)")
	# Voisins de focus : lignes des groupes, colonne gardée (ou dernière carte).
	assert_eq(strap.get_node(strap.focus_neighbor_bottom), inv.cards.nurse_vocal_cords, "bas : même colonne du groupe suivant")
	assert_eq(strap.get_node(strap.focus_neighbor_top), inv.cards.dog_fang)
	assert_eq(inv.cards.dog_collar.get_node(inv.cards.dog_collar.focus_neighbor_bottom), inv.cards.brancard_bracelet,
			"ligne plus courte : sa dernière carte")
	assert_eq(strap.get_node(strap.focus_neighbor_left), strap, "pas de boucle")
	# Focus -> carte choisie (liseré jaune) et fiche.
	strap.grab_focus()
	await wait_frames(1)
	assert_eq(inv.selected_id, "brancard_strap")
	assert_eq(strap.box.border_color, Hub2Style.YELLOW, "liseré jaune")
	assert_eq(strap.box.fill, Hub2Style.yellow_a(0.12), "teinte jaune")
	assert_eq((inv.cards.dog_fang as Hub2Button).box.border_color, Hub2Style.LINE)
	var detail := _texts(inv._detail, [])
	for s in ["BRANCARDIER", "Sangle de cuir", "4 en réserve", "OÙ LA TROUVER", "DEMANDÉE PAR", "CONTRAT", "ÉCHANGE",
			"Contrat c_strap", "Échange x_strap", "4 / 3", "4 / 4"]:
		assert_true(s in detail, "fiche : « %s » (%s)" % [s, str(detail)])
	var where := _find(inv._detail, "Where") as Label
	assert_true(where.text.begins_with("Vague du Brancardier, dès la manche"), where.text)
	var count := _find(_find(inv._detail, "Use_c_strap"), "Count") as Hub2Text
	assert_eq(count.color, Hub2Style.TEAL, "possédé ≥ demandé : turquoise")
	# Aucune demande.
	inv.cards.dog_fang.grab_focus()
	await wait_frames(1)
	assert_true(_find(inv._detail, "Nobody") != null, "aucune demande : phrase")
	# A / Entrée : le contrat qui la demande.
	strap.grab_focus()
	await wait_frames(1)
	strap.pressed.emit()
	assert_eq(hub.current_id, "contracts", "A : CONTRATS")
	hub.open("inventory")
	inv.cards.dog_fur.grab_focus()
	await wait_frames(1)
	inv.cards.dog_fur.pressed.emit()
	assert_eq(hub.current_id, "exchanges", "seul un échange la demande : ÉCHANGES")
	hub.open("inventory")
	Settings.using_pad = true
	assert_eq(Array(hub.prompts.describe()), ["A VOIR LE CONTRAT", "B RETOUR"], "invites de la maquette")


func test_inventory_english_and_scale() -> void:
	Settings.language = "en"
	var hub := await _open("inventory", _profile())
	var inv: Hub2InventoryPanel = hub.panels.inventory
	assert_eq(inv.header_count.text, "16 in stock · 5 of 10 kinds known")
	assert_true("Leather strap" in _texts(inv.cards.brancard_strap, []))
	Settings.menu_ui_scale = 1.3
	await wait_frames(3)
	inv = hub.panels.inventory
	await wait_frames(2)
	_assert_inside(hub, "inventaire à 130 %")
	assert_eq(inv.columns, 2, "130 % : 2 colonnes (cartes à leur largeur de maquette)")
	var w0: float = inv.cards.dog_fang.size.x
	assert_true(w0 >= Hub2Style.px(Hub2InventoryPanel.CARD_W) * 0.9, "carte assez large (%.0f)" % w0)
	assert_near(inv.cards.dog_fur.size.x, w0, 1.0, "colonnes égales")
	_assert_names_readable(inv, "130 %")
	assert_true(inv._list.get_combined_minimum_size().y > inv.list_scroll.size.y, "130 % : la liste défile")


## Noms et demandes des cartes lisibles en entier : ni « … », ni ligne
## cachée, ni mot coupé en deux.
func _assert_names_readable(inv: Hub2InventoryPanel, what: String) -> void:
	for id in inv.cards:
		for nn in ["Name", "Use"]:
			var l := _find(inv.cards[id], nn) as Label
			assert_eq(l.text_overrun_behavior, TextServer.OVERRUN_NO_TRIMMING, "%s %s : pas de « … »" % [what, id])
			assert_false(l.clip_text, "%s %s : pas rogné" % [what, id])
			assert_true(l.get_visible_line_count() == l.get_line_count(), "%s %s : toutes les lignes visibles" % [what, id])
			var words := l.text.split(" ").size()
			assert_true(l.get_line_count() <= words, "%s %s « %s » : aucun mot coupé (%d lignes)" % [what, id, l.text, l.get_line_count()])


# --- Écran CODEX ----------------------------------------------------------------------

func test_codex_screen() -> void:
	var pr := _profile()
	pr.codex.add_kills("surgeon", 1)  # nouveau
	var hub := await _open("codex", pr)
	var cx: Hub2CodexPanel = hub.panels.codex
	assert_eq(cx.header_count.text, "4 / 5 rencontrés")
	assert_eq(cx.cards.size(), 5)
	assert_eq(cx.selected_id, "dog", "première fiche nouvelle (ordre des manches)")
	assert_true(_find(cx.cards.surgeon, "New") != null, "pastille NOUVEAU")
	cx.cards.surgeon.grab_focus()
	await wait_frames(1)
	assert_eq(cx.selected_id, "surgeon", "le focus choisit la carte")
	assert_true(_find(cx.cards.dog, "New") != null, "meute rencontrée, jamais vue : NOUVEAU")
	assert_true(_find(cx.cards.brancardier, "New") == null)
	assert_true(pr.codex.seen.has("surgeon") and pr.codex.seen.has("dog"), "vues à l'affichage")
	var nurse: Hub2Button = cx.cards.nurse
	var nt := _texts(nurse, [])
	assert_true("???" in nt and "INCONNU" in nt and "?" in nt and "MANCHE 20" in nt, "inconnu : %s" % str(nt))
	assert_true(_find(nurse, "Dashes") != null, "pointillés")
	var br: Hub2Button = cx.cards.brancardier
	assert_eq(br.get_node(br.focus_neighbor_bottom), nurse, "grille de 3 : bas vers la dernière de la ligne")
	assert_eq(nurse.get_node(nurse.focus_neighbor_top), cx.cards.dog)
	assert_eq(nurse.box.border_color.a, 0.0, "pas de liseré plein")
	var zt := _texts(cx.cards.zombies, [])
	assert_true("Les zombies" in zt and "ZOMBIE" in zt and "MANCHE 1" in zt, str(zt))
	# Fiche du Chirurgien : taux de butin du boss.
	var d := _texts(cx._detail, [])
	assert_true("BOSS · DÈS LA MANCHE 15" in d and "Le Chirurgien" in d, str(d))
	assert_eq((_find(cx._detail, "Xp") as Hub2Text).text, Hub2Style.num(XpRules.base_xp(XpRules.SURGEON)), "XP de XpRules")
	assert_eq((_find(cx._detail, "Kills") as Hub2Text).text, "1")
	var row := _find(cx._detail, "Loot_surgeon_heart")
	assert_eq((_find(row, "Rate") as Hub2Text).text, SampleCatalog.percent(LootRules.BOSS_SAMPLE_CHANCE))
	assert_eq((_find(row, "Note") as Hub2Text).text, "sur le boss · %s sur son escorte" % SampleCatalog.percent(LootRules.SAMPLE_CHANCE))
	# Les zombies : somme des éliminations, pas d'échantillon.
	cx.cards.zombies.grab_focus()
	await wait_frames(1)
	assert_eq(cx.selected_id, "zombies")
	assert_eq((_find(cx._detail, "Kills") as Hub2Text).text, "136", "marcheurs + coureurs")
	assert_true(_find(cx._detail, "NoLoot") != null, "il ne donne que de la ferraille")
	# Inconnu : silhouette, « ? », taux cachés.
	nurse.grab_focus()
	await wait_frames(1)
	d = _texts(cx._detail, [])
	assert_true("INCONNU · DÈS LA MANCHE 20" in d and "???" in d, str(d))
	assert_eq((_find(cx._detail, "Xp") as Hub2Text).text, "?")
	assert_eq((_find(_find(cx._detail, "Loot_nurse_badge"), "Rate") as Hub2Text).text, "?")
	assert_true((_find(cx._detail, "Text") as Label).text.contains("dès la manche 20"))
	# Brancardier : rencontré, taux normal.
	cx.cards.brancardier.grab_focus()
	await wait_frames(1)
	assert_eq((_find(_find(cx._detail, "Loot_brancard_strap"), "Rate") as Hub2Text).text, SampleCatalog.percent(LootRules.SAMPLE_CHANCE))
	assert_eq(cx.cards.brancardier.box.border_color, Hub2Style.YELLOW, "choisie : liseré jaune")
	# Quitter l'onglet : enregistré, pastilles retirées.
	hub.open("lab")
	assert_false(cx.badge(), "plus de fiche nouvelle")
	assert_true(_find(cx.cards.surgeon, "New") == null, "pastille retirée après la visite")
	Settings.using_pad = true
	hub.open("codex")
	assert_eq(Array(hub.prompts.describe()), ["A DÉTAILS", "B RETOUR"])


func test_codex_tab_badge_before_visit() -> void:
	var pr := _profile()
	pr.codex.add_kills("surgeon", 1)
	var hub := await _open("lab", pr)
	assert_false(hub.panels.has("codex"), "écran pas encore construit")
	assert_true(hub.top_bar.badges.get("codex", false), "pastille de l'onglet CODEX dès l'ouverture")
	assert_true(Hub2CodexPanel.tab_badge(pr))
	assert_false(Hub2CodexPanel.tab_badge(PlayerProfile.new()))


func test_codex_english_and_scale() -> void:
	Settings.language = "en"
	var hub := await _open("codex", _profile())
	var cx: Hub2CodexPanel = hub.panels.codex
	assert_eq(cx.header_count.text, "3 / 5 encountered")
	assert_true("The zombies" in _texts(cx.cards.zombies, []))
	Settings.menu_ui_scale = 1.3
	await wait_frames(5)
	_assert_inside(hub, "codex à 130 %")
	cx = hub.panels.codex
	assert_eq(cx.columns, 2, "130 % : 2 colonnes")
	assert_near(cx.cards.zombies.size.x, cx.cards.dog.size.x, 1.0, "colonnes égales")


func at_focus(c: Control) -> bool:
	return c.get_viewport().gui_get_focus_owner() == c


## Rien ne sort du cadre de 1280 × 720 (hors contenus rognés d'une zone qui
## défile).
func _assert_inside(hub: Hub2Screen, what: String) -> void:
	var screen := Rect2(Vector2.ZERO, Vector2(1280, 720)).grow(1.0)
	var bad := []
	_scan(hub, screen, bad)
	assert_true(bad.is_empty(), "%s : rien ne sort du cadre %s" % [what, str(bad.slice(0, 4))])


func _scan(n: Node, screen: Rect2, bad: Array) -> void:
	if n is ScrollContainer:
		if not screen.encloses((n as Control).get_global_rect()):
			bad.append("%s %s" % [n.name, (n as Control).get_global_rect()])
		return
	if n is Control:
		var c := n as Control
		if not c.is_visible_in_tree():
			return
		if not (c is Hub2PulseRings) and not screen.encloses(c.get_global_rect()):
			bad.append("%s %s" % [c.name, c.get_global_rect()])
	for ch in n.get_children():
		_scan(ch, screen, bad)
