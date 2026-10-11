extends TestCase
## Récapitulatif d'après partie du hub v2 (Recap.dc.html, Hub2RecapModel,
## Hub2RecapPanel) : détail de l'XP par catégorie du relevé (XpRules),
## passages de niveau (un ou plusieurs, ordre et instants), courbes des
## @keyframes (pop, anneaux, éclair, « NIVEAU N ! », lignes), butin gardé /
## perdu (§4.16), carte perso (aucune progression), écran réel : A termine
## l'animation puis CONTINUER, REJOUER, textes FR / EN.

var _saved := {}
var _frame: Control
var _host: FakeHost


class FakeHost extends MenuHost:
	func show_screen(_screen_name: String, _args := {}, _remember := true) -> void:
		pass


func before_each() -> void:
	for k in ["menu_ui_scale", "using_pad", "language", "player_name"]:
		_saved[k] = Settings.get(k)
	Settings.using_pad = false
	Settings.language = "fr"
	Settings.menu_ui_scale = 1.0
	_saved["last_match"] = Router.last_match
	HubContractsView.day_override = HubData.parse_day("2026-11-18")


func after_each() -> void:
	if is_instance_valid(_frame):
		_frame.queue_free()
	for k in _saved:
		if k == "last_match":
			Router.last_match = _saved[k]
		else:
			Settings.set(k, _saved[k])
	HubContractsView.day_override = -1
	Hub2Screen.last_screen = "lab"


## Relevé de la maquette : 2 840 (zombies), 1 320 (vagues spéciales et
## boss), 1 480 (manches), 600 (évacuation).
static func mock_ledger() -> Dictionary:
	var l := XpRules.new_ledger()
	l.kills = {"walker": 200, "dog": 10, "surgeon": 1}
	l.kill_xp = {"walker": 2840, "dog": 500, "surgeon": 640}
	l.wave_xp = 180
	l.rounds = 16
	l.round_xp = 1480
	l.evac_bonus = 600
	l.closed = true
	return l


## Partie de la maquette : niveau 23 à 4 680 XP du niveau 24 (maquette :
## 8 420 / 13 100 ; barème du jeu : besoin plus grand) -> 24, +6 240 XP.
static func mock_last(evacuated := true, progress := true) -> Dictionary:
	var r := MatchResult.new()
	r.evacuated = evacuated
	r.round_reached = 17
	r.kills = 284
	r.duration_sec = 42 * 60 + 18
	r.xp_ledger = mock_ledger()
	var start := PlayerProfile.xp_for_level(24) - 4680
	r.xp = 6240 if progress else 0
	r.profile_xp = start + r.xp
	var pd := PlayerData.new(1)
	pd.weapons = [GameWeapon.make("python", 20, 3, [], "loot:1"), GameWeapon.make("spectre", 18, 2, [], "loot:2"),
		GameWeapon.make("stakeout", 17, 1, [], "w4")]
	var loot := ProfileLoot.carried(pd, [], {"dog_fang": 3, "dog_fur": 2, "brancard_strap": 2, "brancard_bracelet": 1,
		"surgeon_scalpel": 1})
	r.loot = ProfileLoot.report(loot, evacuated and progress)
	if not progress:
		r.loot["custom"] = true
	return {"result": r, "map": "Bunker K-7", "map_id": "bunker_k7" if progress else "perso:quai_13",
		"progress": progress, "challenge": false, "solo": true}


func test_ledger_rows_mapping() -> void:
	var rows := Hub2RecapModel.ledger_rows(mock_ledger())
	assert_eq(rows.size(), 4, "quatre catégories (maquette)")
	assert_eq(rows[0], {"key": "kills", "label": "Zombies éliminés", "xp": 2840})
	assert_eq(rows[1], {"key": "waves", "label": "Vagues spéciales et boss", "xp": 1320}, "chiens + Chirurgien + vagues")
	assert_eq(rows[2], {"key": "rounds", "label": "Manches survécues", "xp": 1480})
	assert_eq(rows[3], {"key": "evac", "label": "Évacuation réussie", "xp": 600})
	var total := 0
	for r in rows:
		total += int(r.xp)
	assert_eq(total, XpRules.total(mock_ledger()), "somme = XP du relevé")
	var w := Hub2RecapModel.ledger_rows(mock_ledger(), 400)
	assert_eq(w[-1].label, "Défi de la semaine", "récompense du défi")
	var empty := Hub2RecapModel.ledger_rows(XpRules.new_ledger())
	assert_true(empty.is_empty(), "catégories à 0 omises")
	Settings.language = "en"
	assert_eq(Hub2RecapModel.ledger_rows(mock_ledger())[0].label, "Zombies killed")


