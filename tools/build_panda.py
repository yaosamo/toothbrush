"""Build "Bao", BrushWatch's original panda, procedurally in Blender.

usage:
  blender -b --factory-startup --python tools/build_panda.py -- <out.usdz> [preview_dir]

Bao is a chubby toy-style panda made of smooth shapes on a hierarchy of pivot
empties (no skinning), so every animation is plain transform keyframes that
export cleanly to USD and play in RealityKit. Clips are laid end to end on one
timeline at 30 fps; their frame ranges are printed as CLIPS {...} and must match
PandaDirector.ranges in the app.

Axes (Blender): Z up, the panda faces -Y (front view). Units: metres.
"""
import bpy, bmesh, sys, json, math, os
from mathutils import Vector, Matrix, Quaternion

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = args[0] if args else "/tmp/Bao.usdz"
PREVIEW = args[1] if len(args) > 1 else None

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = 30

# ---------------------------------------------------------------- materials

def mat(name, color, rough=0.75, metal=0.0, emit=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (*color, 1)
        b.inputs["Emission Strength"].default_value = emit
    return m

FUR_W  = mat("FurWhite", (0.86, 0.84, 0.79), 0.85)
FUR_B  = mat("FurBlack", (0.014, 0.013, 0.017), 0.85)
MUZZLE = mat("Muzzle",   (0.93, 0.91, 0.86), 0.8)
NOSE   = mat("Nose",     (0.32, 0.13, 0.12), 0.35)
PINK   = mat("Pink",     (0.85, 0.42, 0.42), 0.7)
BLUSH  = mat("Blush",    (0.95, 0.48, 0.48), 0.9)
EYE_W  = mat("EyeWhite", (0.95, 0.95, 0.93), 0.25)
IRIS   = mat("Iris",     (0.78, 0.40, 0.05), 0.2)
PUPIL  = mat("Pupil",    (0.01, 0.01, 0.012), 0.08)
SHINE  = mat("Shine",    (1, 1, 1), 0.1, emit=2.0)
MOUTH  = mat("Mouth",    (0.12, 0.04, 0.04), 0.5)
SCARF  = mat("Scarf",    (0.62, 0.04, 0.035), 0.6)
GOLD   = mat("Gold",     (0.95, 0.66, 0.2), 0.28, metal=1.0)
HANDLE = mat("Handle",   (0.12, 0.55, 0.92), 0.3)
BRISTLE= mat("Bristle",  (0.95, 0.97, 1.0), 0.6)
FOAM   = mat("Foam",     (0.86, 1.0, 0.95), 0.9)

# ---------------------------------------------------------------- helpers

def empty(name, parent=None, loc=(0, 0, 0)):
    e = bpy.data.objects.new(name, None)
    scene.collection.objects.link(e)
    e.parent = parent
    e.location = loc
    return e

def _finish(o, name, parent, loc, rot, material):
    o.name = name
    o.parent = parent
    o.location = loc
    o.rotation_euler = rot
    if material:
        o.data.materials.append(material)
    for p in o.data.polygons:
        p.use_smooth = True
    return o

def blob(name, parent, loc, scale, material, rot=(0, 0, 0), seg=48):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, radius=1)
    o = bpy.context.object
    o.scale = scale
    return _finish(o, name, parent, loc, rot, material)

def cyl(name, parent, loc, radius, depth, material, rot=(0, 0, 0), verts=32):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth)
    o = bpy.context.object
    bev = o.modifiers.new("bevel", "BEVEL"); bev.width = min(radius, depth) * 0.3; bev.segments = 3
    return _finish(o, name, parent, loc, rot, material)

def torus(name, parent, loc, major, minor, material, rot=(0, 0, 0), keep=None, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=64, minor_segments=16)
    o = bpy.context.object
    if keep:  # keep only verts satisfying keep(local co): used to make a smile arc
        bm = bmesh.new(); bm.from_mesh(o.data)
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not keep(v.co)], context="VERTS")
        bm.to_mesh(o.data); bm.free()
    o.scale = scale
    return _finish(o, name, parent, loc, rot, material)

# ---------------------------------------------------------------- build

