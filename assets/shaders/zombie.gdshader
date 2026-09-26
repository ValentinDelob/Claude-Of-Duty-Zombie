shader_type spatial;
// Zombies vivants (façon Black Ops 1) : voir zombie_body.gdshaderinc.
// Aucun `discard` ici (pré-passe et ombres bon marché) : les corps qui se
// dissolvent passent sur zombie_dissolve.gdshader (ZombieModel.set_dissolve).
render_mode cull_back;

#include "res://assets/shaders/zombie_body.gdshaderinc"
