extends TestCase
## Codec réseau (NetCodec) face à des messages piégés : instantanés de zombies
## et lots d'effets tronqués, trop courts, de type inconnu ou surdimensionnés.
## Rien ne doit planter ; le décodeur refuse (-1, []) ou s'arrête au dernier
## élément complet, comme le prévoit le code.


func _states(ids: Array) -> Dictionary:
	var d := {}
	for id in ids:
		d[id] = PackedInt32Array([0, 0, 0, 0, 0])
	return d


# ------------------------------------------------------------------ instantanés de zombies

func test_snapshot_too_short_refused() -> void:
	var st := _states([1])
	assert_eq(NetCodec.decode_zombie_snapshot(PackedByteArray(), st), -1, "message vide")
	assert_eq(NetCodec.decode_zombie_snapshot(PackedByteArray([5]), st), -1, "un seul octet")
	assert_eq(st[1], PackedInt32Array([0, 0, 0, 0, 0]), "état intact")


func test_snapshot_truncated_fields_refused() -> void:
	# Une entrée annoncée complète (masque 31 = 8 octets de champs), mais
	# seulement 3 octets de champs présents.
	var buf := PackedByteArray()
	buf.resize(2 + 3 + 3)
	buf.encode_u16(0, 1)
	buf.encode_u16(2, 7)
	buf.encode_u8(4, NetCodec.FULL_MASK)
	var st := _states([7])
	assert_eq(NetCodec.decode_zombie_snapshot(buf, st), -1, "champs tronqués refusés")
	assert_eq(st[7], PackedInt32Array([0, 0, 0, 0, 0]), "rien appliqué")


func test_snapshot_count_larger_than_data() -> void:
	# Compte annoncé 65535, une seule entrée réelle : la première est appliquée
	# puis l'en-tête suivant manque (-1).
	var q := NetCodec.quantize_zombie(Vector3(3, 1, 4), 0.5, 2)
	var buf := NetCodec.encode_zombie_snapshot([[9, NetCodec.FULL_MASK, q]])
	buf.encode_u16(0, 65535)
	var st := _states([9])
	assert_eq(NetCodec.decode_zombie_snapshot(buf, st), -1, "message tronqué signalé")
	assert_eq(st[9], q, "entrée complète appliquée avant l'erreur")


func test_snapshot_unknown_ids_and_high_mask_bits() -> void:
	# Bits de masque inconnus (au-delà de 31) ignorés ; ids inconnus sautés.
	var q := NetCodec.quantize_zombie(Vector3(1, 0, 1), 0.0, 1)
	var buf := NetCodec.encode_zombie_snapshot([[3, NetCodec.FULL_MASK, q], [4, NetCodec.FULL_MASK, q]])
	buf[4] = 0xFF   # masque de la première entrée : 31 | bits parasites
	var st := _states([4])
	assert_eq(NetCodec.decode_zombie_snapshot(buf, st), 1, "seul l'id connu est appliqué")
	assert_eq(st[4], q)
	assert_false(st.has(3), "id inconnu jamais créé")


# ------------------------------------------------------------------ lots d'effets

func _shot(weapon := "m1911") -> PackedByteArray:
	var buf := PackedByteArray()
	NetCodec.append_shot(buf, 2, weapon, false, Vector3(1, 2, 3), PackedVector3Array(), PackedVector3Array())
	return buf


func test_fx_truncated_zombie_hit() -> void:
	assert_true(NetCodec.decode_fx(PackedByteArray([NetCodec.FX_ZOMBIE_HIT, 1])).is_empty(), "touche tronquée ignorée")
	var buf := PackedByteArray()
	NetCodec.append_zombie_hit(buf, 12, true)
	buf.append(NetCodec.FX_ZOMBIE_HIT)
	var out := NetCodec.decode_fx(buf)
	assert_eq(out.size(), 1, "touche complète gardée, la suivante tronquée ignorée")
	assert_eq(out[0].zid, 12)


