extends "res://tests/autotest/long_soak.gd"
## @niveau long
## Soak de DRAFT ARENA, carte faite avec l'éditeur (voir long_soak.gd) :
## portes et débris, courant, caisse au hasard, grenades et peluches,
## mise à terre et auto-réanimation, manche de chiens.
##   godot --headless --fixed-fps 60 --path . -- --autotest=long_soak_draft


func configure() -> void:
	map_id = "draft_arena"
	target_round = 7
	dog_round = 5
