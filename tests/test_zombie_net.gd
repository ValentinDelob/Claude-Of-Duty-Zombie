extends TestCase
## Réplication : instantanés delta des zombies, état des joueurs, effets groupés.


func _zombie(mgr: ZombieManager, zid: int, server: bool, pos: Vector3, yaw: float) -> Zombie:
	var z := Zombie.new()
	z.setup(zid, 7, 2, server)
	mgr.add_child(z)
	mgr.zombies[zid] = z
	mgr.alive.append(z)
	z.global_position = pos
	z.yaw = yaw
	return z


func test_snapshot_roundtrip() -> void:
	var mgr := ZombieManager.new()
	host.add_child(mgr)
	var z := _zombie(mgr, 42, true, Vector3(12.34, -0.5, 56.78), 1.5)
	z.state = Zombie.State.CHASE
	var buf := mgr.build_snapshot()
	# Zombie inconnu du flux : état complet (2 + 3 octets d'en-tête ; x 12,34 m
	# et z 56,78 m : 2 octets chacun, y −0,5 m : 1 octet (entiers variables) ;
	# lacet et code : 2) — un octet de moins que l'ancien codage u16.
	assert_eq(buf.size(), 2 + 3 + 7)

	# Côté client : une marionnette connue (état d'apparition) reçoit l'instantané.
	var mgr2 := ZombieManager.new()
	host.add_child(mgr2)
	var z2 := _zombie(mgr2, 42, false, Vector3.ZERO, 0.0)
	mgr2.net_q[42] = NetCodec.quantize_zombie(Vector3.ZERO, 0.0, 0)
	mgr2.apply_snapshot(buf)
	assert_eq(z2.snapshot_count(), 1)
	var snap: Array = z2.snapshot(0)
	assert_true(snap[1].distance_to(Vector3(12.34, -0.5, 56.78)) < 0.02, "position %s" % snap[1])
	assert_near(snap[2], 1.5, 0.03, "yaw")
	var code: int = snap[3]
	assert_eq(code & 7, Zombie.State.CHASE)
	assert_eq((code >> 3) & 3, 2)
	mgr.queue_free()
	mgr2.queue_free()


func test_delta_sends_only_changes() -> void:
	var mgr := ZombieManager.new()
	host.add_child(mgr)
	var a := _zombie(mgr, 1, true, Vector3(5, 0, 5), 0.0)
	var b := _zombie(mgr, 2, true, Vector3(8, 0, 8), 0.0)
	a.state = Zombie.State.CHASE
	b.state = Zombie.State.ATTACK
	mgr._snap_seq = 1  # ni 1 ni 2 ne sont renvoyés en entier à ce tour-ci
	var full := mgr.build_snapshot()
	assert_eq(full.decode_u16(0), 2)
	# Rien n'a bougé : la redondance renvoie une fois l'état, puis plus rien.
	assert_eq(mgr.build_snapshot().decode_u16(0), 2)
	var empty := mgr.build_snapshot()
	assert_eq(empty.size(), 2)
	# a avance en x seulement : une entrée, un seul champ (deux fois : redondance).
	a.global_position.x += 0.3
	var d := mgr.build_snapshot()
	assert_eq(d.decode_u16(0), 1)
	assert_eq(d.size(), 2 + 3 + 2)
	assert_eq(d.decode_u16(2), 1)
	assert_eq(d.decode_u8(4), 1)  # masque = X
	assert_eq(mgr.build_snapshot(), d)
	assert_eq(mgr.build_snapshot().size(), 2)
	# Client : l'état reconstruit suit l'état serveur.
	var states := {1: NetCodec.quantize_zombie(Vector3(5, 0, 5), 0.0, a.anim_code()),
		2: NetCodec.quantize_zombie(Vector3(8, 0, 8), 0.0, b.anim_code())}
	assert_eq(NetCodec.decode_zombie_snapshot(d, states), 1)
	assert_true(NetCodec.zombie_pos(states[1]).distance_to(a.global_position) < 0.01)
	mgr.queue_free()


