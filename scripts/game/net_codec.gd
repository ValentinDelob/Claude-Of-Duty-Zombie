class_name NetCodec
extends RefCounted
## Encodage binaire compact des messages réseau fréquents (fonctions pures,
## testées dans tests/test_zombie_net.gd). Voir docs/ARCHITECTURE.md, « Protocole ».
##
## * Zombies : état quantifié [x, z, y, lacet, code] ; instantané delta = seuls
##   les champs qui ont changé depuis le dernier envoi, chaque zombie étant
##   renvoyé en entier tous les ZOMBIE_REFRESH instantanés (décalé par id).
## * Joueurs : état de mouvement en 17 octets.
## * Effets de combat : tirs et touches d'une image regroupés en un message.

# --------------------------------------------------------------------------
# Zombies
# --------------------------------------------------------------------------

## Indices de l'état quantifié d'un zombie.
const QX := 0
const QZ := 1
const QY := 2
const QYAW := 3
const QCODE := 4
## Bit du masque de champs pour chaque indice ; tous = état complet.
const FIELD_BITS := [1, 2, 4, 8, 16]
const FULL_MASK := 31
## Un zombie est renvoyé en entier au moins une fois tous les N instantanés.
const ZOMBIE_REFRESH := 15
## Envois complets d'un zombie juste après son apparition.
const FRESH_FULL := 3
## Décalage vertical pour coder y (peut être négatif pendant l'émergence).
const Y_OFFSET := 20.0


static func quantize_zombie(pos: Vector3, yaw: float, code: int) -> PackedInt32Array:
	return PackedInt32Array([
		clampi(int(round(pos.x * 100.0)), 0, 65535),
		clampi(int(round(pos.z * 100.0)), 0, 65535),
		clampi(int(round((pos.y + Y_OFFSET) * 100.0)), 0, 65535),
		int(round(fposmod(yaw, TAU) / TAU * 256.0)) & 255,
		code & 255,
	])


static func zombie_pos(q: PackedInt32Array) -> Vector3:
	return Vector3(q[QX] / 100.0, q[QY] / 100.0 - Y_OFFSET, q[QZ] / 100.0)


static func zombie_yaw(q: PackedInt32Array) -> float:
	return q[QYAW] / 256.0 * TAU


## Masque des champs de `cur` différents de `last` (FULL_MASK si `last` est vide).
static func diff_mask(last: PackedInt32Array, cur: PackedInt32Array) -> int:
	if last.size() != cur.size():
		return FULL_MASK
	var m := 0
	for i in cur.size():
		if cur[i] != last[i]:
			m |= FIELD_BITS[i]
	return m


## Instantané : u16 nombre d'entrées, puis par entrée u16 id, u8 masque et les
## champs présents dans l'ordre x (u16), z (u16), y (u16), lacet (u8), code (u8).
## `entries` : Array de [id, masque, état quantifié].
static func encode_zombie_snapshot(entries: Array) -> PackedByteArray:
	var size := 2
	for e: Array in entries:
		size += 3 + _mask_bytes(e[1])
	var buf := PackedByteArray()
	buf.resize(size)
	buf.encode_u16(0, entries.size())
	var o := 2
	for e: Array in entries:
		var m: int = e[1]
		var q: PackedInt32Array = e[2]
		buf.encode_u16(o, e[0])
		buf.encode_u8(o + 2, m)
		o += 3
		for i in 3:
			if m & FIELD_BITS[i]:
				buf.encode_u16(o, q[i])
				o += 2
		for i in range(3, 5):
			if m & FIELD_BITS[i]:
				buf.encode_u8(o, q[i])
				o += 1
	return buf


static func _mask_bytes(m: int) -> int:
	var n := 0
	for i in 3:
		if m & FIELD_BITS[i]:
			n += 2
	for i in range(3, 5):
		if m & FIELD_BITS[i]:
			n += 1
	return n


