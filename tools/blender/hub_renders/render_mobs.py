# Portraits en cubes pour le hub : ennemis du CODEX (enemies/) et joueur
# (characters/). PNG transparents 600 × 720, vue de 3/4 FACE (les modèles
# regardent -Y dans Blender), même caméra orthographique, même éclairage et
# même contour noir pour toute la série.
#
#   sh tools/blender.sh tools/blender/hub_renders/render_mobs.py --out assets/ui/hub/renders
#       [--group enemies|characters] [--only walker,player]
#
# Rampant, coureur, sprinteur : le jeu n'a qu'UN modèle de zombie (marcheur) ;
# ces types n'en diffèrent que par leur animation procédurale. Ils sont donc
# rendus à partir de zombie_voxel.glb dans une pose figée qui reprend les
# angles du jeu (ZombieAnim.pose : course / sprint ; ZombieGibs.crawl_pose :
# rampant, tibias arrachés comme ZombieGibs.apply).
#
# Joueur : zone d'équipe (matière « team », peinte en gris 0,8 dans le modèle,
# teintée par assets/shaders/player_voxel.gdshader : sRGB team_color × gris /
# 0,8) rendue en trois versions :
#   player.png            : couleur du joueur 1 (HudStyle.PLAYER_COLORS[0], ambre)
#   player_neutral.png    : zone d'équipe laissée grise (neutre)
#   player_team_mask.png  : UNIQUEMENT la zone d'équipe (le reste transparent,
#                           occultation comprise), blanche à pleine teinte :
#                           posée sur player_neutral.png avec
#                           modulate = couleur du joueur, elle donne la même
#                           teinte que le jeu (team_color × ombrage).
import bpy, math, os, sys
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hub_common as hc  # noqa: E402

W, H = 600, 720
MARGIN = 0.06
OUTLINE = 0.006        # épaisseur du contour (part de la plus grande dimension)
VIEW = Vector((0.6, -1.0, 0.22))   # 3/4 face, légèrement du dessus
# Poses qui se lisent mal de 3/4 face : bras tendus vers la caméra (course),
# corps couché (rampant).
VIEWS = {"runner": Vector((1.0, -0.85, 0.22)), "sprinter": Vector((1.0, -0.85, 0.22)),
         "crawler": Vector((0.75, -1.0, 0.55))}
TEAM_GREY = 0.8
P1_COLOR = (1.0, 0.78, 0.28)       # HudStyle.PLAYER_COLORS[0] (sRGB)

ZOMBIE = "assets/models/zombies/zombie_voxel.glb"
PLAYER = "assets/models/player/player_voxel.glb"

