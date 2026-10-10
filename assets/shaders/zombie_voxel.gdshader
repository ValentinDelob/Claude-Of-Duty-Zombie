shader_type spatial;
// Zombies CUBIQUES vivants (ZombieModel, cubes de 2,5 cm) : couleur de la
// face telle quelle, yeux émissifs, flash de touche ; voir
// zombie_body.gdshaderinc. Sans `discard` (voir zombie.gdshader) : les corps
// qui se dissolvent passent sur zombie_voxel_dissolve.gdshader.
render_mode cull_back;

#define VOXEL
#include "res://assets/shaders/zombie_body.gdshaderinc"