root = empty("Bao")
rig = empty("Rig", root)                       # whole-body moves (jump)
torso = empty("Torso", rig, (0, 0, 0.22))      # waist pivot
head = empty("Head", torso, (0, 0, 0.50))      # neck pivot
arm_l = empty("ArmL", torso, (0.25, 0, 0.36))  # shoulders
arm_r = empty("ArmR", torso, (-0.25, 0, 0.36))
leg_l = empty("LegL", rig, (0.15, -0.02, 0.17))
leg_r = empty("LegR", rig, (-0.15, -0.02, 0.17))

# Body: round white belly with the black shoulder band pandas have.
blob("Body", torso, (0, 0, 0.20), (0.33, 0.29, 0.32), FUR_W)
blob("ShoulderBand", torso, (0, 0.01, 0.38), (0.305, 0.275, 0.115), FUR_B)

# Scarf with a gold bell.
torus("Scarf", torso, (0, 0, 0.465), 0.175, 0.07, SCARF, scale=(1.1, 1.04, 0.55))
blob("ScarfTail", torso, (0.09, -0.19, 0.38), (0.05, 0.022, 0.085), SCARF, rot=(0.2, 0.3, 0.25))
blob("Bell", torso, (0, -0.215, 0.42), (0.042, 0.042, 0.042), GOLD)

# Legs: stubby black ellipsoids with pink paw pads.
for side, leg in ((1, leg_l), (-1, leg_r)):
    blob(f"Leg{'L' if side > 0 else 'R'}", leg, (0, 0, -0.07), (0.125, 0.135, 0.105), FUR_B)
    blob(f"Pad{'L' if side > 0 else 'R'}", leg, (0, -0.125, -0.085), (0.06, 0.02, 0.045), PINK, rot=(0.25, 0, 0))

# Arms: black, slightly angled outward, round paws.
for side, arm in ((1, arm_l), (-1, arm_r)):
    s = "L" if side > 0 else "R"
    blob(f"Arm{s}", arm, (side * 0.035, 0, -0.12), (0.085, 0.09, 0.15), FUR_B, rot=(0, side * 0.3, 0))
    blob(f"Paw{s}", arm, (side * 0.07, -0.01, -0.24), (0.08, 0.08, 0.08), FUR_B)

# Toothbrush in the right paw (bristles face forward).
brush = empty("Toothbrush", arm_r, (-0.07, -0.07, -0.26))
cyl("BrushHandle", brush, (0, 0, 0.11), 0.021, 0.26, HANDLE)
cyl("BrushHead", brush, (0, -0.004, 0.265), 0.024, 0.07, HANDLE)
blob("Bristles", brush, (0, -0.03, 0.27), (0.02, 0.02, 0.04), BRISTLE)

# Head: big and round, chubby cheeks, small muzzle.
blob("Skull", head, (0, 0, 0.23), (0.345, 0.3, 0.295), FUR_W)
for side in (1, -1):
    s = "L" if side > 0 else "R"
    blob(f"Cheek{s}", head, (side * 0.15, -0.1, 0.14), (0.17, 0.16, 0.13), FUR_W)
    # Round, droopy eye patches (outer edge lower), hugging the face.
    blob(f"Patch{s}", head, (side * 0.125, -0.238, 0.27), (0.095, 0.06, 0.08), FUR_B,
         rot=(0.15, side * -0.35, side * 0.5))
    blob(f"EyeWhite{s}", head, (side * 0.118, -0.279, 0.283), (0.043, 0.032, 0.045), EYE_W, rot=(0, 0, side * 0.35))
    blob(f"Iris{s}", head, (side * 0.11, -0.304, 0.28), (0.029, 0.012, 0.032), IRIS, rot=(0, 0, side * 0.35))
    blob(f"Pupil{s}", head, (side * 0.108, -0.314, 0.28), (0.016, 0.008, 0.019), PUPIL, rot=(0, 0, side * 0.35))
    blob(f"Shine{s}", head, (side * 0.098, -0.321, 0.295), (0.008, 0.004, 0.008), SHINE, seg=16)
    blob(f"Brow{s}", head, (side * 0.118, -0.262, 0.335), (0.05, 0.016, 0.012), FUR_B, rot=(0.1, side * -0.28, side * 0.3))
    blob(f"Blush{s}", head, (side * 0.215, -0.225, 0.17), (0.042, 0.012, 0.026), BLUSH, rot=(0, 0, side * 0.7))
    blob(f"Ear{s}", head, (side * 0.235, 0.01, 0.45), (0.09, 0.065, 0.085), FUR_B, rot=(0, side * 0.35, 0))
    blob(f"EarTuft{s}", head, (side * 0.255, 0.0, 0.525), (0.025, 0.02, 0.035), FUR_B, rot=(0, side * 0.5, 0))

