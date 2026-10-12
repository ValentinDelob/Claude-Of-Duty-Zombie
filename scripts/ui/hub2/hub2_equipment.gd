class_name Hub2Equipment
extends RefCounted
## Emplacements d'armes de départ du hub v2 : les trois cases de ÉQUIPEMENT
## (Partie.dc.html : rendu 52 px de haut, nom Chakra Petch 14 px 700, liseré
## haut 2 px de la rareté ; case libre en pointillés « + Emplacement libre »)
## et les petites cases des cartes de joueurs du salon (PartieCoop.dc.html :
## 32 px de haut, rendu 26 px). Règles du choix (au moins 1, au plus 3 armes
## de base distinctes, GAME_CONCEPT §4.10) : celles de l'ancien onglet DÉPART
## (toggle / remove_slot), ici sans interface.

## Couleur du liseré d'une arme de base (commune).
const BASE_RARITY := 0


## Nom affiché d'une arme (« M1912 », « BATTE »).
static func weapon_name(id: String) -> String:
	return HubGear.weapon_name(id).to_upper()


## Grande case (ÉQUIPEMENT) : arme `id`, ou case libre si "".
static func big_slot(id: String) -> Control:
	if id == "":
		# Pointillés dessinés par la case ; contenu centré (justify-content:
		# center), hauteur donnée par les cases voisines (même rangée).
		var free := Control.new()
		free.mouse_filter = Control.MOUSE_FILTER_IGNORE
		free.add_child(Hub2Ui.dashed_frame(Hub2Style.white_a(0.18)))
		var v := Hub2Ui.vbox(2)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		free.add_child(v)
		var plus := Hub2Text.new()
		plus.setup("+", Hub2Style.CHAKRA, 500, 26, Hub2Style.text_a(0.35))
		plus.line_height = 26
		plus.align = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(plus)
		var t := Hub2Text.new()
		t.setup(Lang.t("Emplacement libre", "Free slot"), Hub2Style.CHAKRA, 600, 13, Hub2Style.text_a(0.45))
		t.align = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(Hub2Ui.clipped(t))
		return free
	var b := Hub2Box.new()
	b.flat(Hub2Style.white_a(0.05), Hub2Style.rarity_color(BASE_RARITY), 0.0)
	b.border = Vector4(0, 2, 0, 0)
	b.border_color = Hub2Style.rarity_color(BASE_RARITY)
	b.pad(6, 8, 8, 8)
	var v2 := Hub2Ui.vbox(2)
	b.add_child(v2)
	var img := Hub2Render.new()
	img.texture = HubRenders.weapon(id)
	img.custom_minimum_size = Vector2(0, Hub2Style.px(52))
	img.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	img.shadow = Vector3(0, 4, 6)
	img.shadow_color = Color(0, 0, 0, 0.5)
	v2.add_child(img)
	var n := Hub2Text.new()
	n.setup(weapon_name(id), Hub2Style.CHAKRA, 700, 14, Hub2Style.TEXT)
	n.align = HORIZONTAL_ALIGNMENT_CENTER
	v2.add_child(n)
	return b


## Petite case d'une carte de joueur (salon) : rendu de 26 px, ou pointillés.
static func small_slot(id: String) -> Control:
	if id == "":
		var c := Control.new()
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.custom_minimum_size = Vector2(0, Hub2Style.px(32))
		c.add_child(Hub2Ui.dashed_frame(Hub2Style.white_a(0.15)))
		return c
	var b := Hub2Box.new()
	b.flat(Hub2Style.white_a(0.05), Hub2Style.rarity_color(BASE_RARITY), 0.0)
	b.border = Vector4(0, 2, 0, 0)
	b.border_color = Hub2Style.rarity_color(BASE_RARITY)
	# height 32 (box-sizing: border-box), padding 3 : rendu de 26 px sous le
	# liseré de 2 px (contenu centré).
	b.pad(3)
	b.custom_minimum_size = Vector2(0, Hub2Style.px(32))
	var img := Hub2Render.new()
	img.texture = HubRenders.weapon(id)
	img.custom_minimum_size = Vector2(0, Hub2Style.px(26))
	img.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_child(img)
	return b


## Rangée de trois cases (grid 3 colonnes, écart `gap`) pour la sélection
## `sel` (armes de départ ; moins de 3 : cases libres).
static func slots_row(sel: PackedStringArray, big: bool, gap: float) -> HBoxContainer:
	var h := Hub2Ui.hbox(gap)
	for i in BaseWeapons.MAX_START:
		var id := sel[i] if i < sel.size() else ""
		var c := big_slot(id) if big else small_slot(id)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_stretch_ratio = 1.0
		h.add_child(c)
	return h


# --------------------------------------------------------------------------
# Règles du choix (ancien onglet DÉPART)
# --------------------------------------------------------------------------

## Sélection après avoir ajouté / retiré l'arme de base `id` ; [] si refusé
## (dernière arme, trois emplacements pris). [nouvelle sélection, raison].
static func toggled(sel: PackedStringArray, id: String) -> Array:
	var out := Array(sel)
	if id in out:
		if out.size() <= BaseWeapons.MIN_START:
			return [PackedStringArray(), last_hint()]
		out.erase(id)
	else:
		if out.size() >= BaseWeapons.MAX_START:
			return [PackedStringArray(), Lang.t("Les trois emplacements sont pris : retire d’abord une arme.",
				"All three slots are taken: remove a weapon first.")]
		if not BaseWeapons.is_base(id):
			return [PackedStringArray(), ""]
		out.append(id)
	return [PackedStringArray(out), ""]


static func last_hint() -> String:
	return Lang.t("Il faut au moins une arme au départ.", "You need at least one starting weapon.")
