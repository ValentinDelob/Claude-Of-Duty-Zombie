class_name MapMarker
extends RefCounted
## Emplacement d'un objet de carte (achat mural, atout, boîte, interrupteur...),
## indépendant de la façon dont la carte est décrite (grille ASCII ou maillage).
##
## `pos` est un point du sol devant le mur (sur une grille : le centre de la
## cellule), `wall` la direction unitaire vers ce mur et `wall_gap` la distance
## de `pos` à la face du mur : un objet plaqué au mur se place en
## pos + wall * (wall_gap - épaisseur).

## Identifiant stable (noms de nœuds et identifiants réseau).
var id := ""
var pos := Vector3.ZERO
var wall := Vector3(0, 0, -1)
var wall_gap := 0.5
var zone := ""
## Graine déterministe (décalages d'animation, hasard cosmétique).
@warning_ignore("shadowed_global_identifier")
var seed := 0
## Bloqueur de navigation associé ("" : aucun), voir MapLayout.set_blocked.
var block := ""
## Cellule d'origine sur une carte grille (Vector2i(-1, -1) sinon).
var cell := Vector2i(-1, -1)
## Données propres au type (arme, atout...).
var data: Dictionary = {}


## Point plaqué contre le mur, à `height` du sol, `thickness` devant la face.
func on_wall(thickness: float, height: float) -> Vector3:
	return pos + wall * (wall_gap - thickness) + Vector3.UP * height
