class_name Hub2RewardPopup
extends Control
## Fenêtre de remise du hub v2 (pas de maquette dédiée : composée avec les
## jetons des maquettes docs/hub_v2) ouverte après REMETTRE (étape
## d'histoire ou contrat temporaire) et après un ÉCHANGE : voile sombre sur
## le hub (la barre d'invites reste visible), panneau de verre centré :
##   - sorte (« HISTOIRE · ÉTAPE 3 TERMINÉE », « CONTRAT REMIS », « ÉCHANGE
##     CONCLU »), titre ;
##   - Dr Brown (rendu characters/scientist_bust) et sa réplique de
##     remerciement (champ `thanks`, sinon une réplique générique) ;
##   - récompense en tuiles (objet reçu, XP) avec infobulle, XP gagnée,
##     niveau avant → après (« NIVEAU SUPÉRIEUR ») ;
##   - histoire : étape ou chapitre débloqué ;
##   - échantillons consommés et ce qui reste ;
##   - VOIR DANS L'ARSENAL (l'objet porte la pastille NOUVEAU) et FERMER.
## Posée sur le hub (Hub2Screen) ; garde le focus (B / Échap / clic sur le
## voile : fermer). Le profil est déjà enregistré par l'appelant.

const THANKS := ["Excellent travail. La science vous remercie, moi aussi, un peu.",
	"Excellent work. Science thanks you, and so do I, a little."]
const DEAL := ["Marché conclu. Ne me demandez pas d’où vient l’odeur.",
	"Deal. Don't ask me where the smell comes from."]
const WIDTH := 640.0
const BUST := 104.0

var hub: Node
var panel: Hub2Box
var primary_button: Hub2Button
var close_button: Hub2Button
var tooltip: Hub2RewardTooltip
var tiles: Array = []
## Textes affichés (tests).
var head_text := ""
var title_text := ""
var thanks_text := ""
var level_text := ""
var unlock_text := ""
var primary_text := ""
## Exemplaire reçu (uid) et écran où le voir.
var target_uid := ""
var target_screen := ""

