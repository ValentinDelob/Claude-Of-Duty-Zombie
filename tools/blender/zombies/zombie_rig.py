# Ossature du jeu (RigBuilder.BONES : 13 os + mâchoire) posée sur le corps de
# base, pondération automatique, puis remise en « pose de repos du jeu » :
# bras et jambes pendants à la verticale (le jeu anime des os sans rotation
# de repos, membres vers le bas).
import bpy
from mathutils import Vector

# Articulations du corps de base (pose en A du pack Human Base Meshes, 1,684 m,
# repérées sur son squelette anatomique ; côté gauche = +X).
NATIVE = {
    "hips": (0.0, 0.005, 0.9),
    "spine": (0.0, 0.02, 1.01),
    "chest": (0.0, 0.025, 1.2),
    "neck": (0.0, 0.02, 1.435),
    "head": (0.0, 0.0, 1.54),
    "jaw": (0.0, -0.03, 1.525),
    "arm_l": (0.175, 0.012, 1.36),
    "forearm_l": (0.33, 0.012, 1.105),
    "hand_l": (0.395, -0.03, 0.905),
    "thigh_l": (0.09, 0.005, 0.88),
    "shin_l": (0.105, 0.012, 0.47),
    "foot_l": (0.12, 0.0, 0.067),
}
HEAD_TOP = (0.0, -0.02, 1.684)
CHIN = (0.0, -0.1, 1.46)

# [nom, parent, bout (articulation suivante)]
BONES = [
    ("hips", None, "spine"),
    ("spine", "hips", "chest"),
    ("chest", "spine", "neck"),
    ("neck", "chest", "head"),
    ("head", "neck", HEAD_TOP),
    ("jaw", "head", CHIN),
    ("arm_l", "chest", "forearm_l"),
    ("forearm_l", "arm_l", "hand_l"),
    ("arm_r", "chest", "forearm_r"),
    ("forearm_r", "arm_r", "hand_r"),
    ("thigh_l", "hips", "shin_l"),
    ("shin_l", "thigh_l", "foot_l"),
    ("thigh_r", "hips", "shin_r"),
    ("shin_r", "thigh_r", "foot_r"),
]


def joint(name, scale=1.0):
    if name.endswith("_r"):
        x, y, z = NATIVE[name[:-2] + "_l"]
        return Vector((-x, y, z)) * scale
    return Vector(NATIVE[name]) * scale


def _point(ref, scale):
    return Vector(ref) * scale if isinstance(ref, tuple) else joint(ref, scale)


def build_armature(name="zombie_rig", scale=1.0):
    arm = bpy.data.armatures.new(name)
    ob = bpy.data.objects.new(name, arm)
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    for b, parent, tail in BONES:
        eb = arm.edit_bones.new(b)
        eb.head = joint(b, scale)
        eb.tail = _point(tail, scale)
        if parent:
            eb.parent = arm.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    return ob


def decimate(ob, target_tris, detail=None):
    """Décimation au budget ; `detail(co) -> 0..1` réserve plus de polygones
    aux zones importantes (visage, mains), via un groupe de sommets."""
    if detail is not None:
        vg = ob.vertex_groups.new(name="_detail")
        for v in ob.data.vertices:
            vg.add([v.index], detail(v.co), "REPLACE")
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    dec = ob.modifiers.new("Decimate", "DECIMATE")
    dec.ratio = min(1.0, target_tris / max(1, tris))
    if detail is not None:
        dec.vertex_group = "_detail"
        dec.invert_vertex_group = True
        dec.vertex_group_factor = 4.0
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    bpy.data.meshes.remove(old)
    ob.vertex_groups.clear()
    return sum(len(p.vertices) - 2 for p in me.polygons)


def skin(mesh_ob, rig_ob):
    """Pondération automatique (chaleur des os)."""
    bpy.ops.object.select_all(action="DESELECT")
    mesh_ob.select_set(True)
    rig_ob.select_set(True)
    bpy.context.view_layer.objects.active = rig_ob
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    return [g.name for g in mesh_ob.vertex_groups]


# Écart des bras à la verticale (radians) : les épaules du corps réaliste sont
# plus étroites que celles du jeu, des bras parfaitement verticaux
# traverseraient le torse. Le repos du jeu reprend ces directions (os
# « forearm » et « shin » décalés en conséquence).
ARM_SPREAD = 0.17
LEG_SPREAD = 0.0


def pose_to_game_rest(rig_ob):
    """Bras et jambes pendants (pose de repos du jeu)."""
    import math
    bpy.context.view_layer.update()
    for b in ("arm_l", "forearm_l", "arm_r", "forearm_r", "thigh_l", "shin_l", "thigh_r", "shin_r"):
        pb = rig_ob.pose.bones[b]
        bpy.context.view_layer.update()
        spread = ARM_SPREAD if b.startswith(("arm", "forearm")) else LEG_SPREAD
        sgn = 1.0 if b.endswith("_l") else -1.0
        down = Vector((sgn * math.sin(spread), 0.0, -math.cos(spread)))
        cur = (pb.tail - pb.head).normalized()
        # Rotation monde -> repère de l'os (matrice de pose courante).
        q = cur.rotation_difference(down)
        mw = pb.matrix.copy()
        loc = mw.translation.copy()
        rot = q.to_matrix().to_4x4() @ mw
        rot.translation = loc
        pb.matrix = rot
    bpy.context.view_layer.update()


def apply_pose(mesh_ob, rig_ob):
    """Fige la pose dans le maillage et en fait le nouveau repos."""
    bpy.context.view_layer.objects.active = mesh_ob
    mod = next(m for m in mesh_ob.modifiers if m.type == "ARMATURE")
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(mesh_ob.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
    old = mesh_ob.data
    mesh_ob.data = me
    bpy.data.meshes.remove(old)
    bpy.context.view_layer.objects.active = rig_ob
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.armature_apply(selected=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    return mod.name