blob("Muzzle", head, (0, -0.25, 0.16), (0.115, 0.08, 0.075), MUZZLE)
blob("Nose", head, (0, -0.325, 0.195), (0.05, 0.03, 0.032), NOSE, rot=(-0.25, 0, 0))
blob("NoseShine", head, (0.014, -0.35, 0.21), (0.011, 0.004, 0.006), SHINE, seg=16)
# Smile: lower half of a thin torus, standing in the face plane.
torus("Smile", head, (0.005, -0.318, 0.175), 0.075, 0.011, MOUTH, rot=(math.pi / 2, 0, 0.0), scale=(1, 0.55, 1),
      keep=lambda co: co.y < -0.05)

# Toothpaste foam around the mouth; scaled to 0 except while brushing.
foam = empty("Foam", head, (0, -0.322, 0.13))
for i, (x, z, r) in enumerate([(-0.04, 0.0, 0.022), (0.0, -0.012, 0.026), (0.042, 0.004, 0.02), (-0.018, 0.022, 0.014), (0.024, 0.024, 0.012)]):
    blob(f"Foam{i}", foam, (x, -0.012, z), (r, r * 0.8, r), FOAM, seg=20)

# ---------------------------------------------------------------- animation

ANIM = [rig, torso, head, arm_l, arm_r, leg_l, leg_r, brush]
REST = {o.name: (o.location.copy(), o.rotation_euler.copy(), o.scale.copy()) for o in ANIM}
clips = {}

def key(o, f, loc=None, rot=None, scale=None):
    l, r, s = REST[o.name]
    o.location = Vector(l) + Vector(loc or (0, 0, 0))
    o.rotation_euler = (r.x + (rot or (0, 0, 0))[0], r.y + (rot or (0, 0, 0))[1], r.z + (rot or (0, 0, 0))[2])
    o.scale = scale or s
    for path in ("location", "rotation_euler", "scale"):
        o.keyframe_insert(path, frame=f)

def rest(f):
    for o in ANIM:
        key(o, f)

def foam_key(f, on):
    foam.scale = (1, 1, 1) if on else (0.001, 0.001, 0.001)
    foam.keyframe_insert("scale", frame=f)

cursor = 1
def clip(name, length):
    global cursor
    start, end = cursor, cursor + length
    clips[name] = [start, end]
    rest(start); rest(end)
    foam_key(start, name == "Brush"); foam_key(end, name == "Brush")
    cursor = end + 1
    return start

# Idle (2 s): breathing + gentle head sway.
s = clip("Idle", 60)
key(torso, s + 30, scale=(1.015, 1.015, 1.03))
key(head, s + 15, rot=(0.03, 0, 0.05)); key(head, s + 45, rot=(0.03, 0, -0.05))
key(arm_l, s + 30, rot=(0, -0.06, 0)); key(arm_r, s + 30, rot=(0, 0.06, 0))

# Wave (2 s): left arm up, paw waves, head tilts.
s = clip("Wave", 60)
for f, a in ((8, -2.55), (16, -2.25), (24, -2.65), (32, -2.25), (40, -2.65), (48, -2.4)):
    key(arm_l, s + f, rot=(-0.55, a * 0.85, 0.0))
key(head, s + 12, rot=(0, 0.14, 0.12)); key(head, s + 46, rot=(0, 0.14, 0.12))
key(torso, s + 20, rot=(0, 0.05, 0.08)); key(torso, s + 44, rot=(0, 0.05, 0.08))

