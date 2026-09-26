class_name WeaponAudio
extends RefCounted
## Son de tir d'une arme. Arme Pack-a-Punchée (comme BO1) : la même
## détonation, à peine plus grave, doublée d'un arc électrique (« zap »,
## enregistrements CC0 pap_zap_1..3) au lieu d'un simple son ralenti.

## Hauteur du tir d'une arme améliorée (sauf `sound_pitch` de l'arme).
const PAP_PITCH := 0.95
const ZAP_VARIANTS := 3
## Niveau de la couche électrique par rapport au tir (dB) ; les fichiers
## pap_zap_* sont déjà 8 LU sous les tirs (SfxLoudness, catégorie arme_zap).
const ZAP_DB := 0.0


static func pitch(s: Dictionary, pap: bool) -> float:
	return float(s.get("sound_pitch", PAP_PITCH if pap else 1.0))


## Couche électrique : armes améliorées, sauf armes merveilles (leur son
## est déjà électrique / pneumatique).
static func has_zap(s: Dictionary, pap: bool) -> bool:
	return pap and String(s.get("class", "")) != "wonder"


static func zap_name() -> String:
	return "pap_zap_%d" % (1 + randi() % ZAP_VARIANTS)


## Tir du joueur local (non spatialisé).
static func play_2d(s: Dictionary, pap: bool, volume_db := -1.0) -> void:
	Audio.play_2d(s.sound, volume_db, 0.05, "SFX", pitch(s, pap))
	if has_zap(s, pap):
		Audio.play_2d(zap_name(), volume_db + ZAP_DB, 0.1)


## Tir d'un autre joueur (spatialisé).
static func play_3d(s: Dictionary, pap: bool, origin: Vector3) -> void:
	Audio.play_3d(s.sound, origin, 0.0, 0.05, 8, pitch(s, pap))
	if has_zap(s, pap):
		Audio.play_3d(zap_name(), origin, ZAP_DB, 0.1, 8)
