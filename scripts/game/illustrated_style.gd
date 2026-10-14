class_name IllustratedStyle
extends RefCounted
## Style « ILLUSTRÉ » (prototype, OPTIONS > VIDÉO > STYLE ; Settings.art_style,
## CLASSIQUE par défaut) : rendu façon planche peinte (docs/art/
## gemini_target.webp, docs/ART_DIRECTION.md « Style illustré »).
##
## Uniquement du POST-TRAITEMENT plein écran (IllustratedPost) : aucun
## matériau, aucun shader du jeu ni le contour noir (ScreenOutline) ne
## changent ; le style CLASSIQUE est exactement le rendu de référence.

## Forcé par les tests (-1 : suivre Settings.art_style).
static var debug_force := -1


## Le style illustré est-il demandé ?
static func active() -> bool:
	if debug_force >= 0:
		return debug_force == Settings.ArtStyle.ILLUSTRATED
	return Settings.art_style == Settings.ArtStyle.ILLUSTRATED
