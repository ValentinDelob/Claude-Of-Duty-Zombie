class_name MatchContracts
extends RefCounted
## Rotation du tableau des contrats à la fin d'une partie (docs/HUB_PLAN.md
## §5.3, D7) : appelée UNE fois par partie et par client, à côté de
## MatchXp.apply (Game._show_match_end, ou Game.keep_match_xp au départ en
## cours de partie), sur le profil local. Une partie d'au moins
## `min_rounds_for_rotation` manche survécue (quelle que soit l'issue) fait
## tourner le tableau ; plus courte, seule la purge des contrats expirés ou
## inconnus est faite (pas de « relance » gratuite en quittant tout de suite).
## Contrats locaux à chaque joueur, même en coop (D12) : rien sur le réseau.


## Manches survécues d'une partie finie : le relevé d'XP du joueur
## (`rounds`, manches finies vivant) ou, pour l'équipe, la manche atteinte − 1
## (un joueur mort dont l'équipe a tenu compte aussi).
static func rounds_survived(r: MatchResult) -> int:
	if r == null:
		return 0
	return maxi(int(r.xp_ledger.get("rounds", 0)), r.round_reached - 1)


## Rotation sur le profil enregistré (chargé, modifié, enregistré si quelque
## chose a changé). `data` : catalogue (défaut : fichiers livrés) ; `day` :
## jour UTC (défaut : aujourd'hui). Rend le rapport de ContractRules.rotate
## (ou de purge) plus {"rotated": bool}.
static func after_match(rounds: int, profile_path := "", data: HubData = null, day := -1) -> Dictionary:
	if data == null:
		data = HubData.default()
	if day < 0:
		day = HubData.today()
	var pr := ProfileStore.load_profile(profile_path)
	var before := JSON.stringify(pr.contracts.to_dict())
	var rotated := rounds >= int(data.rules.min_rounds_for_rotation)
	var out := ContractRules.rotate(pr.contracts, data, pr.level(), day, true) if rotated \
			else ContractRules.purge(pr.contracts, data, day)
	out.rotated = rotated
	if JSON.stringify(pr.contracts.to_dict()) != before:
		ProfileStore.save_profile(pr, profile_path)
	return out
