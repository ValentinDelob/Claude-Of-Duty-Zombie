extends TestCase
## Réglages du plongeon et de la position allongée (valeurs BO1).


func test_dive_distance() -> void:
	# Vol balistique : ~2,5-3,5 m avant de toucher le sol (saut rasant).
	var air := 2.0 * Player.DIVE_UP / Player.GRAVITY
	var dist := Player.DIVE_SPEED * air
	assert_true(dist > 2.5 and dist < 3.5, "portée du plongeon %.2f m" % dist)
	assert_true(air < 0.5, "vol bref (%.2f s)" % air)


func test_prone_values() -> void:
	assert_true(Player.PRONE_SPEED < Player.CROUCH_SPEED, "reptation plus lente qu'accroupi")
	assert_true(Player.PRONE_EYE_HEIGHT < Player.CROUCH_EYE_HEIGHT)
	assert_true(Player.PRONE_HEIGHT >= Player.RADIUS * 2.0, "capsule valide")
	# Un appui court sur accroupi ne doit pas allonger le joueur.
	assert_true(Player.PRONE_HOLD >= 0.5)


func test_net_flags_distinct() -> void:
	var flags := [Player.FLAG_CROUCH, Player.FLAG_SPRINT, Player.FLAG_AIM, Player.FLAG_GROUNDED,
		Player.FLAG_MOVING, Player.FLAG_PRONE, Player.FLAG_DIVE]
	var all := 0
	for f in flags:
		assert_eq(all & f, 0, "bit %d unique" % f)
		all |= f