signal closed


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	offset_bottom = -Hub2Style.px(Hub2Style.PROMPTS_H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


## Étape d'histoire remise : `res` = rapport de StoryRules.deliver.
func show_story(res: Dictionary, pr: PlayerProfile, remaining: Dictionary) -> void:
	var s: Dictionary = res.step
	var loc := StoryRules.data().locate(s.id)
	var head := Lang.t("HISTOIRE · ÉTAPE %d TERMINÉE", "STORY · STEP %d COMPLETE") % (int(loc.get("step_index", 0)) + 1)
	var nx: Dictionary = res.next
	var unlock := ""
	if nx.is_empty():
		unlock = Lang.t("Histoire terminée. La suite au prochain chapitre…", "Story complete. To be continued…")
	elif res.chapter_done:
		var nl := StoryRules.data().locate(nx.id)
		unlock = Lang.t("Chapitre %d débloqué : « %s »", "Chapter %d unlocked: “%s”") % [int(nl.chapter_index) + 1,
			HubData.text_of(nl.chapter.title)]
	else:
		var nl2 := StoryRules.data().locate(nx.id)
		unlock = Lang.t("Étape %d débloquée : « %s »", "Step %d unlocked: “%s”") % [int(nl2.step_index) + 1, HubData.text_of(nx.title)]
	var th := HubData.text_of(res.get("thanks", {}))
	_build(head, HubData.text_of(s.title), th if th != "" else Lang.t(THANKS[0], THANKS[1]), res, pr, s.samples,
			remaining, true, unlock, s.reward)


## Contrat temporaire remis : `res` = rapport de ContractRules.deliver.
func show_contract(c: Dictionary, res: Dictionary, pr: PlayerProfile, remaining: Dictionary) -> void:
	var th := HubData.text_of(c.get("thanks", {}))
	_build(Lang.t("CONTRAT REMIS", "CONTRACT DELIVERED"), HubData.text_of(c.title),
			th if th != "" else Lang.t(THANKS[0], THANKS[1]), res, pr, c.samples, remaining, true, "", c.reward)


## Échange conclu : `res` = rapport d'ExchangeRules.trade.
func show_exchange(x: Dictionary, res: Dictionary, pr: PlayerProfile, remaining: Dictionary) -> void:
	_build(Lang.t("ÉCHANGE CONCLU", "EXCHANGE DONE"), HubData.text_of(x.title), Lang.t(DEAL[0], DEAL[1]), res, pr,
			x.samples, remaining, false, "", x.reward)


func is_open() -> bool:
	return visible


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()
	queue_free()


func _build(head: String, title: String, line: String, res: Dictionary, pr: PlayerProfile, cost: Dictionary,
		remaining: Dictionary, with_xp: bool, unlock: String, reward: Dictionary) -> void:
	head_text = head
	title_text = title
	thanks_text = line
	unlock_text = unlock
	var veil := ColorRect.new()
	veil.color = Hub2Style.shade(0.62)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)
	add_child(Hub2Style.blur_barrier())
	panel = Hub2Box.new()
	panel.glass(Hub2Style.GLASS_STRONG, Hub2Style.teal_a(0.45) if unlock != "" else Hub2Style.white_a(0.12), 1.0)
	panel.pad(22, 26)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(Hub2Style.px(14)))
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", int(Hub2Style.px(4)))
	hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(hv)
	var k := Hub2Text.new()
	k.setup(head, Hub2Style.CHAKRA, 700, 12, Hub2Style.TEAL if unlock != "" else Hub2Style.YELLOW, 0.24)
	hv.add_child(k)
	var t := Hub2Style.label(title, Hub2Style.CHAKRA, 700, 30, Hub2Style.TEXT)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hv.add_child(t)
	# Dr Brown et sa réplique.
	var sp := HBoxContainer.new()
	sp.add_theme_constant_override("separation", int(Hub2Style.px(18)))
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sp)
	var bust := TextureRect.new()
	bust.texture = HubRenders.character(HubRenders.SCIENTIST_BUST)
	bust.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bust.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bust.texture_filter = HubRenders.FILTER
	bust.custom_minimum_size = Hub2Style.pxv(BUST, BUST)
	bust.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sp.add_child(bust)
	var lv := HBoxContainer.new()
	lv.add_theme_constant_override("separation", int(Hub2Style.px(16)))
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sp.add_child(lv)
	var bar := ColorRect.new()
	bar.color = Hub2Style.TEAL
	bar.custom_minimum_size = Vector2(Hub2Style.px(3), 0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv.add_child(bar)
	var q := Hub2Style.label(Hub2LabKit.quoted(line), Hub2Style.BARLOW, 500, 17, Hub2Style.TEXT)
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lv.add_child(q)
	# Récompense : tuiles, XP, niveau.
	var rw := HBoxContainer.new()
	rw.add_theme_constant_override("separation", int(Hub2Style.px(16)))
	rw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(rw)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", int(Hub2Style.px(8)))
	th.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rw.add_child(th)
	var item: Variant = res.get("item")
	var specs := []
	if item is OwnedWeapon:
		specs.append(Hub2LabKit.weapon_tile(item))
	elif item is WeaponPart:
		specs.append(_part_tile(item, reward))
	if with_xp and int(res.get("xp", 0)) > 0:
		var xs := Hub2LabKit.xp_tile(pr, 0, false)
		var n := Hub2Style.num(int(res.xp))
		xs.cap = "+" + n
		xs.name = "+%s XP" % n
		xs.stats = [[Lang.t("Niveau", "Level"), "%d → %d" % [int(res.level_before), int(res.level_after)]]]
		xs.alt = Lang.t("%s points d’expérience", "%s experience points") % n
		specs.append(xs)
	tooltip = Hub2RewardTooltip.new()
	for s in specs:
		var tile := Hub2RewardTile.new()
		tile.setup(s)
		tile.tip.connect(_on_tip)
		th.add_child(tile)
		tiles.append(tile)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", int(Hub2Style.px(4)))
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rw.add_child(info)
	if not specs.is_empty() and (item is OwnedWeapon or item is WeaponPart):
		var ks := Hub2Text.new()
		ks.setup(String(specs[0].kind), Hub2Style.CHAKRA, 700, 11, specs[0].color, 0.16)
		info.add_child(ks)
		var nm := Hub2Text.new()
		nm.setup(String(specs[0].name), Hub2Style.CHAKRA, 700, 20, Hub2Style.TEXT)
		info.add_child(nm)
	if with_xp:
		var xr := HBoxContainer.new()
		xr.add_theme_constant_override("separation", int(Hub2Style.px(10)))
		xr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.add_child(xr)
		var xt := Hub2Text.new()
		xt.setup("+%s XP" % Hub2Style.num(int(res.get("xp", 0))), Hub2Style.MONO, 700, 16, Hub2Style.YELLOW)
		xr.add_child(xt)
		level_text = Lang.t("Niveau %d → %d", "Level %d → %d") % [int(res.level_before), int(res.level_after)]
		var lt := Hub2Style.label(level_text, Hub2Style.BARLOW, 500, 15, Hub2Style.text_a(0.8))
		xr.add_child(lt)
		if int(res.get("levels", 0)) > 0:
			var tag := Hub2Box.new()
			tag.flat(Hub2Style.YELLOW)
			tag.pad(3, 10)
			tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var tt := Hub2Text.new()
			tt.setup(Lang.t("NIVEAU SUPÉRIEUR", "LEVEL UP"), Hub2Style.CHAKRA, 700, 12, Hub2Style.INK, 0.14)
			tag.add_child(tt)
			xr.add_child(tag)
	if unlock != "":
		var ul := Hub2Style.label(unlock, Hub2Style.BARLOW, 500, 15, Hub2Style.TEAL)
		ul.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(ul)
	# Consommé, et ce qui reste.
	var used := PackedStringArray()
	var left := PackedStringArray()
	for kk in cost:
		used.append("%d %s" % [int(cost[kk]), Hub2LabKit.word(String(kk), int(cost[kk]))])
		var r := int(remaining.get(kk, 0))
		left.append("%d %s" % [r, Hub2LabKit.word(String(kk), r)])
	var cons := Hub2Style.label(Lang.t("Consommé : %s · il reste %s", "Used: %s · %s left") % [" + ".join(used), ", ".join(left)],
			Hub2Style.BARLOW, 400, 13, Hub2Style.text_a(0.6))
	cons.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(cons)
	# Boutons.
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", int(Hub2Style.px(10)))
	btns.alignment = BoxContainer.ALIGNMENT_END
	btns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(btns)
	if item is OwnedWeapon:
		target_uid = (item as OwnedWeapon).uid
	elif item is WeaponPart:
		target_uid = (item as WeaponPart).uid
	if target_uid != "":
		target_screen = "arsenal"
		primary_text = Lang.t("Voir dans l’arsenal", "See in the arsenal")
		primary_button = _button(primary_text.to_upper(), true,
				Lang.t("L’objet est rangé avec la pastille NOUVEAU.", "The item is stored with a NEW badge."))
		primary_button.pressed.connect(_go)
		btns.add_child(primary_button)
	close_button = _button(Lang.t("FERMER", "CLOSE"), false, Lang.t("Revenir à l’écran.", "Back to the screen."))
	close_button.pressed.connect(close)
	btns.add_child(close_button)
	add_child(tooltip)
	var list := [primary_button, close_button].filter(func(b): return b != null)
	for i in list.size():
		var b: Hub2Button = list[i]
		var prev: Hub2Button = list[(i - 1 + list.size()) % list.size()]
		var nxt: Hub2Button = list[(i + 1) % list.size()]
		b.focus_neighbor_left = b.get_path_to(prev)
		b.focus_neighbor_right = b.get_path_to(nxt)
		b.focus_previous = b.focus_neighbor_left
		b.focus_next = b.focus_neighbor_right
	for tile in tiles:
		(tile as Control).focus_mode = Control.FOCUS_NONE
	visible = true
	resized.connect(_place)
	panel.minimum_size_changed.connect(_place)
	_place()
	(list[0] as Hub2Button).grab_focus.call_deferred()
	Audio.play_ui("menu_whoosh", -12.0)


## Tuile d'une pièce reçue : modificateurs exacts dans l'infobulle.
func _part_tile(p: WeaponPart, reward: Dictionary) -> Dictionary:
	var q := String(reward.get("quality", Hub2LabKit.quality_of_mods(p.mods)))
	var s := Hub2LabKit.part_tile(q, p.level)
	s.name = Lang.t("Pièce niv. %d", "Part lvl %d") % p.level
	var stats := []
	for m in p.mods:
		var n: Array = Hub2LabKit.MOD_WORDS.get(String(m), [String(m), String(m)])
		var val := float(p.mods[m])
		stats.append([Hub2LabKit.capitalize(Lang.t(n[0], n[1])), "%s%d %%" % ["+" if val >= 0.0 else "−", roundi(absf(val) * 100.0)]])
	s.stats = stats
	return s


func _button(text: String, primary: bool, hint_text: String) -> Hub2Button:
	var b := Hub2Button.new()
	b.hint = hint_text
	if primary:
		b.box.flat(Hub2Style.YELLOW)
		b.box.chamfer(10)
	else:
		b.box.flat(Color(0, 0, 0, 0), Hub2Style.text_a(0.4), 1.0)
	b.box.pad(0, 18)
	b.custom_minimum_size.y = Hub2Style.px(40)
	var t := Hub2Text.new()
	t.setup(text, Hub2Style.CHAKRA, 700, 14, Hub2Style.INK if primary else Hub2Style.TEXT, 0.14)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_content(t)
	b.focus_entered.connect(func():
		if hub:
			hub.call("set_hint", b.hint))
	return b


func _on_tip(tile: Hub2RewardTile, on: bool) -> void:
	tooltip.show_for(tile if on else null)


## Panneau centré dans la place au-dessus des invites.
func _place() -> void:
	if panel == null:
		return
	var w := minf(Hub2Style.px(WIDTH), size.x - Hub2Style.px(32))
	panel.size = Vector2(w, 0)
	panel.custom_minimum_size.x = w
	var s := panel.get_combined_minimum_size()
	panel.size = s
	panel.position = Vector2(roundf((size.x - s.x) * 0.5), roundf(maxf((size.y - s.y) * 0.5, 0.0)))


## VOIR DANS L'ARSENAL : ferme et ouvre l'écran de l'objet (qui le
## sélectionne s'il le sait : méthode show_item(uid)).
func _go() -> void:
	var h := hub
	var uid := target_uid
	var screen := target_screen
	close()
	if h and screen != "":
		h.call("open", screen)
		var panels: Dictionary = h.get("panels") if "panels" in h else {}
		var p: Object = panels.get(screen)
		if p and p.has_method("show_item"):
			p.call("show_item", uid)


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and panel \
			and not panel.get_global_rect().has_point(mb.global_position):
		accept_event()
		close()
