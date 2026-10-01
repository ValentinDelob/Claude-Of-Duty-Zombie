extends "res://tests/autotest/long_soak.gd"
## @niveau long
## Soak de KINO (voir long_soak.gd) : portes, courant, téléporteur relié au
## poste central puis Pack-a-Punch en salle de projection, pièges à deux
## leviers, boîte, bonus, mise à terre et LAZARUS, manche de chiens.
##   godot --headless --fixed-fps 60 --path . -- --autotest=long_soak_kino


func configure() -> void:
	map_id = "kino"
	target_round = 7
	budget_sec = 1500.0
	dog_round = 5