# Brush (1 s loop): right paw comes up in front of the chest and the brush
# reaches the mouth. Poses are solved from the real rest positions.
s = clip("Brush", 30)
scene.frame_set(s); bpy.context.view_layer.update()
shoulder = arm_r.matrix_world.translation.copy()
paw_rest = Vector(brush.location)                       # brush origin = inside the paw, in arm space
paw_goal = shoulder + Vector((0.07, -0.22, 0.13))       # in front of the chest
mouth = head.matrix_world @ Vector((-0.01, -0.345, 0.175))
q_arm = paw_rest.rotation_difference(paw_goal - shoulder)
z = (mouth - paw_goal).normalized()                     # handle axis points at the mouth
b = Vector((0, 1, 0)); b = (b - z * b.dot(z)).normalized()   # bristles (-Y) face into the mouth
y = -b; x = y.cross(z)
brush_rot = (q_arm.to_matrix().inverted() @ Matrix((x, y, z)).transposed()).to_euler()
prev = None
for f, dz in ((4, 0.0), (8, 0.09), (12, -0.09), (16, 0.09), (20, -0.09), (24, 0.09), (27, 0.0)):
    e = (Quaternion((0, 0, 1), dz) @ q_arm).to_euler("XYZ", prev) if prev else (Quaternion((0, 0, 1), dz) @ q_arm).to_euler()
    prev = e
    key(arm_r, s + f, rot=tuple(e))
    key(brush, s + f, rot=tuple(brush_rot))
key(head, s + 8, rot=(-0.05, 0, -0.05)); key(head, s + 20, rot=(-0.05, 0, -0.02))

# Jump (1.3 s): squash, leap with both arms up, land.
s = clip("Jump", 40)
key(rig, s + 6, scale=(1.06, 1.06, 0.9))
key(rig, s + 16, loc=(0, 0, 0.32), scale=(0.96, 0.96, 1.06))
key(rig, s + 26, loc=(0, 0, 0.0), scale=(1.08, 1.08, 0.88))
key(rig, s + 32, scale=(1, 1, 1))
for f, a in ((6, 0.3), (16, 2.7), (26, 1.2)):
    key(arm_l, s + f, rot=(0, -a, 0)); key(arm_r, s + f, rot=(0, a, 0))
key(leg_l, s + 16, rot=(0.4, 0, 0)); key(leg_r, s + 16, rot=(-0.3, 0, 0))
key(head, s + 16, rot=(-0.18, 0, 0))

# Yes (1.3 s): proud double nod, chest out.
s = clip("Yes", 40)
for f, a in ((8, 0.22), (15, -0.05), (23, 0.22), (31, -0.03)):
    key(head, s + f, rot=(a, 0, 0))
key(torso, s + 12, rot=(-0.06, 0, 0), scale=(1.02, 1.02, 1.03)); key(torso, s + 32, rot=(-0.06, 0, 0))

# Giggle (1.2 s): when tapped, wiggles side to side.
s = clip("Giggle", 36)
for f, a in ((5, 0.14), (11, -0.14), (17, 0.12), (23, -0.1), (29, 0.05)):
    key(torso, s + f, rot=(0, a, 0))
    key(head, s + f, rot=(0, -a * 0.8, a * 0.5))
key(arm_l, s + 10, rot=(0, -0.5, 0)); key(arm_r, s + 10, rot=(0, 0.5, 0))
key(arm_l, s + 26, rot=(0, -0.5, 0)); key(arm_r, s + 26, rot=(0, 0.5, 0))

for o in ANIM + [foam]:
    if o.animation_data and o.animation_data.action:
        for fc in o.animation_data.action.fcurves:
            for kp in fc.keyframe_points:
                kp.interpolation = "CONSTANT" if o is foam else "BEZIER"
scene.frame_start, scene.frame_end = 1, cursor

# ---------------------------------------------------------------- preview renders

