extends TestCase
## Codex du hub (bestiaire, GAME_CONCEPT §4.17, HUB_PLAN §3.10) : fiches
## livrées (CodexData), rencontres du relevé d'XP (XpRules « met »),
## enregistrement dans le profil (CodexState, MatchXp.apply), migration d'un
## profil sans codex, onglet CODEX (fiches connues / inconnues, pastille
## NOUVEAU).

## Fichier propre à ce processus (les tests ne touchent jamais au vrai profil).
var file := "user://profile_codex_unittest_%d.json" % OS.get_process_id()
var _frame: Control
var _saved := {}


class FakeHost extends MenuHost:
	func show_screen(_screen_name: String, _args := {}, _remember := true) -> void:
		pass

	func set_hint(_t: String) -> void:
		pass


func before_each() -> void:
	ProfileStore.reset(file)
	for k in ["menu_ui_scale", "using_pad", "language"]:
		_saved[k] = Settings.get(k)
	Settings.using_pad = false
	Settings.language = "fr"
	Settings.menu_ui_scale = 1.0


func after_each() -> void:
	ProfileStore.reset(file)
	if is_instance_valid(_frame):
		_frame.queue_free()
	for k in _saved:
		Settings.set(k, _saved[k])
	HubScreen.last_tab = "lab"


# --------------------------------------------------------------------------
# Données
# --------------------------------------------------------------------------

func test_fiches_livrees_sans_avertissement() -> void:
	CodexData.clear_cache()
	var d := CodexData.default()
	assert_eq(d.warnings.size(), 0, "codex.json sans avertissement : %s" % ", ".join(d.warnings))
	for id in ["walker", "runner", "sprinter", "crawler", "dog", "brancardier", "nurse", "surgeon"]:
		assert_true(d.has(id), "fiche « %s »" % id)
	# Chaque ennemi réel du barème (hors valeurs de référence) a sa fiche.
	for t in XpRules.ENEMIES:
		if t != XpRules.MINIBOSS_GENERIC and t != XpRules.BOSS_GENERIC:
			assert_true(d.has(t), "type de XpRules « %s » au codex" % t)
	for e in d.entries:
		assert_true(String(e.name.fr) != "" and String(e.name.en) != "", "nom FR / EN : %s" % e.id)
		assert_true(String(e.text.fr) != "" and String(e.text.en) != "", "description FR / EN : %s" % e.id)
		assert_true(CodexData.xp(e) > 0, "XP lue dans XpRules : %s" % e.id)
		# Pas de nombre exact dans les descriptions (répliques génériques).
		for lang in ["fr", "en"]:
			var t: String = e.text[lang]
			for ch in t:
				assert_false(ch.is_valid_int(), "pas de chiffre dans la description %s de %s" % [lang, e.id])
	assert_eq(int(d.entry("dog").round), 5)
	assert_eq(Array(d.entry("dog").samples), ["dog_fang", "dog_fur", "dog_collar"], "mêmes sortes que le butin")
	assert_eq(CodexData.xp(d.entry("walker")), XpRules.base_xp(XpRules.WALKER), "XP du barème, pas dupliquée")
	assert_eq(CodexData.xp(d.entry("surgeon")), XpRules.base_xp(XpRules.SURGEON), "le Chirurgien : son propre barème")
	assert_false(d.entry("surgeon").planned, "le Chirurgien est en jeu")
	# Ennemi prévu (xp_ref) : XP de référence de sa catégorie.
	var planned := CodexData.from_text(JSON.stringify({"format": "hub_codex", "version": 1, "enemies": [
		{"id": "futur", "name": {"fr": "F", "en": "F"}, "text": {"fr": "f", "en": "f"}, "round": 40, "xp_ref": "boss", "planned": true}]}))
	assert_eq(CodexData.xp(planned.entry("futur")), XpRules.base_xp(XpRules.BOSS_GENERIC), "ennemi prévu : XP de référence")
	assert_true(planned.entry("futur").planned)
	assert_eq(CodexData.sample_name("dog_fang"), "CROC")
	assert_eq(CodexData.sample_name("surgeon_scalpel"), Lang.t("SCALPEL", "SCALPEL"))
	assert_eq(CodexData.sample_name("futur_sample"), "???", "sorte pas encore au butin")


