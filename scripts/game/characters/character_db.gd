class_name CharacterDB
extends RefCounted
## Les quatre personnages jouables (docs/CHARACTERS.md), comme l'équipe de Kino
## der Toten dans BO1 : chaque joueur incarne un personnage selon son
## emplacement dans la partie, décalé d'une rotation tirée par l'hôte au début
## du match (`Net.cast_offset`, comme le tirage des personnages de BO1).
##
## L'index d'un personnage (0 à 3) choisit aussi sa tenue en vue FPS
## (`ViewHands.STYLES`) et son apparence vue par les autres (`PlayerModel`).

const IDS := ["callahan", "orlov", "arakawa", "weissmann"]
const NAMES := {
	"callahan": "Sgt Jack « Hammer » Callahan",
	"orlov": "Mikhaïl « Micha » Orlov",
	"arakawa": "Lt Kenji Arakawa",
	"weissmann": "Dr Otto Weissmann",
}
const LINES_DIR := "res://assets/voices/"
const VOX_DIR := "res://assets/audio/vox/"

static var _lines: Dictionary = {}


## Index du personnage d'un emplacement de joueur.
static func index_of_slot(slot: int) -> int:
	return posmod(slot + Net.cast_offset, IDS.size())


static func index_of(pid: int) -> int:
	return index_of_slot(Net.player_slot(pid))


static func id_of(pid: int) -> String:
	return IDS[index_of(pid)]


## Répliques d'un personnage : {catégorie: [{fr, en}, ...]}.
static func lines(character: String) -> Dictionary:
	if not _lines.has(character):
		var res: Variant = load(LINES_DIR + character + ".json")
		var data: Dictionary = res.data if res is JSON else {}
		_lines[character] = data.get("lines", {})
	return _lines[character]


## Nombre de variantes d'une catégorie (0 si le personnage n'en a pas).
static func variants(character: String, category: String) -> int:
	return (lines(character).get(category, []) as Array).size()


## Fichier son d'une réplique dans une langue (« fr » ou « en »).
static func vox_path(lang: String, character: String, category: String, variant: int) -> String:
	return "%s%s/%s/%s_%d.ogg" % [VOX_DIR, lang, character, category, variant]


## Texte d'une réplique (sous-titres, journal).
static func text(lang: String, character: String, category: String, variant: int) -> String:
	var v: Array = lines(character).get(category, [])
	if variant < 0 or variant >= v.size():
		return ""
	return String(v[variant].get(lang, v[variant].get("fr", "")))
