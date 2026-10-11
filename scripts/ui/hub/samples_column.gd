class_name HubSamplesColumn
extends HubBox
## Colonne RÉSERVE des onglets CONTRATS et ÉCHANGES (maquette, écrans 5, 7 et
## 11 : panneau de 300 px à droite) : une ligne par sorte d'échantillon
## (icône, nom, quantité en Impact 22), puis un texte d'aide qui suit
## l'élément choisi (conséquence d'une remise ou d'un échange sur les autres
## contrats actifs, rappel des règles). Lecture seule du profil.
##
## Sortes montrées : celles d'un groupe connu (un échantillon en réserve) ou
## demandé par un contrat, une proposition ou un échange affiché ; sinon tous
## les groupes (rien n'est caché quand le profil est vide).
##
## Aussi : les mots des échantillons accordés en nombre (« 4 crocs »,
## « 1 touffe », « IL MANQUE 3 COLLIERS ») pour les deux onglets.

## Mots des sortes : [FR singulier, FR pluriel, EN singulier, EN pluriel]
## (maquette : « IL MANQUE 1 TOUFFE », « 1 TUFT OF FUR MISSING »).
const WORDS := {
	"dog_fang": ["croc", "crocs", "fang", "fangs"],
	"dog_fur": ["touffe", "touffes", "tuft of fur", "tufts of fur"],
	"dog_collar": ["collier", "colliers", "collar", "collars"],
	"brancard_strap": ["sangle", "sangles", "leather strap", "leather straps"],
	"brancard_bracelet": ["bracelet", "bracelets", "ID bracelet", "ID bracelets"],
}

## Sorte -> Label de la quantité (tests).
var qty_labels: Dictionary = {}
var note: RichTextLabel
## Second paragraphe (rappel des règles), 8 px sous le premier.
var note2: RichTextLabel
var _rows: VBoxContainer


func _init() -> void:
	super(Lang.t("RÉSERVE", "SAMPLES"))
	_rows = HubBox.vbox(0)
	content.add_child(_rows)
	var v := HubBox.vbox(8)
	note = rich("", 13, HubStyle.DIM, true)
	note2 = rich("", 13, HubStyle.DIM, true)
	v.add_child(note)
	v.add_child(note2)
	content.add_child(HubBox.pad(v, 12, 12, 12, 12))


## Relit les quantités ; `wanted` : sortes demandées à l'écran (montrées
## même jamais obtenues).
func show_samples(pr: PlayerProfile, wanted: Dictionary = {}) -> void:
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	qty_labels.clear()
	var groups := []
	for g in LootRules.SAMPLES:
		var shown := false
		for s in LootRules.SAMPLES[g]:
			if pr.sample_count(String(s[0])) > 0 or wanted.has(String(s[0])):
				shown = true
		if shown:
			groups.append(g)
	if groups.is_empty():
		groups = LootRules.SAMPLES.keys()
	for g in groups:
		for s in LootRules.SAMPLES[g]:
			_rows.add_child(_row(String(s[0]), HubLabPanel.sentence_case(Lang.t(s[1], s[2])), pr.sample_count(String(s[0]))))


## Texte d'aide sous la réserve (BBCode : [b]…[/b] en clair, [bad]…[/bad]
## en rouge).
func set_note(bbcode: String, second := "") -> void:
	note.text = style_bbcode(bbcode)
	note2.text = style_bbcode(second)
	note2.visible = second != ""


func _row(kind: String, sample_name: String, qty: int) -> HubRow:
	var r := HubRow.new(HubRow.SAMPLE)
	r.box.add_child(HubIcon.make(HubIcon.sample_art(kind), 4))
	var n := HubStyle.label(sample_name, 15, HubStyle.PAPER)
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	n.clip_text = true
	r.box.add_child(n)
	var q := HubStyle.label(str(qty), 22, HubStyle.PAPER, "impact", true)
	r.box.add_child(q)
	qty_labels[kind] = q
	return r


# --------------------------------------------------------------------------
# Mots et textes
# --------------------------------------------------------------------------

