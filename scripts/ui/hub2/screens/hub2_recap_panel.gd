class_name Hub2RecapPanel
extends Hub2Panel
## Récapitulatif d'après partie (docs/hub_v2/Recap.dc.html) : XP qui grimpe,
## passage de niveau animé (lvlPop, lvlRing, lvlText, lvlFlash), détail de
## l'XP, butin gardé, contrat prêt. Sans barre du haut ni barre d'invites
## (pied de page propre : left 48, right 48, bottom 18) ; voile 0.62 ; <main>
## left 48, right 48, top 40, bottom 64.
## PROVISOIRE (cadre du hub v2) : titre sur un panneau de verre ; le contenu
## de la maquette reste à faire (docs/HUB_PLAN.md §9). B / Échap : LABO.


func build() -> void:
	add_placeholder(Hub2Screen.title_of(screen_id), Lang.t("Écran à venir (maquette validée).", "Screen coming soon (approved mockup)."))


func veil() -> Dictionary:
	return {"color": Hub2Style.shade(0.62)}


func shows_top_bar() -> bool:
	return false


func shows_prompts() -> bool:
	return false


func prompts() -> Array:
	return [[Hub2Input.ACCEPT, Lang.t("Continuer", "Continue")]]


## <main> du récapitulatif : left 48, right 48, top 40, bottom 64.
func content_margins() -> Vector4:
	return Vector4(Hub2Style.px(48), Hub2Style.px(40), Hub2Style.px(48), Hub2Style.px(64))


func back() -> bool:
	hub.call("open", "lab")
	return true