## Flux simulé : zombies qui bougent, tournent et changent d'état, paquets
## perdus. Sans deux pertes consécutives, l'état du client est exactement
## celui du serveur après chaque paquet reçu ; après une longue coupure, il
## l'est de nouveau au plus ZOMBIE_REFRESH instantanés plus tard.
func test_delta_stream_with_losses() -> void:
	var mgr := ZombieManager.new()
	host.add_child(mgr)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var zs: Array[Zombie] = []
	var client := {}
	for i in 12:
		var z := _zombie(mgr, 100 + i, true, Vector3(10 + i, 0, 10), 0.0)
		zs.append(z)
		mgr.net_q[z.id] = NetCodec.quantize_zombie(z.global_position, z.yaw, z.anim_code())
		mgr._net_fresh[z.id] = NetCodec.FRESH_FULL
		client[z.id] = mgr.net_q[z.id]
	# Pertes isolées (1 paquet sur 3 à 1 sur 5), puis une coupure de 4 paquets.
	var lost := {}
	for k in 90:
		if k % 5 == 2 or k % 15 == 10:
			lost[k] = true
	for k in range(100, 104):
		lost[k] = true
	var mismatch_isolated := 0
	var recovered_at := -1
	for k in 130:
		for z in zs:
			if rng.randf() < 0.7:
				z.global_position += Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
			if rng.randf() < 0.2:
				z.yaw += rng.randf_range(-0.5, 0.5)
			if rng.randf() < 0.05:
				z.state = [Zombie.State.CHASE, Zombie.State.ATTACK, Zombie.State.IDLE][rng.randi() % 3]
		var buf := mgr.build_snapshot()
		if lost.has(k):
			continue
		NetCodec.decode_zombie_snapshot(buf, client)
		var same := true
		for z in zs:
			if client[z.id] != mgr.net_q[z.id]:
				same = false
		if k < 100 and not same:
			mismatch_isolated += 1
		if k >= 104 and same and recovered_at < 0:
			recovered_at = k
	assert_eq(mismatch_isolated, 0, "états divergents malgré des pertes isolées")
	assert_true(recovered_at >= 104 and recovered_at <= 104 + NetCodec.ZOMBIE_REFRESH, "resynchronisation après coupure : %d" % recovered_at)
	mgr.queue_free()


func test_periodic_full_refresh() -> void:
	var mgr := ZombieManager.new()
	host.add_child(mgr)
	var z := _zombie(mgr, 3, true, Vector3(5, 0, 5), 0.0)
	z.state = Zombie.State.IDLE
	var fulls := 0
	for i in NetCodec.ZOMBIE_REFRESH * 2:
		var buf := mgr.build_snapshot()
		if buf.size() > 2:
			assert_eq(buf.decode_u8(4), NetCodec.FULL_MASK)
			fulls += 1
	# Immobile : premier envoi (et sa redondance), puis une fois par période.
	assert_eq(fulls, 4, "renvois complets")
	mgr.queue_free()


func test_unknown_zombie_skipped() -> void:
	var q := NetCodec.quantize_zombie(Vector3(1, 0, 2), 0.5, 2)
	var buf := NetCodec.encode_zombie_snapshot([[9, NetCodec.FULL_MASK, q], [4, 1, q]])
	var states := {4: NetCodec.quantize_zombie(Vector3(3, 0, 3), 0.0, 0)}
	assert_eq(NetCodec.decode_zombie_snapshot(buf, states), 1)
	assert_false(states.has(9))
	assert_eq(states[4][NetCodec.QX], q[NetCodec.QX])
	assert_eq(states[4][NetCodec.QZ], 300)


func test_truncated_snapshot_ignored() -> void:
	var mgr := ZombieManager.new()
	var buf := PackedByteArray([5, 0, 1, 2])
	mgr.apply_snapshot(buf)  # ne doit pas planter
	assert_eq(NetCodec.decode_zombie_snapshot(buf, {}), -1)
	mgr.free()


