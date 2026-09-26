extends TestCase
## Modèle procédural des zombies (ZombieModel, RigBuilder) : looks
## déterministes, archétypes, maillage skinné valide, sang peint, caches.


func test_look_keys() -> void:
	for v in [0, 1, 35, 36, 99999, 12345]:
		var k := ZombieModel.look_key(v)
		assert_true(k >= 0 and k < ZombieModel.LOOK_COUNT, "look dans l'intervalle (%d)" % k)
	assert_eq(ZombieModel.look_key(3), ZombieModel.look_key(3 + ZombieModel.LOOK_COUNT))


func test_archetypes_covered() -> void:
	var seen := {}
	for k in ZombieModel.LOOK_COUNT:
		seen[ZombieModel.archetype(k)] = true
	assert_eq(seen.size(), ZombieModel.Arch.size(), "les 6 archétypes existent")
	for a in ZombieModel.Arch.size():
		assert_eq(ZombieModel.archetype(ZombieModel.variant_of(a)), a)
		assert_eq(ZombieModel.archetype(ZombieModel.variant_of(a, 1)), a)
		assert_true(ZombieModel.variant_of(a) != ZombieModel.variant_of(a, 1), "deux variantes par archétype")
	# Kino : surtout des soldats.
	var soldiers := 0
	for k in ZombieModel.LOOK_COUNT:
		if ZombieModel.archetype(k) <= ZombieModel.Arch.RAGGED:
			soldiers += 1
	assert_true(soldiers * 3 >= ZombieModel.LOOK_COUNT * 2, "au moins 2/3 de soldats (%d)" % soldiers)


func test_deterministic() -> void:
	var a := ZombieModel.parts_for(7)
	var b := ZombieModel.parts_for(7 + ZombieModel.LOOK_COUNT)
	assert_eq(a[0].size(), b[0].size(), "même nombre de pièces")
	assert_eq(str(a[2]), str(b[2]), "mêmes taches de sang")
	var ma := RigBuilder.build_arrays(a[0], a[1], a[2])
	var mb := RigBuilder.build_arrays(b[0], b[1], b[2])
	assert_eq(ma[Mesh.ARRAY_VERTEX], mb[Mesh.ARRAY_VERTEX], "mêmes sommets")


func test_mesh_valid() -> void:
	for a in ZombieModel.Arch.size():
		var d := ZombieModel.parts_for(ZombieModel.variant_of(a))
		var arr := RigBuilder.build_arrays(d[0], d[1], d[2])
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
		var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		assert_eq(bones.size(), verts.size() * 4, "4 os par sommet")
		assert_eq(weights.size(), verts.size() * 4, "4 poids par sommet")
		assert_eq(idx.size() % 3, 0, "triangles")
		var ok_w := true
		for i in verts.size():
			var s := weights[i * 4] + weights[i * 4 + 1] + weights[i * 4 + 2] + weights[i * 4 + 3]
			if absf(s - 1.0) > 0.001:
				ok_w = false
		assert_true(ok_w, "poids normalisés (%s)" % ZombieModel.ARCH_NAMES[a])
		var ok_i := true
		for i in idx:
			if i < 0 or i >= verts.size():
				ok_i = false
		assert_true(ok_i, "indices valides")
		# Silhouette humaine : des pieds (sol) au sommet du crâne/casque.
		var box := AABB(verts[0], Vector3.ZERO)
		for v in verts:
			box = box.expand(v)
		assert_true(box.position.y >= 0.0 and box.position.y < 0.02, "pieds au sol (%.3f)" % box.position.y)
		assert_true(box.end.y > 1.78 and box.end.y < 2.0, "taille humaine (%.2f m)" % box.end.y)
		assert_true(box.size.x < 0.75, "silhouette maigre (%.2f m)" % box.size.x)
		# Matière (partie entière) et sang peint (fraction <= 0,45).
		var blood := 0
		var ok_m := true
		for u in uv2:
			var m := floorf(u.y + 0.5)
			var f := u.y - m
			if m < 0.0 or m > 5.0 or f < -0.001 or f > 0.451:
				ok_m = false
			if f > 0.1:
				blood += 1
		assert_true(ok_m, "matières et sang encodés")
		assert_true(blood > 20, "du sang peint (%d sommets)" % blood)
		var eyes := 0
		for c in cols:
			if c.a < 0.5:
				eyes += 1
		assert_true(eyes > 0, "yeux émissifs")


func test_player_and_dog_rigs_unchanged() -> void:
	# Les boîtes historiques (joueurs, chiens) restent des boîtes rigides.
	var parts := [["chest", Vector3(0.4, 0.3, 0.2), Vector3.ZERO, Color.RED, 0.0]]
	var arr := RigBuilder.build_arrays(parts)
	assert_eq((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 24)
	assert_eq((arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 36)
	var dog := HellhoundModel.build(1)
	assert_true(dog.get_bone_count() == RigBuilder.BONES.size())
	dog.free()


func test_cache_shared() -> void:
	var a := ZombieModel.build(4)
	var b := ZombieModel.build(4 + ZombieModel.LOOK_COUNT)
	var ma: MeshInstance3D = a.get_node("Mesh")
	var mb: MeshInstance3D = b.get_node("Mesh")
	assert_true(ma.mesh == mb.mesh, "mesh partagé entre deux zombies du même look")
	assert_true(ma.skin == mb.skin, "Skin partagé")
	assert_eq(ma.layers, ZombieModel.RENDER_LAYERS, "hors des décalques de sang")
	a.free()
	b.free()