func test_fiches_invalides_ecartees() -> void:
	var d := CodexData.from_text(JSON.stringify({"format": "hub_codex", "version": 1, "enemies": [
		{"id": "walker", "name": {"fr": "A", "en": "A"}, "text": {"fr": "a", "en": "a"}, "round": 1},
		{"id": "walker", "name": {"fr": "B", "en": "B"}, "text": {"fr": "b", "en": "b"}, "round": 1},
		{"id": "x y", "name": {"fr": "C", "en": "C"}, "text": {"fr": "c", "en": "c"}, "round": 1},
		{"id": "runner", "name": {"fr": "D"}, "text": {"fr": "d", "en": "d"}, "round": 1},
		{"id": "sprinter", "name": {"fr": "E", "en": "E"}, "text": {"fr": "e", "en": "e"}, "round": 0},
		{"id": "ghost", "name": {"fr": "F", "en": "F"}, "text": {"fr": "f", "en": "f"}, "round": 3},
		{"id": "ghost2", "name": {"fr": "G", "en": "G"}, "text": {"fr": "g", "en": "g"}, "round": 3, "xp_ref": "boss",
			"samples": ["a", "a"]},
		"pas un objet"]}))
	assert_eq(Array(d.ids()), ["walker"], "seule la première fiche valide reste")
	assert_eq(d.warnings.size(), 7)
	assert_eq(CodexData.from_text("").entries.size(), 0)
	assert_eq(CodexData.from_text("{\"format\": \"autre\", \"version\": 1}").entries.size(), 0)


# --------------------------------------------------------------------------
# Rencontres et enregistrement
# --------------------------------------------------------------------------

func test_rencontres_du_releve() -> void:
	var l := XpRules.new_ledger()
	assert_true(XpRules.add_met(l, XpRules.DOG), "première rencontre")
	assert_false(XpRules.add_met(l, XpRules.DOG), "une seule fois par partie")
	assert_false(XpRules.add_met(l, "inconnu"), "type inconnu ignoré")
	XpRules.add_kill(l, XpRules.WALKER, 1)
	assert_eq(Array(XpRules.met_types(l)), [XpRules.DOG, XpRules.WALKER], "une élimination est une rencontre")
	assert_eq(XpRules.total(l), XpRules.kill_xp(XpRules.WALKER, 1), "une rencontre ne rapporte pas d'XP")
	# Relu du réseau : rencontres gardées, types inconnus écartés.
	l.met["x"] = 1
	var back := XpRules.clean_ledger(l.duplicate(true))
	assert_eq(Array(XpRules.met_types(back)), [XpRules.DOG, XpRules.WALKER])
	assert_true(XpRules.clean_ledger({"met": "oui"}).met.is_empty())
	XpRules.close(l, false)
	assert_false(XpRules.add_met(l, XpRules.RUNNER), "relevé clos")
	# Ancien relevé sans « met » : rien ne casse.
	var old := {"kills": {XpRules.RUNNER: 2}}
	assert_eq(Array(XpRules.met_types(old)), [XpRules.RUNNER])
	assert_true(XpRules.add_met(old, XpRules.DOG))


