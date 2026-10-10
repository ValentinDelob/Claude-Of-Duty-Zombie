class_name ProfileLoot
extends RefCounted
## Butin d'une partie rapporté au profil (GAME_CONCEPT §4.6, §4.7, §4.12,
## §4.16). Seulement après une ÉVACUATION : si toute l'équipe meurt, tout est
## perdu sauf l'XP (MatchXp, à part).
##
## Butin « porté » (carried) : {"weapons": [arme de partie...], "parts":
## [pièce...], "samples": {sorte: quantité}} :
## * armes gardées sur soi : en main et dans l'inventaire de partie, sauf les
##   armes de base intactes (niveau 1, sans pièce : toujours disponibles) et
##   les pistolets prêtés à terre ;
## * pièces de l'onglet des pièces de la partie (non montées) ;
## * échantillons ramassés pendant la partie.
## Une arme de base améliorée (pièce montée) devient un nouvel exemplaire ;
## une arme de l'arsenal (même `uid`) voit cette version mise à jour (ses
## pièces) ; toute autre arme (butin « loot:… ») est un nouvel exemplaire.


## Butin porté par un joueur en fin de partie (données de partie `pd`, pièces
## et échantillons de la partie). Pur.
static func carried(pd: PlayerData, parts: Array, samples: Dictionary) -> Dictionary:
	var ws := []
	if pd != null:
		for w in pd.weapons + pd.bag:
			if w is Dictionary and keeps_weapon(w):
				ws.append((w as Dictionary).duplicate(true))
	var ss := {}
	for k in samples:
		var n := int(samples[k])
		if n > 0:
			ss[String(k)] = n
	return {"weapons": ws, "parts": parts.duplicate(true), "samples": ss}


## Arme à rapporter (voir l'en-tête) ?
static func keeps_weapon(w: Dictionary) -> bool:
	if w.is_empty() or w.get("loaned", false) or not WeaponDB.exists(String(w.get("id", ""))):
		return false
	var uid := String(w.get("uid", ""))
	if uid.begins_with(BaseWeapons.UID_PREFIX):
		return GameWeapon.level_of(w) > 1 or not (w.get("parts", []) as Array).is_empty()
	return uid != ""


## Évacuation réussie : ajoute le butin porté `loot` (carried) au profil
## enregistré (chargé, modifié, enregistré une fois). Appelée UNE fois par
## partie et par client, pour le joueur local (Game._show_match_end).
## Rend le nombre d'objets ajoutés {weapons, updated, parts, samples}.
static func apply_evacuation(loot: Dictionary, profile_path := "") -> Dictionary:
	var pr := ProfileStore.load_profile(profile_path)
	var out := apply_to(pr, loot)
	if out.weapons + out.updated + out.parts + out.samples > 0:
		ProfileStore.save_profile(pr, profile_path)
	return out


## Même chose sur un profil en mémoire (pur, tests).
static func apply_to(pr: PlayerProfile, loot: Dictionary) -> Dictionary:
	var out := {"weapons": 0, "updated": 0, "parts": 0, "samples": 0}
	for w in loot.get("weapons", []):
		if not w is Dictionary or not keeps_weapon(w):
			continue
		var o := GameWeapon.to_owned(w)
		var mine := _arsenal(pr, o.uid)
		if mine != null:
			# Version de l'arsenal améliorée en partie (§4.11) : ses pièces.
			mine.parts = o.parts
			for p in mine.parts:
				p.uid = ""
			pr.weapons.erase(mine)
			pr.add_weapon(mine)
			out.updated += 1
			continue
		o.uid = ""
		for p in o.parts:
			p.uid = ""
		if pr.add_weapon(o) != "":
			out.weapons += 1
	for pd in loot.get("parts", []):
		if not pd is Dictionary:
			continue
		var p := WeaponPart.create(String(pd.get("id", "part")), int(pd.get("level", 1)), pd.get("mods", {}))
		if pr.add_part(p) != "":
			out.parts += 1
	var sm: Variant = loot.get("samples", {})
	if sm is Dictionary:
		for k in sm:
			var n := int(sm[k])
			if n > 0 and pr.add_samples(String(k), n) > 0:
				out.samples += n
	return out


static func _arsenal(pr: PlayerProfile, uid: String) -> OwnedWeapon:
	if uid == "" or uid.begins_with(BaseWeapons.UID_PREFIX):
		return null
	for w in pr.weapons:
		if w.uid == uid:
			return w
	return null


## Résumé pour le rapport de fin (MatchResult.loot) : {"kept": bool,
## "weapons": [[identifiant, niveau, rareté]...], "parts": n, "samples":
## {sorte: n}}. Données seulement (le texte est écrit dans la langue du
## joueur par MatchResult.loot_lines).
static func report(loot: Dictionary, kept: bool) -> Dictionary:
	var ws := []
	for w in loot.get("weapons", []):
		ws.append([String(w.get("id", "")), GameWeapon.level_of(w), GameWeapon.rarity_of(w)])
	return {"kept": kept, "weapons": ws, "parts": (loot.get("parts", []) as Array).size(),
		"samples": (loot.get("samples", {}) as Dictionary).duplicate()}
