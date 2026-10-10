shader_type spatial;
// Zombies CUBIQUES qui se dissolvent (corps) : même rendu que
// zombie_voxel.gdshader, plus la dissolution cube par cube et ses braises
// (instance uniform `dissolve`). Voir ZombieModel.set_dissolve.
render_mode cull_back;

#define VOXEL
#define DISSOLVE
#include "res://assets/shaders/zombie_body.gdshaderinc"
