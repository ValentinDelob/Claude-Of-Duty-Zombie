class_name Hub2CodexPanel
extends Hub2Panel
## CODEX (docs/hub_v2/Codex.dc.html) : rendus des ennemis (silhouette noire si
## inconnu), fiche avec taux de butin par échantillon.
## PROVISOIRE (cadre du hub v2) : titre sur un panneau de verre ; le contenu
## de la maquette reste à faire (docs/HUB_PLAN.md §9).


func build() -> void:
	add_placeholder(Hub2Screen.title_of(screen_id), Lang.t("Écran à venir (maquette validée).", "Screen coming soon (approved mockup)."))


func prompts() -> Array:
	return [[Hub2Input.ACCEPT, Lang.t("Détails", "Details")], [Hub2Input.BACK, Lang.t("Retour", "Back")]]


func help() -> String:
	return Lang.t("Les fiches sombres attendent ta première rencontre.", "The dark entries await your first encounter.")
