class_name Tag3D
extends RefCounted
## Étiquettes 3D du jeu (Label3D : nom au-dessus des coéquipiers, « À TERRE »,
## butin au sol, panneaux du piège électrique et du poste central...) : une
## seule police, la police en cubes du jeu (CubeFont), lisible et en harmonie
## avec le style cubique (docs/ART_DIRECTION.md « Étiquettes 3D »).
##
## Appliqué à TOUTE Label3D qui entre dans l'arbre (Router branche
## on_node_added sur SceneTree.node_added) : le code qui crée une étiquette
## garde ses réglages (taille, couleur, billboard...) sans avoir à penser à la
## police. Méta « tag3d_keep » sur une Label3D : laissée telle quelle.

## Les capitales de CubeFont occupent 7/10 de la taille de police, celles des
## polices système ~3/4 : la taille est relevée d'un peu plus (les cubes
## fins se lisent moins bien de loin qu'une police pleine).
const SIZE_GAIN := 1.2
## Liseré : celui de la police (cuit, noir) ; on garde un contour fin pour les
## caractères absents de CubeFont (repli en police système, ex. « ✚ »).
const FALLBACK_OUTLINE := 6


static func on_node_added(n: Node) -> void:
	if n is Label3D:
		style(n as Label3D)


## Police en cubes sur `l` (une seule fois par étiquette).
static func style(l: Label3D) -> void:
	if l.has_meta("tag3d_keep") or l.has_meta("tag3d"):
		return
	l.set_meta("tag3d", true)
	l.font = CubeFont.font()
	l.font_size = roundi(l.font_size * SIZE_GAIN)
	# La police est cuite en grand (cubes de 12 px) puis réduite : mipmaps.
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	l.outline_size = mini(l.outline_size, FALLBACK_OUTLINE)
	l.outline_modulate = Color(0, 0, 0, 0.9)
