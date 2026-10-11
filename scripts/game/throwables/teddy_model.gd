class_name TeddyModel
extends RefCounted
## Ours en peluche de la PELUCHE LEURRE (objet de la caisse au hasard), en
## CUBES de 2,5 cm (GAME_CONCEPT §4.19) : ours assis, fourrure brune, museau
## et coussinets clairs, yeux-boutons (l'un recousu plus haut), nœud rouge au
## cou, pièce rapiécée. Modèle assets/models/weapons/voxel/teddy.glb
## (tools/blender/weapons/weapons_voxel.py), à sa taille finale (environ
## 27 cm, jamais mis à l'échelle) ; face vers +Z, assis sur y = 0. La tête est
## une pièce à part (« Head »).

## Hauteur du modèle (m).
const HEIGHT := 0.275


## `view` : matériaux de la vue FPS (jamais dans les murs).
static func build(view := false) -> Node3D:
	var root := Node3D.new()
	root.name = "Teddy"
	root.add_child(WeaponModels.piece_node(WeaponModels.TEDDY, "body", view))
	root.add_child(WeaponModels.piece_node(WeaponModels.TEDDY, "Head", view))
	return root
