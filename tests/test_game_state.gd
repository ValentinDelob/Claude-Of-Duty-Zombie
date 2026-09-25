extends TestCase

func before_each() -> void:
	GameState.reset_to_menu()


func test_valid_flow() -> void:
	assert_true(GameState.set_state(GameState.State.LOADING))
	assert_true(GameState.set_state(GameState.State.PLAYING))
	assert_true(GameState.set_state(GameState.State.ROUND_END))
	assert_true(GameState.set_state(GameState.State.PLAYING))
	assert_true(GameState.set_state(GameState.State.PLAYER_DOWN))
	assert_true(GameState.set_state(GameState.State.GAME_OVER))
	assert_true(GameState.is_in_game())
	assert_true(GameState.set_state(GameState.State.DISCONNECTING))
	assert_true(GameState.set_state(GameState.State.MAIN_MENU))


func test_invalid_transition_rejected() -> void:
	assert_false(GameState.set_state(GameState.State.PLAYING), "MENU -> PLAYING")
	assert_eq(GameState.state, GameState.State.MAIN_MENU)


func test_signal_emitted() -> void:
	var got := []
	var cb := func(a, b): got.append([a, b])
	GameState.state_changed.connect(cb)
	GameState.set_state(GameState.State.LOBBY)
	GameState.state_changed.disconnect(cb)
	assert_eq(got, [[GameState.State.MAIN_MENU, GameState.State.LOBBY]])