func test_model_from_mockup_match() -> void:
	var m := Hub2RecapModel.new().read(mock_last(), PlayerProfile.new())
	assert_eq(m.kicker(), "RETOUR AU LABO · BUNKER K-7")
	assert_eq(m.title(), "ÉVACUÉ")
	assert_eq(m.duration_text(), "42:18")
	assert_eq(m.gained, 6240)
	assert_eq(m.level_before, 23)
	assert_eq(m.level_after, 24)
	assert_eq(m.weapons.size(), 3)
	assert_eq(m.weapons[0].name, "COUPERET", "nom de la maquette (python)")
	assert_true(m.weapons[0].new and not m.weapons[2].new, "NEUF : butin ; version de l'arsenal : mise à jour")
	assert_eq(m.sample_total(), 9, "ÉCHANTILLONS · 9")
	assert_eq(m.samples[0].id, "dog_fang", "ordre des échantillons (LootRules)")
	assert_eq(m.loot_title(), "BUTIN GARDÉ")
	assert_eq(m.outcome()[0], "RIEN DE PERDU")
	assert_true(m.unlocked.begins_with("Armes de niveau 24"), m.unlocked)
	var s0 := m.state_at(0.0)
	assert_eq(int(s0.level), 23)
	var need := PlayerProfile.xp_to_next(23)
	var nb := String.chr(0xA0)
	assert_eq(Hub2RecapModel.xp_line(s0, m.xp_start), "%s / %s" % [Hub2Style.num(need - 4680), Hub2Style.num(need)],
			"« 8 420 / 13 100 » de la maquette (XP dans le niveau / besoin)")
	assert_true(Hub2RecapModel.xp_line(s0, m.xp_start).contains(nb), "espace insécable des milliers")
	var s1 := m.state_at(Hub2RecapModel.XP_DELAY + Hub2RecapModel.XP_DURATION)
	assert_eq(int(s1.gained), 6240)
	assert_eq(int(s1.level), 24)
	assert_eq(int(s1["in"]), 6240 - 4680, "barre repartie de 0 après le passage")


## Le défaite : titre, butin perdu (§4.16 : ce qui est perdu), XP gardée.
func test_model_defeat_lists_losses() -> void:
	var m := Hub2RecapModel.new().read(mock_last(false), PlayerProfile.new())
	assert_eq(m.title(), "LA HORDE L’EMPORTE")
	assert_false(m.kept)
	assert_eq(m.loot_title(), "BUTIN PERDU")
	assert_eq(m.lost_text(), "3 armes, 9 échantillons")
	assert_eq(m.outcome()[0], "PERDU")
	assert_eq(m.gained, 6240, "l'XP est toujours gardée")


## Carte perso : aucune progression (ni XP ni butin), règle affichée.
func test_model_custom_map() -> void:
	var m := Hub2RecapModel.new().read(mock_last(true, false), PlayerProfile.new())
	assert_false(m.progress)
	assert_eq(m.gained, 0)
	assert_true(m.rows.is_empty(), "pas de détail d'XP")
	assert_eq(m.unlocked, "")
	assert_eq(m.loot_title(), "BUTIN NON GARDÉ")
	assert_eq(m.outcome()[0], "POUR LE FUN")
	assert_eq(m.level_before, m.level_after)


## Plusieurs passages de niveau : dans l'ordre, chacun à son instant, barre
## turquoise et repartie de 0 à chaque fois.
func test_level_up_sequencing() -> void:
	var r := MatchResult.new()
	var start := PlayerProfile.xp_for_level(6) - 50
	r.xp = PlayerProfile.xp_to_next(6) + 200
	r.profile_xp = start + r.xp
	r.evacuated = true
	var m := Hub2RecapModel.new().read({"result": r, "map": "X", "progress": true}, null)
	assert_eq(m.level_before, 5)
	assert_eq(m.level_after, 7, "deux niveaux")
	var ups := m.level_ups()
	assert_eq(ups.size(), 2)
	assert_eq(ups[0], [6, 50], "niveau 6 après 50 XP")
	assert_eq(ups[1][0], 7)
	var t6 := m.time_of_gain(int(ups[0][1]))
	var t7 := m.time_of_gain(int(ups[1][1]))
	assert_true(t6 > Hub2RecapModel.XP_DELAY and t6 < t7 and t7 <= Hub2RecapModel.XP_DELAY + Hub2RecapModel.XP_DURATION,
			"instants croissants (%.3f, %.3f)" % [t6, t7])
	assert_eq(int(m.state_at(t6 - 0.01).level), 5, "juste avant : niveau 5")
	assert_eq(int(m.state_at(t6).level), 6, "au passage : niveau 6")
	assert_eq(int(m.state_at(t7).level), 7)
	assert_eq(int(m.state_at(t7).levels), 2)
	# Monotone.
	var last := -1
	for i in 50:
		var g := m.gained_at(i * 0.1)
		assert_true(g >= last, "XP croissante")
		last = g
	assert_eq(m.gained_at(0.5), 0, "rien avant 0,7 s")
	assert_eq(m.gained_at(10.0), m.gained)


