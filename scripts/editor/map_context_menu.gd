class_name MapContextMenu
extends PopupMenu
## MENU DU CLIC DROIT de l'éditeur de cartes (docs/MAP_AUTHORING.md § 2),
## ouvert dans toutes les vues (Dessus, élévations, 3D) quand aucun tracé ni
## glissement n'est en cours (sinon le clic droit les annule) : sur un
## élément non choisi, il est choisi d'abord (MapEditor.open_context_menu).
## Entrées en français ou en anglais avec leur raccourci, grisées (avec une
## bulle qui dit pourquoi) quand elles sont impossibles. Style : thème de
## l'éditeur (fenêtre fille de MapEditor).

enum { PREFAB, DUPLICATE, COPY, CUT, PASTE, ROTATE, DELETE, SELECT_ALL, DESELECT }

## [id, fr, en, raccourci (fr), raccourci (en)] ; null : séparateur.
const ENTRIES := [
	[PREFAB, "Créer une prefab…", "Create a prefab…", "Ctrl+G", "Ctrl+G"],
	null,
	[DUPLICATE, "Dupliquer", "Duplicate", "Ctrl+D", "Ctrl+D"],
	[COPY, "Copier", "Copy", "Ctrl+C", "Ctrl+C"],
	[CUT, "Couper", "Cut", "Ctrl+X", "Ctrl+X"],
	[PASTE, "Coller ici", "Paste here", "Ctrl+V", "Ctrl+V"],
	[ROTATE, "Pivoter de 90°", "Rotate 90°", "R", "R"],
	[DELETE, "Supprimer", "Delete", "Suppr", "Del"],
	null,
	[SELECT_ALL, "Tout sélectionner (étage)", "Select all (floor)", "Ctrl+A", "Ctrl+A"],
	[DESELECT, "Désélectionner", "Deselect", "Échap", "Esc"],
]

var ed: MapEditor
## Point du plan (m) pour « Coller ici » ; Vector2.INF : hors de la vue Dessus.
var paste_at := Vector2.INF


func _init() -> void:
	name = "ContextMenu"
	id_pressed.connect(_on_id)


## Libellés avec les raccourcis alignés en colonne (espaces ajoutés d'après la
## police du menu) : id -> texte.
func aligned_labels() -> Dictionary:
	var font := get_theme_font("font")
	var fs := get_theme_font_size("font_size")
	var out := {}
	var widest := 0.0
	for en in ENTRIES:
		if en != null:
			widest = maxf(widest, font.get_string_size(Lang.t(String(en[1]), String(en[2])), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var sp := maxf(font.get_string_size(" ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, 1.0)
	for en in ENTRIES:
		if en == null:
			continue
		var name_text := Lang.t(String(en[1]), String(en[2]))
		var w := font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var n := maxi(3, roundi((widest - w) / sp) + 4)
		out[int(en[0])] = name_text + " ".repeat(n) + Lang.t(String(en[3]), String(en[4]))
	return out


## État des entrées pour la sélection et le presse-papiers actuels :
## id -> "" (permise) ou la raison (fr / en) pour laquelle elle est grisée.
func states() -> Dictionary:
	var ids := ed.sel_ids()
	var none := Lang.t("Rien n'est sélectionné", "Nothing is selected")
	var has := not ids.is_empty()
	var out := {}
	var pf := MapPrefabTools.analyze(ed.doc, ids)
	if not has:
		out[PREFAB] = none
	elif ed.is_guest():
		out[PREFAB] = Lang.t("Seul l'hôte de la session change les prefabs de la carte", "Only the session host changes the map prefabs")
	elif (pf.parts as Array).is_empty():
		out[PREFAB] = Lang.t("Une prefab ne contient que du décor du catalogue posé au sol : la sélection n'en a pas", "A prefab only holds catalogue props placed on the floor: the selection has none")
	elif MapPrefabTools.floors_of(pf.parts).size() > 1:
		out[PREFAB] = MapPrefabTools.multi_floor_text()
	else:
		out[PREFAB] = ""
	for id in [DUPLICATE, COPY, CUT, DELETE, DESELECT]:
		out[id] = "" if has else none
	if not has:
		out[ROTATE] = none
	elif ids.size() == 1 and not MapTransform.can_rotate(ed.doc.find(ids[0])):
		out[ROTATE] = Lang.t("Cet élément suit son mur : déplacez-le plutôt", "This element follows its wall: move it instead")
	else:
		out[ROTATE] = ""
	if ed.clipboard.is_empty():
		out[PASTE] = Lang.t("Rien à coller : copiez d'abord (Ctrl+C)", "Nothing to paste: copy first (Ctrl+C)")
	elif paste_at == Vector2.INF:
		out[PASTE] = Lang.t("Collez dans la vue Dessus : sous la souris", "Paste in the Top view: under the mouse")
	else:
		out[PASTE] = ""
	var any := not (ed.doc.rooms_on(ed.floor_k).is_empty() and ed.doc.openings_on(ed.floor_k).is_empty() and ed.doc.objects_on(ed.floor_k).is_empty())
	out[SELECT_ALL] = "" if any else Lang.t("L'étage est vide", "The floor is empty")
	return out


## Remplit le menu et l'ouvre en `screen_pos` (pixels de l'écran) ; `at_m` :
## point du plan pour « Coller ici » (Vector2.INF : vue sans plan).
func open(screen_pos: Vector2, at_m: Vector2) -> void:
	paste_at = at_m
	clear()
	var st := states()
	var texts := aligned_labels()
	for en in ENTRIES:
		if en == null:
			add_separator()
			continue
		add_item(String(texts[int(en[0])]), int(en[0]))
		var i := get_item_index(int(en[0]))
		var why := String(st.get(int(en[0]), ""))
		set_item_disabled(i, why != "")
		set_item_tooltip(i, why)
	reset_size()
	position = Vector2i(screen_pos)
	popup()


func _on_id(id: int) -> void:
	if ed == null:
		return
	match id:
		PREFAB:
			ed.create_prefab_from_selection()
		DUPLICATE:
			ed.duplicate_selection()
		COPY:
			ed.copy_selected()
		CUT:
			ed.cut_selected()
		PASTE:
			ed.paste(paste_at)
		ROTATE:
			ed.rotate_selection()
		DELETE:
			ed.delete_selection()
		SELECT_ALL:
			ed.select_all()
		DESELECT:
			ed.select("")
