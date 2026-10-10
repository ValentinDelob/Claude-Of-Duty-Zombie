class_name HubPanel
extends Control
## Panneau du hub : le contenu d'un onglet (LABO, ARSENAL, PIÈCES, CONTRATS,
## ÉCHANGES, DÉPART, PARTIE). Chaque panneau est INDÉPENDANT (HUB_PLAN §3.9) :
## il ne connaît que le profil et son hôte `hub` (HubScreen aujourd'hui, le
## laboratoire 3D plus tard, qui l'ouvrira en surimpression). Il occupe toute
## la zone centrale (1248 × 556 à 100 %, sous les onglets, au-dessus des
## invites) et dessine ses propres panneaux (HubBox).
##
## API pour les lots C, D et E (docs/HUB_PLAN.md §8) :
##   - enregistrer le panneau : une ligne dans HubScreen.PANELS
##     (identifiant d'onglet -> chemin du script), ou
##     HubScreen.register_panel(id, script) (tests) ;
##   - build() : construire le contenu (appelé une fois, `hub` et `profile`
##     prêts, taille des menus déjà connue : utiliser HubStyle.px / fs) ;
##   - refresh() : le profil a changé (hub.profile_changed), mettre à jour ;
##   - first_focus() : élément qui reçoit le focus à l'ouverture de l'onglet
##     (premier élément utile, HUB_PLAN §4.1) ;
##   - prompts() : invites de la barre du bas, [[HubPrompts.ACCEPT, texte], …] ;
##     hub.refresh_prompts() quand elles changent (fiche ouverte…) ;
##   - back() : Échap / B / clic droit ; vrai si le panneau l'a consommé
##     (fermer une fiche, annuler un deuxième appui) ; faux : le hub ouvre son
##     menu ;
##   - handle_input(event) : touches propres (Tab / Y : filtre, Suppr / R / X :
##     action secondaire…) ; vrai si consommé ;
##   - shown() / hidden() : onglet affiché / quitté (le panneau reste en vie
##     entre deux visites : le salon de l'onglet PARTIE reste connecté, D4) ;
##   - badge() : nombre de la pastille de l'onglet (0 : aucune) ;
##   - hub.set_hint(t), hub.select_tab(id), hub.save_profile(),
##     hub.reload_profile(), hub.menu (MenuHost : show_screen, launch…).

## Hôte (HubScreen).
var hub: Node
## Identifiant de l'onglet (« lab », « arsenal »…).
var tab_id := ""


## Profil du joueur (lu par le hub à l'ouverture, partagé par les panneaux).
func profile() -> PlayerProfile:
	return hub.profile if hub else null


func build() -> void:
	pass


func refresh() -> void:
	pass


func first_focus() -> Control:
	return null


func prompts() -> Array:
	return [[HubPrompts.ACCEPT, Lang.t("Choisir", "Select")], [HubPrompts.TABS, Lang.t("Onglets", "Tabs")],
		[HubPrompts.MENU, Lang.t("Menu du hub", "Hub menu")]]


func back() -> bool:
	return false


func handle_input(_event: InputEvent) -> bool:
	return false


func shown() -> void:
	pass


func hidden() -> void:
	pass


func badge() -> int:
	return 0


## Bouton du hub dont l'aide passe dans la barre d'invites.
func hub_button(t: String, cb: Callable, kind := HubButton.NORMAL, hint := "") -> HubButton:
	var b := HubButton.make(t, cb, kind, hint)
	b.focus_entered.connect(func():
		if hub:
			hub.set_hint(hint))
	return b
