class_name CharacterDB
extends RefCounted
## Les sept personnages jouables (docs/CHARACTERS.md) : l'équipe de quatre de
## Kino der Toten dans BO1, plus Mercer, Berg et Jojo. Chaque joueur choisit le sien dans
## OPTIONS > JEU > PERSONNAGE (`Settings.character`) ou laisse « automatique ».
## L'hôte répartit les personnages au lancement de la partie (resolve_cast) :
## les choix explicites sont respectés (doublons permis), les joueurs en
## automatique prennent un personnage libre, d'après leur emplacement décalé
## d'une rotation tirée par l'hôte (comme le tirage des personnages de BO1).
## La distribution est envoyée à tous avec l'ordre de chargement (`Net.cast`).
##
## L'index d'un personnage (0 à 6) choisit aussi sa tenue en vue FPS
## (`ViewHands.STYLES`) et son apparence vue par les autres (`PlayerModel`).

const IDS := ["callahan", "orlov", "arakawa", "weissmann", "mercer", "berg", "jojo"]
## Choix « automatique » (Settings.character) : personnage libre tiré par l'hôte.
const AUTO := "auto"
const NAMES := {
	"callahan": "Sgt Jack « Hammer » Callahan",
	"orlov": "Mikhaïl « Micha » Orlov",
	"arakawa": "Lt Kenji Arakawa",
	"weissmann": "Dr Otto Weissmann",
	"mercer": "Sgt-chef Frank « Bulldog » Mercer",
	"berg": "Dr Ella Berg",
	"jojo": "Georges « Jojo la Magouille » Ferrand",
}
const NAMES_EN := {
	"callahan": "Sgt Jack \"Hammer\" Callahan",
	"orlov": "Mikhail \"Misha\" Orlov",
	"arakawa": "Lt Kenji Arakawa",
	"weissmann": "Dr Otto Weissmann",
	"mercer": "GySgt Frank \"Bulldog\" Mercer",
	"berg": "Dr Ella Berg",
	"jojo": "Georges \"Jojo the Hustler\" Ferrand",
}
## Noms courts du sélecteur des options (le nom complet est dans l'aide).
const SHORT_NAMES := {
	"callahan": {"fr": "SGT CALLAHAN", "en": "SGT CALLAHAN"},
	"orlov": {"fr": "ORLOV", "en": "ORLOV"},
	"arakawa": {"fr": "LT ARAKAWA", "en": "LT ARAKAWA"},
	"weissmann": {"fr": "DR WEISSMANN", "en": "DR WEISSMANN"},
	"mercer": {"fr": "SGT-CHEF MERCER", "en": "GYSGT MERCER"},
	"berg": {"fr": "DR BERG", "en": "DR BERG"},
	"jojo": {"fr": "JOJO", "en": "JOJO"},
}
const LINES_DIR := "res://assets/voices/"
const VOX_DIR := "res://assets/audio/vox/"

static var _lines: Dictionary = {}


## Nom complet affiché d'un personnage, dans la langue du jeu.
static func display_name(id: String) -> String:
	if not id in IDS:
		return Lang.t("Automatique", "Automatic")
	return Lang.t(NAMES[id], NAMES_EN[id])


## Nom court (sélecteur des options) ; « AUTOMATIQUE » pour le choix auto.
static func short_name(id: String) -> String:
	if not id in IDS:
		return Lang.t("AUTOMATIQUE", "AUTOMATIC")
	return Lang.pick(SHORT_NAMES[id])


## Choix de personnage venu d'un fichier ou du réseau : un identifiant connu,
## sinon « auto » (jamais d'erreur sur une valeur inattendue).
static func clean_choice(v: Variant) -> String:
	if v is String and v in IDS:
		return v
	return AUTO


## Distribution des personnages (serveur, au lancement). `players` :
## pid -> {"slot": int, "char": String} (Net.players). Les choix explicites
## sont respectés, même en double ; les joueurs « auto », par emplacement
## croissant, prennent le personnage de (emplacement + rotation), ou le
## suivant libre ; s'il n'en reste aucun, celui de leur emplacement.
## Retourne pid -> index dans IDS.
static func resolve_cast(players: Dictionary, rotation := 0) -> Dictionary:
	var n := IDS.size()
	var cast := {}
	var taken := {}
	var autos: Array = []
	for pid in players:
		var p: Variant = players[pid]
		var choice := clean_choice(p.get("char", AUTO) if p is Dictionary else AUTO)
		if choice == AUTO:
			autos.append(pid)
		else:
			cast[pid] = IDS.find(choice)
			taken[cast[pid]] = true
	var slot_of := func(pid: Variant) -> int:
		var p: Variant = players[pid]
		var s: Variant = p.get("slot", 0) if p is Dictionary else 0
		return int(s) if (s is int or s is float) else 0
	autos.sort_custom(func(a, b):
		var sa: int = slot_of.call(a)
		var sb: int = slot_of.call(b)
		return sa < sb if sa != sb else int(a) < int(b))
	for pid in autos:
		var pref := posmod(int(slot_of.call(pid)) + rotation, n)
		var pick := pref
		for k in n:
			var c := posmod(pref + k, n)
			if not taken.has(c):
				pick = c
				break
		cast[pid] = pick
		taken[pick] = true
	return cast


## Distribution reçue de l'hôte, bornée : pid entier > 0 -> index valide,
## 8 joueurs au plus (une entrée invalide est ignorée).
static func clean_cast(v: Variant) -> Dictionary:
	var out := {}
	if not v is Dictionary:
		return out
	for pid in v:
		if out.size() >= Net.MAX_SUPPORTED_PLAYERS:
			break
		var idx: Variant = v[pid]
		if pid is int and pid > 0 and idx is int and idx >= 0 and idx < IDS.size():
			out[pid] = idx
	return out


## Index du personnage d'un joueur : celui de la distribution de la partie,
## à défaut celui de son emplacement.
static func index_of(pid: int) -> int:
	if Net.cast.has(pid):
		return Net.cast[pid]
	return posmod(Net.player_slot(pid), IDS.size())


static func id_of(pid: int) -> String:
	return IDS[index_of(pid)]


## Répliques d'un personnage : {catégorie: [{fr, en}, ...]}. Fichier absent
## (personnage en cours d'écriture) : aucune réplique, le personnage se tait.
static func lines(character: String) -> Dictionary:
	if not _lines.has(character):
		var path := LINES_DIR + character + ".json"
		var res: Variant = load(path) if ResourceLoader.exists(path) else null
		var data: Variant = res.data if res is JSON else {}
		var l: Variant = data.get("lines", {}) if data is Dictionary else {}
		_lines[character] = l if l is Dictionary else {}
	return _lines[character]


## Nombre de variantes d'une catégorie (0 si le personnage n'en a pas).
static func variants(character: String, category: String) -> int:
	var v: Variant = lines(character).get(category, [])
	return v.size() if v is Array else 0


## Fichier son d'une réplique dans une langue (« fr » ou « en »).
static func vox_path(lang: String, character: String, category: String, variant: int) -> String:
	return "%s%s/%s/%s_%d.ogg" % [VOX_DIR, lang, character, category, variant]


## Texte d'une réplique (sous-titres, journal).
static func text(lang: String, character: String, category: String, variant: int) -> String:
	var v: Variant = lines(character).get(category, [])
	if not v is Array or variant < 0 or variant >= v.size() or not v[variant] is Dictionary:
		return ""
	return String(v[variant].get(lang, v[variant].get("fr", "")))
