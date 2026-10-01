extends TestCase
## Modèle 3D des coéquipiers : l'arme tenue est à l'endroit.


func _model_with_weapon() -> PlayerModel:
	var m := PlayerModel.new()
	m.build(Color.RED, 0)
	host.add_child(m)
	m.set_weapon("m1911", false)
	# Arme épaulée (immobile, regard à l'horizontale) ; le squelette et la
	# BoneAttachment3D se mettent à jour à l'image suivante.
	m.animate(0.016, 0.0, 0.0, 0, false, false)
	await wait_frames(2)
	return m


func test_weapon_points_forward_and_upright() -> void:
	var m: PlayerModel = await _model_with_weapon()
	var b: Basis = m.weapon_model.global_transform.basis.orthonormalized()
	# L'arme pointe vers son -Z ; le joueur regarde vers -Z, le haut est +Y.
	var barrel := -b.z
	var up := b.y
	assert_true(barrel.dot(Vector3.FORWARD) > 0.8, "canon vers l'avant (%s)" % barrel)
	assert_true(up.dot(Vector3.UP) > 0.8, "dessus de l'arme vers le haut (%s)" % up)
	m.queue_free()