# Poses : os -> (x, y, z) en radians, angles d'Euler de Godot (ordre YXZ,
# repère de Godot), appliqués comme Skeleton3D.set_bone_pose_rotation sur
# des os de repos sans rotation. « _hips_pos » : position du bassin (repère
# Blender, m) ; « _scale » : os réduits à rien (membres arrachés).
# Course et sprint : angles de ZombieAnim.pose (run_k / sprint_k = 1) figés
# en pleine foulée, un peu accentués pour se lire en vignette.
RUN = {  # coureur : penché, foulée, bras tendus vers l'avant qui battent
    "spine": (0.2, 0.0, 0.0), "chest": (0.16, -0.1, -0.05),
    "head": (-0.24, 0.0, 0.08), "jaw": (0.35, 0.0, 0.0),
    "thigh_l": (-0.55, 0.0, 0.0), "shin_l": (0.5, 0.0, 0.0),
    "thigh_r": (0.35, 0.0, 0.0), "shin_r": (0.9, 0.0, 0.0),
    "arm_l": (-1.25, 0.0, 0.0), "forearm_l": (-0.5, 0.0, 0.0),
    "arm_r": (-1.6, 0.0, 0.0), "forearm_r": (-0.45, 0.0, 0.0),
}
SPRINT = {  # sprinteur : très penché, grande foulée, bras raides vers la proie
    "spine": (0.32, 0.0, 0.0), "chest": (0.26, -0.12, -0.04),
    "head": (-0.32, 0.0, 0.05), "jaw": (0.55, 0.0, 0.0),
    "thigh_l": (-0.75, 0.0, 0.0), "shin_l": (0.6, 0.0, 0.0),
    "thigh_r": (0.5, 0.0, 0.0), "shin_r": (1.2, 0.0, 0.0),
    "arm_l": (-1.88, 0.0, 0.0), "forearm_l": (-0.12, 0.0, 0.0),
    "arm_r": (-2.33, 0.0, 0.0), "forearm_r": (-0.12, 0.0, 0.0),
}
CRAWL = {  # rampant (ZombieGibs.crawl_pose, chute finie k = 1)
    "_hips_pos": (0.0, 0.375, 0.24),
    "hips": (1.38, 0.0, 0.06), "spine": (0.04, 0.0, 0.0), "chest": (-0.06, -0.08, 0.035),
    "head": (-1.1, 0.0, 0.1), "jaw": (0.4, 0.0, 0.0),
    "arm_l": (-2.83, 0.0, 0.12), "forearm_l": (-0.5, 0.0, 0.0),
    "arm_r": (-2.07, 0.0, -0.12), "forearm_r": (-0.25, 0.0, 0.0),
    "thigh_l": (-0.07, 0.0, 0.12), "thigh_r": (-0.23, 0.0, -0.12),
    "_scale": ("shin_l", "shin_r"),
}

ENEMIES = [  # (nom, glb, pose)
    ("walker", ZOMBIE, None),
    ("crawler", ZOMBIE, CRAWL),
    ("runner", ZOMBIE, RUN),
    ("sprinter", ZOMBIE, SPRINT),
    ("dog", "assets/models/dogs/dog_voxel.glb", None),
    ("brancardier", "assets/models/brancardier/brancardier_voxel.glb", None),
    ("nurse", "assets/models/nurse/nurse_voxel.glb", None),
    ("surgeon", "assets/models/surgeon/surgeon_voxel.glb", None),
]
CHARACTERS = [  # (nom, glb, variante de la zone d'équipe)
    ("player", PLAYER, "p1"),
    ("player_neutral", PLAYER, "neutral"),
    ("player_team_mask", PLAYER, "mask"),
]


def godot_rot(x, y, z):
    """Quaternion.from_euler((x, y, z)) de Godot (YXZ), exprimé dans le
    repère de Blender (Godot x -> X, y -> Z, z -> -Y)."""
    return (Matrix.Rotation(y, 4, "Z") @ Matrix.Rotation(x, 4, "X") @ Matrix.Rotation(-z, 4, "Y"))


