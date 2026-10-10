class_name ProfileValues
extends RefCounted
## Lecture typée des valeurs du profil venues d'un fichier JSON (nombres
## toujours lus en flottants, types quelconques si le fichier a été modifié) :
## une valeur inutilisable donne la valeur par défaut, jamais une erreur de
## script qui laisserait le profil à moitié lu.


## Entier borné ; `v` peut être un flottant JSON (5.0) ou un entier.
static func to_int(v: Variant, default: int, lo: int, hi: int) -> int:
	if v is int:
		return clampi(v, lo, hi)
	if v is float and is_finite(v):
		# Borné AVANT la conversion : int(1e30) déborde (comme SafeConfig.get_int).
		return clampi(int(clampf(v, lo, hi)), lo, hi)
	return default


## Identifiant acceptable : texte non vide, court, lettres, chiffres, « _ », « - », « . », « : ».
static func id_ok(s: String) -> bool:
	if s.is_empty() or s.length() > WeaponPart.MAX_ID_LEN:
		return false
	for c in s:
		if not (c.is_valid_ascii_identifier() or c.is_valid_int() or c in "_-.:"):
			return false
	return true


## Identifiant nettoyé ("" s'il est inutilisable).
static func clean_id(v: Variant) -> String:
	if (v is String or v is StringName) and id_ok(String(v)):
		return String(v)
	return ""
