# Architecture — Call of Claude Zombie

Moteur : **Godot 4.7** (GDScript, rendu Forward+). Cible : GTX 1050 à 60 FPS en 1080p.

## Principe réseau (dès le premier commit)

- Modèle **Host / Client** sur ENet. Le **serveur (peer 1) fait autorité** sur tout ce qui
  est critique : dégâts, santé et mort des zombies, points, achats, portes, manches,
  spawns, Power, machines.
- Le **solo** utilise `OfflineMultiplayerPeer` : le joueur local *est* le serveur.
  Aucune ligne de gameplay n'est dupliquée entre solo et multijoueur.
- Conventions RPC :
  - requête client → serveur : `@rpc("any_peer", "call_local")` + `rpc_id(1, ...)` —
    fonctionne aussi quand l'appelant est le serveur (solo / hôte) ;
  - diffusion serveur → tous : `@rpc("authority", "call_local")` + `rpc(...)`.
- Le client n'envoie que des **intentions** (tirer, acheter, interagir) et sa position ;
  le serveur valide tout (distance, points, cadence, munitions...).

## Autoloads

| Nom | Rôle |
|-----|------|
| `GameState` | Machine à états unique de la session (`MAIN_MENU`, `LOBBY`, `CONNECTING`, `LOADING`, `PLAYING`, `ROUND_END`, `PLAYER_DOWN`, `GAME_OVER`, `DISCONNECTING`) avec transitions validées. |
| `Settings` | Options persistantes (`user://settings.cfg`) et actions d'entrée. |
| `Net` | Host / Join / Solo, poignée de main (version, serveur plein, partie lancée), registre des joueurs, erreurs de connexion lisibles. |
| `Autotest` | Scénarios de test automatisés dans le vrai jeu (`-- --autotest=<nom>`), mesures de perf, captures d'écran. |

## Tests

- `sh tools/check.sh` : import, tests unitaires, test réseau multi-processus, lancement
  réel du jeu + scénario. **Doit passer avant chaque commit.**
- Tests unitaires : `tests/test_*.gd` (runner : `res://tests/test_runner.tscn`).
- Scénarios en jeu : `tests/autotest/*.gd`.