func test_player_state_roundtrip() -> void:
	var buf := NetCodec.encode_player_state(Vector3(10.25, 1.5, -3.75), -2.0, 0.7, 13)
	assert_eq(buf.size(), NetCodec.PLAYER_STATE_SIZE)
	var s := NetCodec.decode_player_state(buf)
	assert_true(s[0].distance_to(Vector3(10.25, 1.5, -3.75)) < 0.001)
	assert_near(angle_difference(s[1], -2.0), 0.0, 0.001, "lacet")
	assert_near(s[2], 0.7, 0.001, "tangage")
	assert_eq(s[3], 13)
	assert_true(NetCodec.decode_player_state(PackedByteArray([1, 2])).is_empty())
	# Même état = mêmes octets (détection des changements côté envoi).
	assert_eq(buf, NetCodec.encode_player_state(Vector3(10.25, 1.5, -3.75), -2.0, 0.7, 13))


func test_fx_batch_roundtrip() -> void:
	var buf := PackedByteArray()
	var impacts := PackedVector3Array([Vector3(1, 2, 3), Vector3(0, 1, 0), Vector3(4, 5, 6), Vector3(1, 0, 0)])
	NetCodec.append_shot(buf, 123456789, "mp40", true, Vector3(7, 1.6, 8), impacts, PackedVector3Array([Vector3(9, 1, 9)]))
	NetCodec.append_zombie_hit(buf, 77, true)
	NetCodec.append_shot(buf, 1, "m1911", false, Vector3.ZERO, PackedVector3Array(), PackedVector3Array())
	var fx := NetCodec.decode_fx(buf)
	assert_eq(fx.size(), 3)
	assert_eq(fx[0].type, NetCodec.FX_SHOT)
	assert_eq(fx[0].pid, 123456789)
	assert_eq(fx[0].weapon, "mp40")
	assert_true(fx[0].pap)
	assert_eq(fx[0].impacts.size(), 4)
	assert_true(fx[0].impacts[2].distance_to(Vector3(4, 5, 6)) < 0.001)
	assert_true(fx[0].impacts[3].distance_to(Vector3(1, 0, 0)) < 0.01)
	assert_eq(fx[0].blood.size(), 1)
	assert_eq(fx[1].type, NetCodec.FX_ZOMBIE_HIT)
	assert_eq(fx[1].zid, 77)
	assert_true(fx[1].headshot)
	assert_eq(fx[2].weapon, "m1911")
	assert_false(fx[2].pap)
	# Tronqué : on garde les éléments complets.
	assert_eq(NetCodec.decode_fx(buf.slice(0, buf.size() - 3)).size(), 2)


## Pause « de folie » à la fenêtre : un bit du code d'animation (état et
## vitesse intacts), seulement à la fenêtre ; la marionnette le reçoit.
func test_frenzy_bit_in_anim_code() -> void:
	var mgr := ZombieManager.new()
	host.add_child(mgr)
	var z := _zombie(mgr, 5, true, Vector3(3, 0, 3), 0.0)
	z.state = Zombie.State.BARRIER
	z.tear_frenzy = true
	var code := z.anim_code()
	assert_true(code & Zombie.FRENZY_BIT != 0, "bit de folie levé")
	assert_eq(code & 7, Zombie.State.BARRIER, "état intact")
	assert_eq((code >> 3) & 3, 2, "vitesse intacte")
	assert_true(code <= 255, "tient dans l'octet du code")
	z.state = Zombie.State.CHASE
	assert_eq(z.anim_code() & Zombie.FRENZY_BIT, 0, "hors de la fenêtre : jamais")
	z.state = Zombie.State.BARRIER
	var buf := mgr.build_snapshot()
	var mgr2 := ZombieManager.new()
	host.add_child(mgr2)
	var z2 := _zombie(mgr2, 5, false, Vector3(3, 0, 3), 0.0)
	mgr2.net_q[5] = NetCodec.quantize_zombie(Vector3.ZERO, 0.0, 0)
	mgr2.apply_snapshot(buf)
	var snap: Array = z2.snapshot(0)
	assert_true(int(snap[3]) & Zombie.FRENZY_BIT != 0, "bit reçu par la marionnette")
	mgr.queue_free()
	mgr2.queue_free()


