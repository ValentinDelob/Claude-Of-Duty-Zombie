class_name ProfileLoot
extends RefCounted
## Armes rapportées au profil à la fin d'une partie (GAME_CONCEPT §4.6,
## §4.10 à §4.12, §4.16). Seule l'ÉVACUATION rapporte quelque chose : à la mort
## de toute l'équipe, rien n'est appelé (armes ramassées et améliorations en
## partie perdues ; les armes de l'arsenal, elles, n'ont jamais quitté le
## profil : une construction ne les retire pas).
##
## À l'évacuation, pour chaque arme gardée sur soi (en main et inventaire) :
##   * exemplaire construit depuis l'arsenal (même `uid` qu'une arme du
##     profil) : s'il a été amélioré en partie (niveau, rareté ou pièces
##     différents), CETTE version est mise à jour (§4.11) ; sinon rien. Un
##     second exemplaire de la même version, différent de la version déjà
##     mise à jour, devient une nouvelle version (rien n'est remplacé en
##     silence) ;
##   * arme de base (niveau 1, commune, sans pièce) : rien (toujours
##     disponible) ; améliorée, elle devient une nouvelle version (§4.10) ;
##   * autre arme (ramassée pendant la partie) : ajoutée à l'arsenal (§4.12).
## Les armes prêtées à terre et les identifiants d'arme inconnus sont ignorés.

## Rapport vide (clés de apply_evacuation).
static func empty_report() -> Dictionary:
	return {"updated": [], "added": []}


## Applique l'évacuation au profil `pr` (en mémoire) pour les armes de partie
## `carried` (GameWeapon). Rend {updated: [uid], added: [uid]}. Pure (aucun
## fichier) : apply_evacuation l'enregistre.
static func apply_to(pr: PlayerProfile, carried: Array) -> Dictionary:
	var rep := empty_report()
	var handled := {}
	for w in carried:
		if not w is Dictionary or w.is_empty() or bool(w.get("loaned", false)):
			continue
		var id := String(w.get("id", ""))
		if not ProfileValues.id_ok(id) or not (WeaponDB.exists(id) or KnifeDB.exists(id)):
			continue
		var uid := String(w.get("uid", ""))
		var o := GameWeapon.to_owned(w)
		if BaseWeapons.is_base(id) and _same(o, BaseWeapons.make(id)):
			continue
		var own: OwnedWeapon = pr.get_weapon(uid) if uid != "" and not uid.begins_with(BaseWeapons.UID_PREFIX) else null
		if own != null and not handled.has(uid):
			handled[uid] = true
			if not _same(o, own) and pr.update_weapon(uid, o):
				rep.updated.append(uid)
			continue
		if own != null and _same(o, own):
			continue
		o.uid = ""
		var nid := pr.add_weapon(o)
		if nid != "":
			rep.added.append(nid)
	return rep


## Fin de partie, évacuation réussie : applique `carried` (armes en main et
## inventaire du joueur local) au profil enregistré et l'enregistre s'il
## change. Appelée UNE fois par partie (Game._show_match_end). Rend le
## rapport (apply_to).
static func apply_evacuation(carried: Array, profile_path := "") -> Dictionary:
	var pr := ProfileStore.load_profile(profile_path)
	var rep := apply_to(pr, carried)
	if not rep.updated.is_empty() or not rep.added.is_empty():
		ProfileStore.save_profile(pr, profile_path)
	return rep


## Même arme, même niveau, même rareté, mêmes pièces (identifiant, niveau,
## modificateurs ; ordre compris) ?
static func _same(a: OwnedWeapon, b: OwnedWeapon) -> bool:
	if a.weapon_id != b.weapon_id or a.level != b.level or a.rarity != b.rarity or a.parts.size() != b.parts.size():
		return false
	for i in a.parts.size():
		var pa := a.parts[i]
		var pb := b.parts[i]
		if pa.part_id != pb.part_id or pa.level != pb.level or not _same_mods(pa.mods, pb.mods):
			return false
	return true


static func _same_mods(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(k) or absf(float(a[k]) - float(b[k])) > 1e-6:
			return false
	return true