## Applique un instantané à `states` (id -> état quantifié, modifié en place).
## Les ids inconnus sont ignorés. Retourne le nombre d'entrées appliquées, ou
## -1 si le message est tronqué (rien n'est appliqué après l'erreur).
static func decode_zombie_snapshot(buf: PackedByteArray, states: Dictionary) -> int:
	if buf.size() < 2:
		return -1
	var n := buf.decode_u16(0)
	var o := 2
	var applied := 0
	for k in n:
		if o + 3 > buf.size():
			return -1
		var zid := buf.decode_u16(o)
		var m := buf.decode_u8(o + 2)
		o += 3
		if o + _mask_bytes(m) > buf.size():
			return -1
		var q: PackedInt32Array = states.get(zid, PackedInt32Array())
		var known := q.size() == 5
		for i in 3:
			if m & FIELD_BITS[i]:
				if known:
					q[i] = buf.decode_u16(o)
				o += 2
		for i in range(3, 5):
			if m & FIELD_BITS[i]:
				if known:
					q[i] = buf.decode_u8(o)
				o += 1
		if known:
			states[zid] = q
			applied += 1
	return applied


# --------------------------------------------------------------------------
# Joueurs
# --------------------------------------------------------------------------

## x, y, z (f32), lacet (u16), tangage (u16, [-PI/2, PI/2]), drapeaux (u8).
const PLAYER_STATE_SIZE := 17


static func encode_player_state(pos: Vector3, yaw: float, pitch: float, flags: int) -> PackedByteArray:
	var buf := PackedByteArray()
	buf.resize(PLAYER_STATE_SIZE)
	buf.encode_float(0, pos.x)
	buf.encode_float(4, pos.y)
	buf.encode_float(8, pos.z)
	buf.encode_u16(12, int(round(fposmod(yaw, TAU) / TAU * 65536.0)) & 0xFFFF)
	buf.encode_u16(14, clampi(int(round((pitch / PI + 0.5) * 65535.0)), 0, 65535))
	buf.encode_u8(16, flags & 255)
	return buf


## [position, lacet, tangage, drapeaux], ou [] si le message est invalide.
## Position NaN / infinie refusée : chez le serveur, elle ferait échouer toute
## comparaison de distance (achats, tirs, interactions depuis n'importe où).
static func decode_player_state(buf: PackedByteArray) -> Array:
	if buf.size() != PLAYER_STATE_SIZE:
		return []
	var pos := Vector3(buf.decode_float(0), buf.decode_float(4), buf.decode_float(8))
	if not NetGuard.finite_vec(pos):
		return []
	return [pos,
		buf.decode_u16(12) / 65536.0 * TAU,
		(buf.decode_u16(14) / 65535.0 - 0.5) * PI,
		buf.decode_u8(16)]


# --------------------------------------------------------------------------
# Effets de combat regroupés
# --------------------------------------------------------------------------

const FX_SHOT := 1
const FX_ZOMBIE_HIT := 2
const MAX_FX_POINTS := 64


## Ajoute un tir : u8 type, u32 tireur, u8 longueur + id d'arme (UTF-8), u8
## Pack-a-Punch, origine (3 x f32), u8 impacts puis (position 3 x f32,
## normale 3 x i8), u8 taches de sang puis 3 x f32 chacune.
## `impacts` : paires position / normale (comme Combat.srv_fire).
static func append_shot(buf: PackedByteArray, pid: int, weapon_id: String, pap: bool, origin: Vector3, impacts: PackedVector3Array, blood: PackedVector3Array) -> void:
	var wid := weapon_id.to_utf8_buffer()
	@warning_ignore("integer_division")
	var n_imp := mini(impacts.size() / 2, MAX_FX_POINTS)
	var n_blood := mini(blood.size(), MAX_FX_POINTS)
	var o := buf.size()
	buf.resize(o + 1 + 4 + 1 + wid.size() + 1 + 12 + 1 + n_imp * 15 + 1 + n_blood * 12)
	buf.encode_u8(o, FX_SHOT)
	buf.encode_u32(o + 1, pid)
	buf.encode_u8(o + 5, wid.size())
	o += 6
	for i in wid.size():
		buf[o + i] = wid[i]
	o += wid.size()
	buf.encode_u8(o, 1 if pap else 0)
	o = _put_vec(buf, o + 1, origin)
	buf.encode_u8(o, n_imp)
	o += 1
	for i in n_imp:
		o = _put_vec(buf, o, impacts[i * 2])
		var nrm := impacts[i * 2 + 1]
		buf.encode_s8(o, clampi(int(round(nrm.x * 127.0)), -127, 127))
		buf.encode_s8(o + 1, clampi(int(round(nrm.y * 127.0)), -127, 127))
		buf.encode_s8(o + 2, clampi(int(round(nrm.z * 127.0)), -127, 127))
		o += 3
	buf.encode_u8(o, n_blood)
	o += 1
	for i in n_blood:
		o = _put_vec(buf, o, blood[i])