func test_fx_truncated_shot_header() -> void:
	assert_true(NetCodec.decode_fx(PackedByteArray([NetCodec.FX_SHOT, 0, 0])).is_empty(), "en-tête de tir tronqué")
	var b := _shot()
	assert_true(NetCodec.decode_fx(b.slice(0, 10)).is_empty(), "tir coupé dans l'id d'arme")
	# Longueur d'id d'arme énorme (255) sans les octets.
	var c := _shot()
	c[5] = 255
	assert_true(NetCodec.decode_fx(c).is_empty(), "longueur d'arme mensongère")


func test_fx_lying_impact_count() -> void:
	var b := _shot()
	var n_imp_at := 6 + "m1911".length() + 1 + 12
	assert_eq(b[n_imp_at], 0, "position du compte d'impacts")
	b[n_imp_at] = 200
	assert_true(NetCodec.decode_fx(b).is_empty(), "200 impacts annoncés, aucun présent")


func test_fx_lying_blood_count() -> void:
	var b := _shot()
	var n_blood_at := 6 + "m1911".length() + 1 + 12 + 1
	b[n_blood_at] = 50
	assert_true(NetCodec.decode_fx(b).is_empty(), "50 taches annoncées, aucune présente")


func test_fx_unknown_kind_stops() -> void:
	assert_true(NetCodec.decode_fx(PackedByteArray([99, 1, 2, 3, 4, 5])).is_empty(), "type inconnu")
	var buf := PackedByteArray()
	NetCodec.append_zombie_hit(buf, 5, false)
	buf.append_array(PackedByteArray([0, 0, 0, 0]))
	NetCodec.append_zombie_hit(buf, 6, false)
	var out := NetCodec.decode_fx(buf)
	assert_eq(out.size(), 1, "arrêt au premier type inconnu (0)")


func test_fx_oversized_impacts_capped() -> void:
	# 255 impacts écrits à la main (plus que MAX_FX_POINTS) : décodés, puis
	# bornés à MAX_FX_POINTS paires.
	var buf := PackedByteArray([NetCodec.FX_SHOT, 2, 0, 0, 0, 1, 0x61, 0])
	var o := buf.size()
	buf.resize(o + 12 + 1 + 255 * 15 + 1 + 255 * 12)
	buf.encode_float(o, 1.0)
	buf.encode_float(o + 4, 1.0)
	buf.encode_float(o + 8, 1.0)
	o += 12
	buf.encode_u8(o, 255)
	o += 1
	for i in 255:
		buf.encode_float(o, float(i))
		buf.encode_float(o + 4, 0.0)
		buf.encode_float(o + 8, 0.0)
		buf.encode_s8(o + 12, 0)
		buf.encode_s8(o + 13, 127)
		buf.encode_s8(o + 14, 0)
		o += 15
	buf.encode_u8(o, 255)
	var out := NetCodec.decode_fx(buf)
	assert_eq(out.size(), 1, "tir décodé")
	assert_eq(out[0].weapon, "a")
	assert_eq(out[0].impacts.size(), NetCodec.MAX_FX_POINTS * 2, "impacts bornés")
	assert_eq(out[0].blood.size(), NetCodec.MAX_FX_POINTS, "taches bornées")


func test_fx_random_garbage_never_crashes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for n in 300:
		var b := PackedByteArray()
		b.resize(rng.randi_range(0, 64))
		for i in b.size():
			b[i] = rng.randi_range(0, 255)
		# Premier octet souvent un type valide, pour aller plus loin dans le décodeur.
		if b.size() > 0 and n % 2 == 0:
			b[0] = NetCodec.FX_SHOT if n % 4 == 0 else NetCodec.FX_ZOMBIE_HIT
		if b.size() > 5 and b[0] == NetCodec.FX_SHOT:
			b[5] = rng.randi_range(0, 8)
			# Id d'arme en ASCII : le décodage UTF-8 du moteur signalerait sinon
			# chaque octet invalide dans le journal.
			for i in range(6, mini(6 + b[5], b.size())):
				b[i] = 0x61
		var out := NetCodec.decode_fx(b)
		for e: Dictionary in out:
			if e.type == NetCodec.FX_SHOT:
				assert_true(NetGuard.finite_vec(e.origin), "origine finie")
		var st := _states([1, 2, 3])
		var r := NetCodec.decode_zombie_snapshot(b, st)
		assert_true(r >= -1 and r <= 3, "résultat borné (%d)" % r)