def apply_pose(rig, pose):
    """Pose « à la Godot » : chaque os tourne autour de sa tête, dans le repère
    de son parent déjà posé (D(os) = D(parent) · T(tête) · R · T(-tête))."""
    if not pose:
        return
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="POSE")
    shrink = pose.get("_scale", ())
    deform = {}
    for b in rig.data.bones:  # ordre : parents avant enfants
        h = b.head_local.copy()
        r = godot_rot(*pose.get(b.name, (0.0, 0.0, 0.0)))
        if b.name in shrink:
            r = r @ Matrix.Diagonal((0.001, 0.001, 0.001, 1.0))
        local = Matrix.Translation(h) @ r @ Matrix.Translation(-h)
        if b.parent is None:
            if "_hips_pos" in pose:
                local = Matrix.Translation(Vector(pose["_hips_pos"]) - h) @ local
            deform[b.name] = local
        else:
            deform[b.name] = deform[b.parent.name] @ local
        rig.pose.bones[b.name].matrix = deform[b.name] @ b.matrix_local
        bpy.context.view_layer.update()
    bpy.ops.object.mode_set(mode="OBJECT")


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def linear_to_srgb(c):
    c = max(c, 0.0)
    return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def team_variant(meshes, variant):
    """Zone d'équipe : couleur du joueur 1 (formule du shader), grise
    (neutre) ou masque (zone blanche à pleine teinte, reste en « holdout »)."""
    if variant == "neutral":
        return
    for ob in meshes:
        mats = [m.name.split(".")[0] for m in ob.data.materials]
        if "team" not in mats:
            continue
        ti = mats.index("team")
        col = ob.data.color_attributes.get("Color")
        me = ob.data
        team_loops = set()
        for p in me.polygons:
            if p.material_index == ti:
                team_loops.update(p.loop_indices)
        corner = col.domain == "CORNER"
        if corner:
            idx = team_loops
        else:
            idx = {me.loops[i].vertex_index for i in team_loops}
        for i in idx:
            r, g, b, a = col.data[i].color
            grey = linear_to_srgb(g) / TEAM_GREY
            tint = (1.0, 1.0, 1.0) if variant == "mask" else P1_COLOR
            col.data[i].color = tuple(srgb_to_linear(min(1.0, t * grey)) for t in tint) + (a,)
        if variant == "mask":
            hold = bpy.data.materials.new("holdout")
            hold.use_nodes = True
            nt = hold.node_tree
            nt.nodes.clear()
            hn = nt.nodes.new("ShaderNodeHoldout")
            out = nt.nodes.new("ShaderNodeOutputMaterial")
            nt.links.new(hn.outputs[0], out.inputs[0])
            for i, m in enumerate(me.materials):
                if i != ti:
                    me.materials[i] = hold


def render_one(name, path, pose, out_path, variant=None):
    sc = hc.reset(W, H, 0.5)
    bpy.ops.import_scene.gltf(filepath=path)
    hc.drop_helpers(min_verts=100)
    rig = next((o for o in sc.objects if o.type == "ARMATURE"), None)
    if rig and pose:
        apply_pose(rig, pose)
    meshes = [o for o in sc.objects if o.type == "MESH"]
    lo, hi, pts = hc.bounds(meshes)
    center, size = (lo + hi) / 2, hi - lo
    big = max(size)
    dirv = VIEWS.get(name, VIEW).normalized()
    cam = hc.ortho_camera(sc, center, dirv, big * 4, big)
    bpy.context.view_layer.update()
    hc.fit_ortho(cam, pts, W, H, MARGIN)
    if variant:
        team_variant(meshes, variant)
    om = hc.outline(meshes, big * OUTLINE)
    if variant == "mask":
        # Le contour ne fait pas partie du masque (il cache quand même).
        om.node_tree.nodes.clear()
        hn = om.node_tree.nodes.new("ShaderNodeHoldout")
        out = om.node_tree.nodes.new("ShaderNodeOutputMaterial")
        om.node_tree.links.new(hn.outputs[0], out.inputs[0])
    L = big
    f = -1.0  # le modèle regarde -Y
    hc.light("key", tuple(center + Vector((L * 1.2, f * L * 1.5, L * 1.8))), center, 150 * L * L, L, (0.9, 0.95, 1.0))
    hc.light("fill", tuple(center + Vector((-L * 1.5, f * L, L * 0.5))), center, 50 * L * L, L * 1.5, (0.8, 0.85, 1.0))
    hc.light("rim", tuple(center + Vector((-L * 0.5, -f * L * 1.8, L * 1.2))), center, 250 * L * L, L, (0.5, 1.0, 0.9))
    hc.render(sc, out_path)


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    root = os.path.abspath(args[args.index("--out") + 1])
    only = args[args.index("--only") + 1].split(",") if "--only" in args else None
    group = args[args.index("--group") + 1] if "--group" in args else None
    for name, path, pose in ENEMIES:
        if group in (None, "enemies") and (only is None or name in only):
            render_one(name, path, pose, os.path.join(root, "enemies", name + ".png"))
    for name, path, variant in CHARACTERS:
        if group in (None, "characters") and (only is None or name in only):
            render_one(name, path, None, os.path.join(root, "characters", name + ".png"), variant)


main()
