class_name Hub2Panel
extends Control
## Écran du hub v2 (une maquette docs/hub_v2/*.dc.html) : LABO, LABO ›
## CONTRATS, LABO › ÉCHANGES, ARSENAL, INVENTAIRE, CODEX, JOUER (solo /
## coop), récapitulatif d'après partie. Le cadre (fond 3D, voile, barre du
## haut, fil d'Ariane, invites, navigation) est fourni par Hub2Screen ; le
## panneau ne dessine QUE le contenu de sa maquette.
##
## Le panneau occupe tout l'écran (1280 × 720 logiques à 100 %, ancré plein
## cadre, souris ignorée sur le fond) : il place ses éléments aux positions de
## la maquette, en général dans content_rect() (le <main> : left 28, right 28,
## top 96 ou 92 + fil d'Ariane, bottom 60), avec Hub2Style.px / fs.
##
## API (à surcharger ; docs/HUB_PLAN.md §9) :
##   - build() : construire le contenu (une fois, au premier affichage ;
##     `hub`, profile(), la taille des menus sont prêts). Le hub entier est
##     reconstruit si la taille des menus change ;
##   - refresh() : le profil a changé (hub.save_profile / reload_profile) ;
##   - shown() / hidden() : écran affiché / quitté (le panneau reste en vie) ;
##   - first_focus() : élément qui reçoit le focus à l'affichage ;
##   - prompts() : invites [[Hub2Input.ACCEPT, texte], …] (touches standard)
##     ou [[id, texte, touches_clavier, boutons_manette]] (action propre,
##     cliquée -> on_prompt(id)) ; hub.refresh_prompts() quand elles changent ;
##   - help() : texte d'aide à gauche des invites (le focus d'un bouton peut le
##     remplacer : hub.set_hint(t), "" pour revenir à help()) ;
##   - back() : B / Échap / clic droit ; vrai si consommé (fermer une fiche) ;
##     faux : le hub remonte (sous-écran -> parent, onglet -> LABO, LABO ->
##     menu du hub, JOUER -> écran d'avant) ;
##   - handle_input(event) : reçu AVANT la navigation du hub ; vrai si
##     consommé ;
##   - badge() : pastille jaune sur l'onglet de cet écran ;
##   - veil() : voile sur le fond 3D (Hub2Veil : plein ou dégradé) ;
##   - shows_top_bar() / shows_prompts() : cadre affiché (récapitulatif : non).
## Côté hub : hub.open(id), hub.back(), hub.profile, hub.save_profile(),
## hub.set_hint(t), hub.refresh_prompts(), hub.refresh_badges(), hub.menu.

## Hôte (Hub2Screen).
var hub: Node
## Identifiant de l'écran (Hub2Screen.SCREENS).
var screen_id := ""
## build() déjà fait.
var built := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Profil du joueur (lu par le hub à l'ouverture, partagé par les écrans).
func profile() -> PlayerProfile:
	return hub.get("profile") if hub else null


func build() -> void:
	pass


func refresh() -> void:
	pass


func shown() -> void:
	pass


func hidden() -> void:
	pass


func first_focus() -> Control:
	return null


func prompts() -> Array:
	return [[Hub2Input.ACCEPT, Lang.t("Choisir", "Select")], [Hub2Input.BACK, Lang.t("Retour", "Back")]]


func help() -> String:
	return ""


func back() -> bool:
	return false


func handle_input(_event: InputEvent) -> bool:
	return false


## Invite propre à l'écran cliquée (identifiant non standard).
func on_prompt(_id: String) -> void:
	pass


func badge() -> bool:
	return false


## Voile sur le fond 3D (voir Hub2Veil) ; par défaut celui des onglets
## (rgba(8, 9, 11, 0.35)).
func veil() -> Dictionary:
	return {"color": Hub2Style.shade(0.35)}


func shows_top_bar() -> bool:
	return true


func shows_prompts() -> bool:
	return true


## Zone <main> de la maquette (pixels du panneau, à l'échelle) : left 28,
## right 28, bottom 60 ; top 96 (onglets) ou, sous le fil d'Ariane, 92 +
## sa hauteur + 14 (sous-écrans).
func content_rect() -> Rect2:
	var m := content_margins()
	return Rect2(m.x, m.y, size.x - m.x - m.z, size.y - m.y - m.w)


## Marges de <main> : gauche, haut, droite, bas (pour des ancres plein cadre :
## offset_left = x, offset_top = y, offset_right = -z, offset_bottom = -w).
func content_margins() -> Vector4:
	var side := Hub2Style.px(Hub2Style.SIDE)
	var top := Hub2Style.px(Hub2Style.MAIN_TOP)
	if hub and hub.call("is_sub_screen", screen_id):
		top = Hub2Style.px(Hub2Style.MAIN_TOP_SUB) + float(hub.call("crumb_height")) + Hub2Style.px(Hub2Style.CRUMB_GAP)
	return Vector4(side, top, side, Hub2Style.px(Hub2Style.MAIN_BOTTOM))


## Pose `c` sur toute la zone <main> (ancres plein cadre + marges) et
## l'ajoute au panneau.
func add_main(c: Control) -> Control:
	var m := content_margins()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = m.x
	c.offset_top = m.y
	c.offset_right = -m.z
	c.offset_bottom = -m.w
	add_child(c)
	return c


## Écran provisoire (en attendant son contenu) : panneau de verre sur la zone
## <main> avec le titre de l'écran et une note. À retirer par l'écran réel.
func add_placeholder(title: String, note := "") -> Hub2Box:
	var box := Hub2Box.new()
	box.glass()
	box.pad(24, 26)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", int(Hub2Style.px(10)))
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(v)
	var t := Hub2Text.new()
	t.setup(title, Hub2Style.CHAKRA, 700, 52, Hub2Style.TEXT, 0.02)
	t.line_height = 52
	t.align = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	if note != "":
		var n := Hub2Style.label(note, Hub2Style.BARLOW, 400, 17, Hub2Style.text_a(0.7))
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(n)
	add_main(box)
	return box