func test_codex_rempli_par_la_partie() -> void:
	var l := XpRules.new_ledger()
	for i in 3:
		XpRules.add_kill(l, XpRules.WALKER, 1)
	XpRules.add_met(l, XpRules.DOG)
	XpRules.close(l, false)
	var r := MatchXp.apply(l, file)
	assert_eq(Array(r.codex_new), [XpRules.DOG, XpRules.WALKER], "découvertes de la partie")
	var pr := ProfileStore.load_profile(file)
	assert_true(pr.codex.is_known(XpRules.DOG), "chien rencontré (coup porté ou reçu)")
	assert_eq(pr.codex.kills(XpRules.DOG), 0)
	assert_eq(pr.codex.kills(XpRules.WALKER), 3)
	assert_false(pr.codex.is_known(XpRules.SPRINTER), "jamais rencontré")
	assert_eq(pr.codex.new_count(), 2, "pastille NOUVEAU")
	# Deuxième partie : les éliminations s'ajoutent, rien de nouveau.
	var l2 := XpRules.new_ledger()
	XpRules.add_kill(l2, XpRules.WALKER, 4)
	XpRules.add_kill(l2, XpRules.DOG, 5)
	var r2 := MatchXp.apply(l2, file)
	assert_eq(r2.codex_new.size(), 0)
	pr = ProfileStore.load_profile(file)
	assert_eq(pr.codex.kills(XpRules.WALKER), 4)
	assert_eq(pr.codex.kills(XpRules.DOG), 1)
	# Partie sans XP mais avec une rencontre : enregistrée quand même.
	var l3 := XpRules.new_ledger()
	XpRules.add_met(l3, XpRules.SPRINTER)
	var r3 := MatchXp.apply(l3, file)
	assert_eq(r3.xp, 0)
	assert_true(ProfileStore.load_profile(file).codex.is_known(XpRules.SPRINTER))


func test_codex_vu_et_aller_retour() -> void:
	var pr := PlayerProfile.new()
	pr.codex.add_kills(XpRules.DOG, 12)
	pr.codex.encounter(XpRules.RUNNER)
	pr.codex.mark_seen(XpRules.DOG)
	pr.codex.mark_seen(XpRules.SPRINTER)  # jamais rencontré : ignoré
	assert_false(pr.codex.is_new(XpRules.DOG))
	assert_true(pr.codex.is_new(XpRules.RUNNER))
	ProfileStore.save_profile(pr, file)
	var back := ProfileStore.load_profile(file)
	assert_eq(back.codex.kills(XpRules.DOG), 12)
	assert_true(back.codex.is_known(XpRules.RUNNER))
	assert_eq(Array(back.codex.seen), [XpRules.DOG])
	assert_eq(ProfileStore.last_status, "ok")


func test_migration_profil_sans_codex() -> void:
	# Profil enregistré avant le codex (v2 sans section) et profil v1 : se
	# lisent sans perte, codex vide, rien d'écarté.
	for doc in [{"format": "profile", "version": 2, "profile": {"xp": 500, "samples": {"dog_fang": 3}}},
			{"format": "profile", "version": 1, "profile": {"xp": 500, "samples": {"dog_fang": 3}}}]:
		ProfileStore.reset(file)
		var f := FileAccess.open(file, FileAccess.WRITE)
		f.store_string(JSON.stringify(doc))
		f.close()
		var pr := ProfileStore.load_profile(file)
		assert_eq(ProfileStore.last_status, "ok")
		assert_eq(pr.xp, 500)
		assert_eq(pr.sample_count("dog_fang"), 3)
		assert_true(pr.codex.enemies.is_empty(), "codex vide")
		assert_eq(pr.codex.new_count(), 0)
	# Section abîmée : entrées écartées, le reste est lu.
	var dropped := [0]
	var c := CodexState.from_dict({"enemies": {"dog": 4, "bad id": 1, "walker": -2, "runner": "x"}, "seen": ["dog", 5]}, dropped)
	assert_eq(c.kills("dog"), 4)
	assert_eq(c.enemies.size(), 1)
	assert_eq(dropped[0], 4)
	assert_eq(CodexState.from_dict("Object(Node)", dropped).enemies.size(), 0)


# --------------------------------------------------------------------------
# Onglet CODEX
# --------------------------------------------------------------------------

func _open(pr: PlayerProfile) -> HubScreen:
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
	hub.enter({"tab": "lab", "profile": pr})
	await wait_frames(3)
	return hub