if PREVIEW:
    os.makedirs(PREVIEW, exist_ok=True)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    scene.collection.objects.link(cam)
    cam.data.lens = 60
    scene.camera = cam
    for name, loc, energy, size in (("Key", (2.0, -3.0, 3.0), 600, 2.5), ("Fill", (-3.0, -2.0, 1.5), 250, 3), ("Rim", (0, 3, 2.5), 400, 2)):
        l = bpy.data.objects.new(name, bpy.data.lights.new(name, "AREA"))
        l.data.energy = energy; l.data.size = size
        scene.collection.objects.link(l); l.location = loc
        l.rotation_euler = (Vector((0, 0, 0.6)) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    world = bpy.data.worlds.new("W"); scene.world = world; world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.95, 0.88, 0.78, 1)
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.6
    bpy.ops.mesh.primitive_plane_add(size=6)
    bpy.context.object.data.materials.append(mat("Floor", (0.9, 0.82, 0.7), 0.9))
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = 900, 1000
    views = {"front": (0, -2.9, 0.85), "three_quarter": (1.7, -2.4, 1.0)}
    shots = [("front", 1, "idle"), ("three_quarter", 1, "idle"), ("front", clips["Brush"][0] + 8, "brush"),
             ("front", clips["Wave"][0] + 8, "wave"), ("front", clips["Jump"][0] + 16, "jump")]
    for view, frame, label in shots:
        cam.location = views[view]
        cam.rotation_euler = (Vector((0, 0, 0.62)) - Vector(views[view])).to_track_quat("-Z", "Y").to_euler()
        scene.frame_set(frame)
        scene.render.filepath = os.path.join(PREVIEW, f"{label}_{view}.png")
        bpy.ops.render.render(write_still=True)
    # Lights/camera/floor must not end up in the USD.
    for o in [o for o in scene.objects if o.type in ("CAMERA", "LIGHT") or o.name.startswith("Plane")]:
        bpy.data.objects.remove(o)

# ---------------------------------------------------------------- bake to a skeleton
# RealityKit ignores USD transform animation on plain prims, but plays skeletal
# animation. So: one bone per pivot empty, motion baked per frame, and every part
# rigidly skinned (weight 1) to the bone of the pivot it hangs from.

def bake_to_skeleton():
    pivots = [root, rig, torso, head, arm_l, arm_r, leg_l, leg_r, brush, foam]
    frames = range(scene.frame_start, scene.frame_end + 1)
    scene.frame_set(1); bpy.context.view_layer.update()
    rest_world = {e.name: e.matrix_world.copy() for e in pivots}
    samples = {f: {} for f in frames}
    for f in frames:
        scene.frame_set(f)
        for e in pivots:
            samples[f][e.name] = e.matrix_world.copy()

    arm_data = bpy.data.armatures.new("BaoSkeleton")
    arm_obj = bpy.data.objects.new("BaoRig", arm_data)
    scene.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")
    for e in pivots:
        b = arm_data.edit_bones.new(e.name)
        head_pos = rest_world[e.name].translation
        b.head = head_pos
        b.tail = head_pos + Vector((0, 0, 0.08))
        if e.parent in pivots:
            b.parent = arm_data.edit_bones[e.parent.name]
    bpy.ops.object.mode_set(mode="POSE")
    rest_bone = {b.name: b.matrix_local.copy() for b in arm_data.bones}
    order = [e.name for e in pivots]  # parents before children
    for f in frames:
        scene.frame_set(f)
        for name in order:
            pb = arm_obj.pose.bones[name]
            pb.matrix = samples[f][name] @ rest_world[name].inverted() @ rest_bone[name]
            bpy.context.view_layer.update()
            pb.keyframe_insert("location", frame=f)
            pb.keyframe_insert("rotation_quaternion", frame=f)
            pb.keyframe_insert("scale", frame=f)
    bpy.ops.object.mode_set(mode="OBJECT")

    # Rigidly skin every mesh to its pivot's bone, then merge into one mesh.
    scene.frame_set(1); bpy.context.view_layer.update()
    meshes = [o for o in scene.objects if o.type == "MESH" and o.parent in pivots]
    for o in meshes:
        bone = o.parent.name
        for m in list(o.modifiers):  # bake bevels etc. into the mesh
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.modifier_apply(modifier=m.name)
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
        o.data.transform(mw)
        o.matrix_world.identity()
        vg = o.vertex_groups.new(name=bone)
        vg.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    body = bpy.context.object
    body.name = "BaoMesh"
    body.parent = arm_obj
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = arm_obj
    for e in pivots:
        bpy.data.objects.remove(e)

bake_to_skeleton()

scene.frame_set(1)
bpy.ops.wm.usd_export(
    filepath=OUT, export_animation=True, export_materials=True, generate_preview_surface=True,
    export_armatures=True, only_deform_bones=False,
    convert_orientation=True, export_global_forward_selection="NEGATIVE_Z", export_global_up_selection="Y",
)
print("CLIPS", json.dumps({"fps": scene.render.fps, "clips": clips}))
