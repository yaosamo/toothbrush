"""Convert GLB -> USDZ with Blender.

usage: blender -b --python convert.py -- <in.glb> <out.usdz> <target_height_m> [ActionName ...]

If action names are given, those actions are laid end to end on the timeline and
the frame ranges are printed as JSON (CLIPS ...), so the app can trim them apart.
"""
import bpy, sys, json, mathutils

args = sys.argv[sys.argv.index("--") + 1:]
src, dst, height = args[0], args[1], float(args[2])
wanted = args[3:]

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = 30
bpy.ops.import_scene.gltf(filepath=src)

# Normalise size: scale the whole import so it is `height` metres tall, sitting on z=0.
roots = [o for o in bpy.data.objects if o.parent is None]
bpy.context.view_layer.update()
mins = [1e9] * 3; maxs = [-1e9] * 3
for o in bpy.data.objects:
    if o.type == 'MESH':
        for c in o.bound_box:
            w = o.matrix_world @ mathutils.Vector(c)
            for i in range(3): mins[i] = min(mins[i], w[i]); maxs[i] = max(maxs[i], w[i])
s = height / (maxs[2] - mins[2])
cx, cy = (mins[0] + maxs[0]) / 2, (mins[1] + maxs[1]) / 2
holder = bpy.data.objects.new("Root", None)
scene.collection.objects.link(holder)
for r in roots:
    r.parent = holder
holder.scale = (s, s, s)
holder.location = (-cx * s, -cy * s, -mins[2] * s)
bpy.context.view_layer.update()
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.transform_apply(location=False, rotation=False, scale=False)

clips = {}
arm = next((o for o in bpy.data.objects if o.type == 'ARMATURE'), None)
if arm and wanted:
    actions = {a.name.split("|")[-1]: a for a in bpy.data.actions}
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = None
    for t in list(ad.nla_tracks): ad.nla_tracks.remove(t)
    track = ad.nla_tracks.new()
    frame = 1
    for name in wanted:
        a = actions[name]
        start, end = a.frame_range
        strip = track.strips.new(name, int(frame), a)
        strip.action_frame_start, strip.action_frame_end = start, end
        length = end - start
        clips[name] = [frame, frame + length]
        frame += length + 1
    scene.frame_start, scene.frame_end = 1, int(frame)

bpy.ops.wm.usd_export(
    filepath=dst,
    export_animation=bool(clips),
    export_armatures=True,
    export_materials=True,
    generate_preview_surface=True,
    export_textures=True,
    convert_orientation=True,
    export_global_forward_selection='NEGATIVE_Z',
    export_global_up_selection='Y',
)
print("CLIPS", json.dumps({"fps": scene.render.fps, "clips": clips}))
