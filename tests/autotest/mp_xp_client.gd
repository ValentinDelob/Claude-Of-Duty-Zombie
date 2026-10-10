extends AutotestScenario
## [MP] Client : XP de partie calculée par l'hôte et reçue (docs/XP_RULES.md).
## Reçoit son relevé (sprinteur tué, manche 1 survécue) avec le « +N XP » et
## le compteur ; à la fin de la partie, l'XP du résultat (calculée par
## l'hôte, sans la manche 2 où il était mort) est ajoutée à SON profil.

const PORT := 17925

var H := AutotestHelpers


func run() -> void:
	timeout_sec = 150
	ProfileStore.reset()
	if not await MpHelpers.join_game(self, PORT):
		return
	var game := Game.instance
	game.local_player.bot_controlled = true
	var xp := game.xp
	var want := XpRules.kill_xp(XpRules.SPRINTER, 1) + XpRules.round_xp(1)

	if not await MpHelpers.wait_peer(self, "round1", 60.0):
		return
	var ok: bool = await until(func(): return XpRules.total(xp.my_ledger) == want, 5.0, "relevé reçu")
	at.check(ok and xp.my_ledger.kills == {XpRules.SPRINTER: 1} and int(xp.my_ledger.rounds) == 1,
			"relevé reçu de l'hôte : %s" % xp.my_ledger)
	at.check(xp.counter_shown() == XpSystem.counter_text(want), "compteur : « %s »" % xp.counter_shown())
	MpHelpers.signal_peer("client_saw_round1")

	if not await MpHelpers.wait_peer(self, "ended", 60.0):
		return
	ok = await until(func(): return game.last_result != null, 5.0, "fin de partie reçue")
	if ok:
		var r := game.last_result
		at.check(r.xp == want and int(r.xp_ledger.rounds) == 1, "XP de la partie calculée par l'hôte : %d" % r.xp)
		at.check(ProfileStore.load_profile().xp == want, "ajoutée à mon profil : %d" % ProfileStore.load_profile().xp)
		at.check(game.hud.xp_report_text().contains(r.xp_title()), "rapport à l'écran de fin")
	await MpHelpers.finish(self)
	ProfileStore.reset()
