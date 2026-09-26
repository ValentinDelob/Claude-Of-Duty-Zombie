shader_type spatial;
// Zombies qui se dissolvent (corps, morceaux arrachés) : même rendu que
// zombie.gdshader, plus la dissolution et son bord brûlant (instance
// uniform `dissolve`). Voir zombie_body.gdshaderinc et ZombieModel.set_dissolve.
render_mode cull_back;

#define DISSOLVE
#include "res://assets/shaders/zombie_body.gdshaderinc"
