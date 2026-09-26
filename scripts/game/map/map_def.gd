class_name MapDef
extends RefCounted
## Description d'une carte : grille ASCII + signification des marqueurs.
##
## Marqueurs communs (posés sur du sol, zone déduite des voisins) :
##   P apparition joueur      Z apparition zombie     L lampe
##   1-9 portes (payantes)    X emplacement de la boîte mystère
##   R U V % ... achats muraux, armes ou couteaux (voir wall_buys)   Q J S D M ( ) atouts (voir perks)
##   * achat mural de grenades (250, voir GrenadeBuy)
##   G interrupteur du courant   E zone du piège électrique   H levier du piège
##   T plateforme du téléporteur   F sortie du téléporteur   K Pack-a-Punch
##   Décor bloquant : C caisse  O baril  I lit  N paillasse  Y générateur
##   Décor : , flaque de sang
##   W fenêtre barricadée, posée dans un mur entre la zone et une petite poche
##     fermée (le dehors) dont les Z sont des apparitions « par la fenêtre »
##     (voir BarricadeLayout). Les Z hors poche sortent du sol.
##   A poste central du téléporteur (liaison, retour des voyageurs)
##   Décor de théâtre (PropBuilder, si theater_props) : = fauteuils (bloquants)  ~ rideau
##     ] écran de cinéma   ? lustre   ! applique murale   + panneau SORTIE
##     & affiche   $ coiffeuse à miroir (bloquante)   @ projecteur (bloquant)
##     | colonne (bloquante)   ^ portant de costumes (bloquant)

const BLOCKING_PROPS := "COINY"
const WINDOW := "W"

var id := "map"
var display_name := "Carte"
var rows: PackedStringArray = []
var zone_names: Dictionary = {}
## "1" -> {"cost": 750}
var doors: Dictionary = {}
## marqueur -> id d'arme
var wall_buys: Dictionary = {}
## marqueur -> id d'atout
var perks: Dictionary = {}
## Index de l'emplacement de départ de la boîte mystère (ordre des X).
var box_start := 0
## zone -> [matériau du sol, matériau des murs]
var zone_materials: Dictionary = {}
## Zones dont les murs portent des tuyauteries.
var pipe_zones: Array = []
## Texte d'accroche (écran de sélection de carte).
var description := ""
## Décor bloquant propre à la carte (en plus de BLOCKING_PROPS).
var extra_blocking := ""
## Départ aléatoire de la boîte parmi ces index d'emplacements (vide : box_start).
var box_starts: Array = []
## zone -> hauteur sous plafond (m) ; les autres zones : MapBuilder.WALL_HEIGHT.
## Les portes et fenêtres gardent la hauteur standard (linteau automatique).
var zone_heights: Dictionary = {}
## Zones ouvertes l'une sur l'autre sans porte : ouvrir l'accès à l'une
## active aussi les apparitions des autres (zone -> [zones]).
var open_links: Dictionary = {}
## Décor de théâtre (marqueurs = ~ ] ? ! + & $ @ | ^, voir en tête) ; sur les
## autres cartes, ces caractères peuvent servir d'achats muraux.
var theater_props := false
## Zone bordée d'une galerie décorative à mi-hauteur (hall de KINO), "" si aucune.
var balcony_zone := ""
var balcony_height := 3.3
## Zone « scène » (rampe lumineuse et lambrequin côté salle), "" si aucune.
var stage_zone := ""
## Musique d'ambiance (assets/audio).
var music := "ambience_bunker"
## Bandeau affiché à l'arrivée du téléporteur.
var teleport_banner := "SALLE DU RITUEL"
## Téléporteur à relier au poste central (marqueur A) avant chaque voyage,
## comme à Kino der Toten ; le retour se fait devant le poste central.
var teleporter_link := false
## Pack-a-Punch caché jusqu'au premier voyage du téléporteur (il surgit alors
## de la scène) au lieu d'une salle secrète.
var pap_revealed_by_teleporter := false
## Ambiance lumineuse : surcharges de WorldLook.setup_environment
## (ambient_color, ambient_energy, fog_color, fog_density, saturation...).
var look: Dictionary = {}


func player_spawn_marker() -> String:
	return "P"


func zone_display_name(zone: String) -> String:
	return zone_names.get(zone, zone.to_upper())


## Cellules bloquantes au départ (décor + portes fermées + fenêtres, que les
## zombies ne franchissent que par l'enjambement scripté).
static func blocking_cells(data: MapData, def: MapDef) -> Array:
	var out := []
	for key in data.markers:
		if BLOCKING_PROPS.contains(key) or def.extra_blocking.contains(key) or def.doors.has(key) or key == WINDOW:
			out.append_array(data.markers[key])
	return out


## Hauteur sous plafond d'une cellule de sol : celle de sa zone, sauf pour
## les portes et fenêtres (hauteur standard : un linteau ferme le haut).
func cell_height(data: MapData, c: Vector2i) -> float:
	if zone_heights.is_empty():
		return MapBuilder.WALL_HEIGHT
	var key := String.chr(data.at(c))
	if doors.has(key) or key == WINDOW:
		return MapBuilder.WALL_HEIGHT
	return float(zone_heights.get(data.zone_at(c), MapBuilder.WALL_HEIGHT))


## Plus grande hauteur de plafond de la carte.
func max_height() -> float:
	var h := MapBuilder.WALL_HEIGHT
	for z in zone_heights:
		h = maxf(h, float(zone_heights[z]))
	return h


## Regroupe des cellules adjacentes (4-connexité) : une porte de 2 cases, une
## plateforme 2x2... Retourne Array[Array[Vector2i]].
static func group_cells(cells: Array) -> Array:
	var left := {}
	for c in cells:
		left[c] = true
	var groups := []
	while not left.is_empty():
		var start: Vector2i = left.keys()[0]
		var group := []
		var stack := [start]
		left.erase(start)
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			group.append(c)
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if left.has(c + d):
					left.erase(c + d)
					stack.append(c + d)
		groups.append(group)
	return groups


## Direction (unitaire, dans le plan) vers le mur le plus proche d'une cellule :
## les objets muraux (atouts, achats) sont plaqués contre ce mur.
static func wall_normal(data: MapData, c: Vector2i) -> Vector3:
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		if data.is_wall(c + d):
			return Vector3(d.x, 0, d.y)
	return Vector3(0, 0, -1)
