extends TestCase
## Fond 3D du menu (MenuBackdrop) : aucune boîte de l'architecture n'en
## chevauche une autre. Un chevauchement donne des faces coplanaires de
## textures différentes qui scintillent quand la caméra dérive (z-fighting :
## dessous du linteau et chants des ouvertures du couloir transversal).


func test_architecture_boxes_never_overlap() -> void:
	var b := MenuBackdrop.new()
	b._build_corridor()
	b._span("steel", Vector3(-0.15, MenuBackdrop.DOOR_H + 0.3, MenuBackdrop.Z_FAR),
			Vector3(0.15, MenuBackdrop.DOOR_H + 0.375, MenuBackdrop.Z_FAR + 0.3))  # support du gyrophare
	assert_true(b.spans.size() > 20, "boîtes relevées (%d)" % b.spans.size())
	var eps := 0.001
	for i in b.spans.size():
		var a: AABB = b.spans[i][1]
		assert_true(a.size.x > 0.0 and a.size.y > 0.0 and a.size.z > 0.0, "boîte %d non plate" % i)
		for j in range(i + 1, b.spans.size()):
			var c: AABB = b.spans[j][1]
			var inter := a.intersection(c)
			var overlap := inter.size.x > eps and inter.size.y > eps and inter.size.z > eps
			assert_false(overlap, "%s %s chevauche %s %s" % [b.spans[i][0], a, b.spans[j][0], c])
	b.free()
