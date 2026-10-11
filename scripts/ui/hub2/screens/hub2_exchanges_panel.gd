class_name Hub2ExchangesPanel
extends Hub2Panel
## LABO › ÉCHANGES (docs/hub_v2/Echanges.dc.html) : catalogue d'objets précis
## contre des échantillons.
## PROVISOIRE (cadre du hub v2) : titre sur un panneau de verre ; le contenu
## de la maquette reste à faire (docs/HUB_PLAN.md §9).


func build() -> void:
	add_placeholder(Hub2Screen.title_of(screen_id), Lang.t("Écran à venir (maquette validée).", "Screen coming soon (approved mockup)."))


func prompts() -> Array:
	return [[Hub2Input.ACCEPT, Lang.t("Échanger", "Trade")], [Hub2Input.FILTER, Lang.t("Filtrer", "Filter")],
		[Hub2Input.BACK, Lang.t("Retour", "Back")]]


func help() -> String:
	return Lang.t("L’objet obtenu est à ton niveau actuel.", "The item you get is at your current level.")