## Ajoute une touche non mortelle : u8 type, u16 zombie, u8 tête.
static func append_zombie_hit(buf: PackedByteArray, zid: int, headshot: bool) -> void:
	var o := buf.size()
	buf.resize(o + 4)
	buf.encode_u8(o, FX_ZOMBIE_HIT)
	buf.encode_u16(o + 1, zid)
	buf.encode_u8(o + 3, 1 if headshot else 0)


## Décode un lot d'effets. Chaque élément : {type: FX_SHOT, pid, weapon, pap,
## origin, impacts (paires position / normale), blood} ou {type: FX_ZOMBIE_HIT,
## zid, headshot}. Un message tronqué s'arrête au dernier élément complet.
static func decode_fx(buf: PackedByteArray) -> Array:
	var out := []
	var o := 0
	while o < buf.size():
		var kind := buf.decode_u8(o)
		if kind == FX_ZOMBIE_HIT:
			if o + 4 > buf.size():
				break
			out.append({"type": kind, "zid": buf.decode_u16(o + 1), "headshot": buf.decode_u8(o + 3) != 0})
			o += 4
		elif kind == FX_SHOT:
			if o + 6 > buf.size():
				break
			var pid := buf.decode_u32(o + 1)
			var wl := buf.decode_u8(o + 5)
			o += 6
			if o + wl + 1 + 12 + 1 > buf.size():
				break
			var wid := buf.slice(o, o + wl).get_string_from_utf8()
			o += wl
			var pap := buf.decode_u8(o) != 0
			var origin := _get_vec(buf, o + 1)
			o += 13
			var n_imp := buf.decode_u8(o)
			o += 1
			if o + n_imp * 15 + 1 > buf.size():
				break
			var impacts := PackedVector3Array()
			for i in n_imp:
				impacts.append(_get_vec(buf, o))
				impacts.append(Vector3(buf.decode_s8(o + 12), buf.decode_s8(o + 13), buf.decode_s8(o + 14)).normalized())
				o += 15
			var n_blood := buf.decode_u8(o)
			o += 1
			if o + n_blood * 12 > buf.size():
				break
			var blood := PackedVector3Array()
			for i in n_blood:
				blood.append(_get_vec(buf, o))
				o += 12
			# Valeurs non finies (hôte malveillant ou message corrompu) : effet ignoré.
			if NetGuard.finite_vec(origin):
				out.append({"type": kind, "pid": pid, "weapon": wid, "pap": pap, "origin": origin,
					"impacts": NetGuard.clean_vecs(impacts, MAX_FX_POINTS * 2, true),
					"blood": NetGuard.clean_vecs(blood, MAX_FX_POINTS)})
		else:
			break
	return out


static func _put_vec(buf: PackedByteArray, o: int, v: Vector3) -> int:
	buf.encode_float(o, v.x)
	buf.encode_float(o + 4, v.y)
	buf.encode_float(o + 8, v.z)
	return o + 12


static func _get_vec(buf: PackedByteArray, o: int) -> Vector3:
	return Vector3(buf.decode_float(o), buf.decode_float(o + 4), buf.decode_float(o + 8))