func test_keyframe_curves() -> void:
	assert_near(Hub2RecapModel.ease_cubic(0.5), 0.875, 0.0001, "1 − (1 − x)³")
	assert_eq(Hub2RecapPanel.pop_scale(-1.0), 1.0)
	assert_near(Hub2RecapPanel.pop_scale(0.7 * 0.35), 1.45, 0.001, "pop : 1,45 à 35 %")
	assert_true(Hub2RecapPanel.pop_scale(0.7 * 0.2) > 1.45, "cubic-bezier(.2, 1.6, …) : dépasse")
	assert_eq(Hub2RecapPanel.pop_scale(0.7), 1.0)
	assert_near(Hub2RecapPanel.flash_alpha(0.0), 0.55, 0.0001)
	assert_eq(Hub2RecapPanel.flash_alpha(0.9), 0.0)
	var a := Hub2RecapPanel.level_text_state(0.0)
	assert_near(float(a.opacity), 0.0, 0.0001)
	assert_near(float(a.y), 14.0, 0.0001)
	assert_near(float(a.tracking), 0.6, 0.0001)
	var b := Hub2RecapPanel.level_text_state(2.2 * 0.25)
	assert_near(float(b.opacity), 1.0, 0.0001)
	assert_near(float(b.scale), 1.0, 0.0001)
	assert_near(float(b.tracking), 0.22, 0.0001)
	assert_near(float(Hub2RecapPanel.level_text_state(2.2 * 0.7).opacity), 1.0, 0.0001, "visible jusqu'à 80 %")
	assert_eq(float(Hub2RecapPanel.level_text_state(2.2).opacity), 0.0)
	assert_eq(Hub2RecapPanel.row_in(0.0), 0.0)
	assert_eq(Hub2RecapPanel.row_in(0.4), 1.0)


## Hub v2 ouvert sur le récapitulatif (cadre de 1280 × 720).
func _open_recap(last: Dictionary) -> Hub2Screen:
	Router.last_match = last
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
	_host.current_name = "hub2"
	var pr := PlayerProfile.new()
	pr.xp = (last.result as MatchResult).profile_xp
	hub.enter({"screen": "recap", "profile": pr})
	await wait_frames(3)
	return hub


func _accept(hub: Hub2Screen) -> bool:
	var ev := InputEventAction.new()
	ev.action = "ui_accept"
	ev.pressed = true
	return hub.handle_event(ev)


func test_panel_animation_skip_and_continue() -> void:
	var hub := await _open_recap(mock_last())
	var p: Hub2RecapPanel = hub.panels.recap
	assert_eq(hub.current_id, "recap")
	assert_true(Router.last_match.get("recap_seen", false), "vu : pas remontré au prochain retour")
	assert_eq(p.title_text.text, "ÉVACUÉ")
	assert_eq(p.title_text.color, Hub2Style.TEAL)
	assert_true(p.animating(), "animation en cours")
	assert_eq(p.gained_text.text, "+0 XP")
	assert_eq(p.badge_level.text, "23")
	assert_eq(hub.get_viewport().gui_get_focus_owner(), p.continue_button, "focus : CONTINUER")
	# Au passage du niveau 24 : pavé plein, barre turquoise, texte, éclair.
	var tu: float = p._ups[0][1]
	p.frozen = true
	p.apply_time(tu + 0.3)
	assert_eq(p.badge_level.text, "24")
	assert_eq(p.bar_color, Hub2Style.TEAL, "barre turquoise après le passage")
	assert_true(p.level_text.visible and p.level_text.text == "NIVEAU 24 !", p.level_text.text)
	assert_true(p.flash.visible, "éclair doré")
	assert_true(p.level_badge.scale.x > 1.0, "pavé qui saute")
	p.frozen = false
	# A : fin immédiate de l'animation (consommé), puis CONTINUER.
	assert_true(_accept(hub), "A pendant l'animation : consommé")
	assert_false(p.animating())
	assert_eq(p.gained_text.text, "+%s XP" % Hub2Style.num(6240), "+6 240 XP")
	assert_false(p.level_text.visible, "texte du niveau fini")
	assert_false(p.flash.visible)
	assert_eq(p.unlocked_box.modulate.a, 1.0, "DÉBLOQUÉ affiché")
	assert_eq(p.row_nodes[0][0].modulate.a, 1.0, "lignes entrées")
	assert_false(_accept(hub), "animation finie : A va au bouton (CONTINUER)")
	p.continue_button.pressed.emit()
	assert_eq(hub.current_id, "lab", "CONTINUER : LABO")


func test_panel_replay_and_back() -> void:
	var hub := await _open_recap(mock_last(false))
	var p: Hub2RecapPanel = hub.panels.recap
	assert_eq(p.title_text.text, "LA HORDE L’EMPORTE")
	p.finish()
	p.replay_button.pressed.emit()
	assert_true(p.animating(), "REJOUER : animation relancée")
	assert_eq(p.t, 0.0)
	hub.back()
	assert_eq(hub.current_id, "lab", "B / Échap : CONTINUER")


func test_panel_english_and_custom() -> void:
	Settings.language = "en"
	var hub := await _open_recap(mock_last(true, false))
	var p: Hub2RecapPanel = hub.panels.recap
	assert_eq(p.title_text.text, "EVACUATED")
	p.finish()
	assert_eq(p.gained_text.text, "+0 XP", "carte perso : aucune XP")
	assert_eq(p.unlocked_box, null)