## « 4 crocs », « 1 touffe », « 0 touffe » (FR : 0 et 1 au singulier),
## « 1 fang », « 0 fangs ». `upper` : en capitales.
static func words(kind: String, n: int, upper := false) -> String:
	var w: Array = WORDS.get(kind, [])
	var t := ""
	if w.is_empty():
		t = "%d %s" % [n, LootRules.sample_name(kind).to_lower()]
	elif Lang.is_en():
		t = "%d %s" % [n, w[2] if n == 1 else w[3]]
	else:
		t = "%d %s" % [n, w[0] if n <= 1 else w[1]]
	return t.to_upper() if upper else t


## Liste lisible : « 4 crocs », « 4 crocs et 2 touffes », « 3 crocs, 3
## touffes et 3 colliers » (EN : « and »).
static func join_words(items: PackedStringArray, sep_last := "") -> String:
	if items.size() <= 1:
		return "".join(items)
	var last := sep_last if sep_last != "" else Lang.t(" et ", " and ")
	return ", ".join(items.slice(0, items.size() - 1)) + last + items[items.size() - 1]


## Coût d'une demande en mots : {sorte: n} -> « 4 colliers + 2 touffes ».
static func cost_words(cost: Dictionary, upper := false, sep := " + ") -> String:
	var items := PackedStringArray()
	for k in cost:
		items.append(words(String(k), int(cost[k]), upper))
	return sep.join(items)


## Texte du bouton grisé quand il manque des échantillons : « IL MANQUE 1
## TOUFFE » (« 1 TUFT OF FUR MISSING ») ; plusieurs sortes : « IL MANQUE 5
## ÉCHANTILLONS ». "" : rien ne manque.
static func missing_text(pr: PlayerProfile, cost: Dictionary) -> String:
	var kinds := []
	var total := 0
	for k in cost:
		var miss := int(cost[k]) - pr.sample_count(String(k))
		if miss > 0:
			kinds.append([String(k), miss])
			total += miss
	if kinds.is_empty():
		return ""
	if kinds.size() == 1:
		var w := words(kinds[0][0], kinds[0][1], true)
		return Lang.t("IL MANQUE %s" % w, "%s MISSING" % w)
	return Lang.t("IL MANQUE %d ÉCHANTILLONS" % total, "%d SAMPLES MISSING" % total)


## Échantillons restants après avoir payé `cost` : {sorte: n}.
static func remaining_after(pr: PlayerProfile, cost: Dictionary) -> Dictionary:
	var out := {}
	for k in cost:
		out[String(k)] = maxi(pr.sample_count(String(k)) - int(cost[k]), 0)
	return out


## Texte riche du hub (RichTextLabel ajusté à son contenu, polices des
## menus ; [b] en gras).
static func rich(bbcode: String, size: int, color := HubStyle.PAPER, wrap := false) -> RichTextLabel:
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.scroll_active = false
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := HubStyle.fs(size)
	t.add_theme_font_override("normal_font", HubStyle.font("ui"))
	t.add_theme_font_override("bold_font", HubStyle.font("bold"))
	t.add_theme_font_size_override("normal_font_size", s)
	t.add_theme_font_size_override("bold_font_size", s)
	t.add_theme_color_override("default_color", color)
	t.add_theme_constant_override("line_separation", int(HubStyle.px(2)))
	if not wrap:
		t.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	t.text = style_bbcode(bbcode)
	return t


## Balises du hub -> BBCode : [b] en couleur papier, [bad] en rouge gras,
## [ok] en vert.
static func style_bbcode(t: String) -> String:
	return t.replace("[b]", "[b][color=#%s]" % HubStyle.PAPER.to_html(false)).replace("[/b]", "[/color][/b]") \
		.replace("[bad]", "[b][color=#%s]" % HubStyle.BAD.to_html(false)).replace("[/bad]", "[/color][/b]") \
		.replace("[ok]", "[color=#%s]" % HubStyle.OK.to_html(false)).replace("[/ok]", "[/color]")


## Échappe un texte venu des données pour le BBCode.
static func esc(t: String) -> String:
	return t.replace("[", "[lb]")
