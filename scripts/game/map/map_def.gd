class_name MapDef
extends RefCounted
## Description d'une carte : grille ASCII + signification des marqueurs.
## Les marqueurs communs :
##   'P' point d'apparition des joueurs
##   'L' lampe au plafond

var id := "map"
var display_name := "Carte"
var rows: PackedStringArray = []


func player_spawn_marker() -> String:
	return "P"
