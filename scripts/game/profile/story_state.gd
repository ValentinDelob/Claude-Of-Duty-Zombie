class_name StoryState
extends RefCounted
## Progression de l'HISTOIRE d'un profil (contrats d'histoire, StoryRules ;
## GAME_CONCEPT §4.2 quater) : les étapes remises, dans l'ordre de remise.
## L'étape en cours n'est pas enregistrée : c'est la première étape du
## fichier (StoryData) qui n'est pas remise. Ajouter, retirer ou réordonner
## des étapes dans le fichier ne casse donc pas un profil ; une étape
## remise disparue du fichier reste notée (elle compte si elle revient).
##
## Format (section « story » du profil, ProfileStore version 4) :
##   {"done": ["ch1_fangs", "ch1_fur"]}

## Plafond des étapes lues depuis un fichier (garde-fou).
const MAX_ENTRIES := 512

## Étapes remises, dans l'ordre de remise.
var done: PackedStringArray = []


func is_done(id: String) -> bool:
	return id in done


func mark_done(id: String) -> void:
	if not is_done(id) and done.size() < MAX_ENTRIES:
		done.append(id)


func to_dict() -> Dictionary:
	return {"done": Array(done)}


## État lu depuis un fichier. Entrées illisibles écartées et comptées dans
## `dropped` (tableau d'un entier). Section absente (profil plus ancien) :
## histoire au début, sans rien compter.
static func from_dict(d: Variant, dropped := [0]) -> StoryState:
	var st := StoryState.new()
	if d == null:
		return st
	if not d is Dictionary:
		dropped[0] += 1
		return st
	var list: Variant = d.get("done", [])
	if not list is Array:
		dropped[0] += 1
		return st
	for v in list:
		var id := ProfileValues.clean_id(v)
		if id == "" or st.is_done(id) or st.done.size() >= MAX_ENTRIES:
			dropped[0] += 1
		else:
			st.done.append(id)
	return st
