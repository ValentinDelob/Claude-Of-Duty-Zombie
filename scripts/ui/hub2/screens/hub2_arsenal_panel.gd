class_name Hub2ArsenalPanel
extends Hub2Panel
## ARSENAL (docs/hub_v2/Arsenal.dc.html) : rail horizontal des niveaux, armes
## d'un même niveau empilées verticalement (◄ ► niveau, ▲ ▼ même niveau), vue
## d'ensemble, sous-onglet PIÈCES, fiche (statistiques en icônes, valeur de
## base + modificateur vert / rouge sans unité).
## PROVISOIRE (cadre du hub v2) : titre sur un panneau de verre ; le contenu
## de la maquette reste à faire (docs/HUB_PLAN.md §9).


func build() -> void:
	add_placeholder(Hub2Screen.title_of(screen_id), Lang.t("Écran à venir (maquette validée).", "Screen coming soon (approved mockup)."))


func prompts() -> Array:
	return [[Hub2Input.ACCEPT, Lang.t("Installer", "Install")], [Hub2Input.SECONDARY, Lang.t("Recycler", "Recycle")],
		[Hub2Input.FILTER, Lang.t("Filtrer", "Filter")], [Hub2Input.BACK, Lang.t("Retour", "Back")]]


func help() -> String:
	return Lang.t("◄ ► change de niveau · ▲ ▼ parcourt les armes d’un même niveau",
			"◄ ► changes level · ▲ ▼ browses the weapons of one level")