## Format 17 (protocole 6) : positions sans borne de carte ni d'altitude —
## négatives, très grandes, très hautes — en aller-retour exact au cm.
func test_snapshot_unbounded_positions_roundtrip() -> void:
	var cases := [Vector3(-37.5, -12.25, -0.01), Vector3(655.36, 0, 700.0), Vector3(12000.5, 950.25, -8000.75),
		Vector3(-150000.0, -20.5, 190000.0), Vector3(0.004, -0.004, 0.0), Vector3(21474836.0, -21474836.0, 1.0)]
	var entries := []
	var states := {}
	for i in cases.size():
		entries.append([i + 1, NetCodec.FULL_MASK, NetCodec.quantize_zombie(cases[i], 1.0, 9)])
		states[i + 1] = PackedInt32Array([0, 0, 0, 0, 0])
	var buf := NetCodec.encode_zombie_snapshot(entries)
	assert_eq(NetCodec.decode_zombie_snapshot(buf, states), cases.size(), "toutes les entrées lues")
	for i in cases.size():
		var p := NetCodec.zombie_pos(states[i + 1])
		var want: Vector3 = cases[i]
		assert_true(p.distance_to(want) < 0.006 + absf(want.x) * 1e-7 + absf(want.z) * 1e-7, "position %s -> %s" % [want, p])
		assert_eq(states[i + 1][NetCodec.QCODE], 9, "code")
	# Au-delà de ± 21 474 km : borné (jamais un débordement), valeur non finie : 0.
	var q := NetCodec.quantize_zombie(Vector3(1e12, NAN, -1e12), 0.0, 0)
	assert_eq(q[NetCodec.QX], NetCodec.POS_MAX)
	assert_eq(q[NetCodec.QY], 0)
	assert_eq(q[NetCodec.QZ], -NetCodec.POS_MAX)


## Taille des instantanés : une carte ordinaire (monde de 4 à 80 m, sol à 0 ou
## 3,5 m) coûte au plus autant que l'ancien codage u16 (11 octets pour un état
## complet, 5 pour un seul champ de position), une grande carte quelques
## octets de plus seulement.
func test_snapshot_size_stays_compact() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var entries := []
	for i in 24:
		var p := Vector3(rng.randf_range(4, 80), [0.0, 3.5][i % 2], rng.randf_range(4, 80))
		entries.append([i, NetCodec.FULL_MASK, NetCodec.quantize_zombie(p, rng.randf() * TAU, 3)])
	var full := NetCodec.encode_zombie_snapshot(entries).size()
	assert_true(full <= 2 + 24 * 11, "24 zombies, états complets : %d octets (ancien codage : %d)" % [full, 2 + 24 * 11])
	var moves := []
	for e in entries:
		moves.append([e[0], 1 | 2 | 8, e[2]])
	var delta := NetCodec.encode_zombie_snapshot(moves).size()
	assert_true(delta <= 2 + 24 * 8, "24 zombies qui avancent et tournent : %d octets (ancien : %d)" % [delta, 2 + 24 * 8])
	# Très grande carte (jusqu'à 10 km) : 3 octets par coordonnée au plus.
	var big := NetCodec.encode_zombie_snapshot([[1, NetCodec.FULL_MASK, NetCodec.quantize_zombie(Vector3(9000, 400, 9000), 0.0, 0)]])
	assert_true(big.size() <= 2 + 3 + 3 * 3 + 2, "grande carte : %d octets" % big.size())
