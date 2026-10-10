class_name HubPrompts
extends Control
## Barre d'invites en bas du hub (classe .prompts de la maquette, 36 px) :
## actions possibles avec la touche du périphérique utilisé en dernier
## (clavier ou manette, Settings.using_pad ; noms Xbox ou PlayStation par
## PadNames), recalculées sur Settings.input_device_changed ; à droite, texte
## d'aide de l'élément qui a le focus (comme set_hint des menus).
##
## Chaque invite se clique (la souris peut tout faire) : elle déclenche la
## même action que sa touche.
##
## Invites standard (HUB_PLAN §4.1) : identifiant -> touches du clavier,
## boutons de la manette. Les panneaux donnent [identifiant, texte].

const ACCEPT := "accept"
const BACK := "back"
const TABS := "tabs"
const MENU := "menu"
## Action secondaire (retirer, recycler, abandonner) : Suppr ou R / X.
const SECONDARY := "secondary"
## Filtre / tri : Tab / Y.
const FILTER := "filter"
## Tri (onglet ARSENAL, PIÈCES) : R / X.
const SORT := "sort"

## Hauteur à 100 %.
const HEIGHT := 36.0

## Invites affichées : [{id, text, keys: PackedStringArray, pads: Array}].
var items: Array = []
var hint := "":
	set(v):
		hint = v
		queue_redraw()
## Action d'une invite cliquée (identifiant).
signal prompt_clicked(id: String)

var _hit: Array = []  # [Rect2, id]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(0, HubStyle.px(HEIGHT))
	Settings.input_device_changed.connect(func(_p): queue_redraw())


## Touches du clavier de l'invite standard `id`.
static func keys_of(id: String) -> PackedStringArray:
	match id:
		ACCEPT: return PackedStringArray([Lang.t("Entrée", "Enter")])
		BACK, MENU: return PackedStringArray([Lang.t("Échap", "Esc")])
		TABS: return PackedStringArray([physical_key_name(KEY_Q), physical_key_name(KEY_E)])
		SECONDARY: return PackedStringArray([Lang.t("Suppr", "Del")])
		FILTER: return PackedStringArray(["Tab"])
		SORT: return PackedStringArray([physical_key_name(KEY_R)])
	return PackedStringArray()


## Boutons de la manette de l'invite standard `id`.
static func pads_of(id: String) -> Array:
	match id:
		ACCEPT: return [JOY_BUTTON_A]
		BACK: return [JOY_BUTTON_B]
		MENU: return [JOY_BUTTON_START]
		TABS: return [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER]
		SECONDARY, SORT: return [JOY_BUTTON_X]
		FILTER: return [JOY_BUTTON_Y]
	return []


## Nom d'une touche physique dans la disposition du clavier (Q s'affiche A en
## AZERTY), comme Settings.code_label.
static func physical_key_name(physical: int) -> String:
	return Settings.code_label(Settings.key_code(physical))


## Remplace les invites : `list` = [[identifiant, texte], …].
func set_items(list: Array) -> void:
	items.clear()
	for it in list:
		if it is Array and it.size() >= 2:
			items.append({"id": String(it[0]), "text": String(it[1])})
	queue_redraw()


## Textes affichés (tests) : « Entrée Choisir », « LB RB Onglets »…
func describe() -> PackedStringArray:
	var out := PackedStringArray()
	for it in items:
		var names := PackedStringArray()
		if Settings.using_pad:
			for b in pads_of(it.id):
				names.append(PadNames.button_label(b, Settings.pad_style()))
		else:
			names = keys_of(it.id)
		out.append(" ".join(names) + " " + String(it.text))
	return out


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var b := HubStyle.px(2)
	draw_rect(r, HubStyle.BAR_BG)
	draw_rect(Rect2(0, 0, r.size.x, b), HubStyle.BLACK)
	_hit.clear()
	var x := HubStyle.px(16)
	var kh := HubStyle.px(22)
	var ky := b + (r.size.y - b - kh) * 0.5
	var f := HubStyle.font("ui")
	var s := HubStyle.fs(14)
	for it in items:
		var x0 := x
		if Settings.using_pad:
			for p in pads_of(it.id):
				x += HubKey.draw_item(self, Vector2(x, ky), "", p) + HubStyle.px(6)
		else:
			for k in keys_of(it.id):
				x += HubKey.draw_item(self, Vector2(x, ky), k, -1) + HubStyle.px(6)
		var t: String = it.text
		draw_string(f, Vector2(x, HubStyle.baseline(f, s, b, r.size.y - b)), t, HORIZONTAL_ALIGNMENT_LEFT, -1, s, HubStyle.PLASTER)
		x += HubStyle.text_width(t, f, s)
		_hit.append([Rect2(x0, b, x - x0, r.size.y - b), it.id])
		x += HubStyle.px(18)
	if hint != "":
		var hs := HubStyle.fs(13)
		var room := r.size.x - x - HubStyle.px(16)
		var maxw := minf(HubStyle.px(520), room)
		if maxw > HubStyle.px(40):
			var shown := _ellipsis(hint, f, hs, maxw)
			var hw := HubStyle.text_width(shown, f, hs)
			draw_string(f, Vector2(r.size.x - HubStyle.px(16) - hw, HubStyle.baseline(f, hs, b, r.size.y - b)), shown,
					HORIZONTAL_ALIGNMENT_LEFT, -1, hs, HubStyle.DIM)


## Texte coupé avec « … » pour tenir dans `w`.
static func _ellipsis(t: String, f: Font, s: int, w: float) -> String:
	if HubStyle.text_width(t, f, s) <= w:
		return t
	var n := t.length()
	while n > 0 and HubStyle.text_width(t.left(n) + "…", f, s) > w:
		n -= 1
	return t.left(n) + "…"


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		for h in _hit:
			if (h[0] as Rect2).has_point(mb.position):
				accept_event()
				prompt_clicked.emit(String(h[1]))
				return