func test_onglet_codex() -> void:
	var pr := PlayerProfile.new()
	pr.codex.add_kills(XpRules.WALKER, 1234)
	pr.codex.encounter(XpRules.DOG)
	pr.codex.mark_seen(XpRules.WALKER)
	var hub := await _open(pr)
	var cp: HubCodexPanel = hub.panels.codex
	var i := HubScreen.TABS.find("codex")
	assert_eq(i, HubScreen.TABS.find("play") - 1, "CODEX juste avant PARTIE")
	assert_eq(int(hub.tab_bar.badges.get(i, 0)), 1, "pastille : une fiche nouvelle (chien)")
	assert_eq(cp.cards.size(), cp.data.entries.size(), "une fiche par ennemi")
	assert_eq(cp.box.right_label.text, "2 / %d rencontrés" % cp.data.entries.size())
	var w := cp.card_of("walker")
	assert_true(w.known and not w.empty)
	assert_true(_has_text(w, "MARCHEUR"), "nom")
	assert_true(_has_text(w, HubStyle.num(1234)), "éliminations")
	assert_true(_has_text(w, str(XpRules.base_xp(XpRules.WALKER))), "XP du barème")
	assert_false(_has_tag(w), "déjà vu : pas de NOUVEAU")
	var dog := cp.card_of("dog")
	assert_true(_has_tag(dog), "chien : NOUVEAU")
	assert_true(_has_text(dog, "CROC"), "échantillons")
	var s := cp.card_of("surgeon")
	assert_true(not s.known and s.empty, "inconnu : fiche grisée")
	assert_true(_has_text(s, "???"))
	assert_true(_has_text(s, "Peut apparaître dès la manche 15"), "seulement l'indice de manche")
	assert_false(_has_text(s, "CHIRURGIEN"), "nom caché")
	# Affichage : focus sur la première fiche, flèches entre les fiches.
	hub.select_tab("codex")
	await wait_frames(2)
	assert_eq(hub.get_viewport().gui_get_focus_owner(), cp.cards[0])
	assert_eq(cp.cards[0].find_valid_focus_neighbor(SIDE_RIGHT), cp.cards[1], "droite : fiche suivante")
	assert_eq(cp.cards[0].find_valid_focus_neighbor(SIDE_BOTTOM), cp.cards[HubCodexPanel.COLUMNS], "bas : rangée suivante")
	# Vu : enregistré en quittant l'onglet, la pastille disparaît.
	assert_false(pr.codex.is_new(XpRules.DOG))
	assert_true(_has_tag(cp.card_of("dog")), "NOUVEAU reste affiché pendant la visite")
	assert_eq(int(hub.tab_bar.badges.get(i, 0)), 0, "pastille de l'onglet retirée à l'affichage")
	hub.select_tab("lab")
	assert_eq(int(hub.tab_bar.badges.get(i, 0)), 0, "plus de pastille")
	assert_false(_has_tag(cp.card_of("dog")), "visite suivante : plus de NOUVEAU")
	Settings.language = "en"
	assert_eq(HubScreen.tab_label("codex"), "CODEX")
	assert_eq(CodexData.round_hint(20), "May appear from round 20")


func test_codex_taille_des_menus() -> void:
	var pr := PlayerProfile.new()
	for t in XpRules.ENEMIES:
		pr.codex.add_kills(t, 99999)
	for f in [0.8, 1.3]:
		Settings.menu_ui_scale = f
		var hub := await _open(pr)
		hub.select_tab("codex")
		await wait_frames(3)
		var cp: HubCodexPanel = hub.panels.codex
		var r := Rect2(Vector2.ZERO, Vector2(1280, 720)).grow(1.0)
		assert_true(r.encloses(cp.box.get_global_rect()), "%d %% : le bestiaire reste à l'écran" % roundi(f * 100))
		for c in cp.cards:
			assert_true(c.size.x > 0.0 and c.size.y >= HubStyle.px(HubCodexCard.CARD_H) - 1.0, "fiche dimensionnée")
		_frame.queue_free()
		await wait_frames(1)


func _has_text(n: Node, t: String) -> bool:
	if n is Label and (n as Label).text.contains(t):
		return true
	for c in n.get_children():
		if _has_text(c, t):
			return true
	return false


func _has_tag(n: Node) -> bool:
	if n is HubTag and (n as HubTag).kind == HubTag.NEW:
		return true
	for c in n.get_children():
		if _has_tag(c):
			return true
	return false
