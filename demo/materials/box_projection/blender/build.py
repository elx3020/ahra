# Run from anywhere: blender -b --factory-startup --python build.py  (rebuilds box_projection.blend from scratch)
# Builds demo/materials/box_projection/blender/box_projection.blend, bakes noise.png from a
# procedural Noise Texture, exports shapes.glb and renders unlit references for compare.gd.
import bpy, math, os
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BL = os.path.join(ROOT, "blender")
RES = (960, 540)
SCALE = 0.5      # Mapping scale: one texture tile every 2 m
BLEND = 0.25     # Image Texture box blend
CAM_POS = (0.0, -12.0, 6.5)
CAM_TARGET = (0.0, 0.5, 0.6)
FOV_Y = 35.0
COLOR_A = "2f3b33"
COLOR_B = "b9ae94"


def lin(h):
    def f(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return tuple(f(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4)) + (1.0,)


bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
view_layer = bpy.context.view_layer


def node(nt, kind, x, y, **props):
    n = nt.nodes.new(kind)
    n.location = (x, y)
    for k, v in props.items():
        setattr(n, k, v)
    return n


def new_material(name):
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    m.node_tree.nodes.clear()
    return m, m.node_tree


def math_node(nt, op, a, b, x, y):
    n = node(nt, "ShaderNodeMath", x, y, operation=op)
    nt.links.new(a, n.inputs[0])
    if b is not None:
        n.inputs[1].default_value = b
    return n.outputs[0]


# --- Procedural noise, baked to a tileable noise.png -------------------------------------
# UV (u, v) goes around two circles in 4D: (cos u, sin u, cos v, sin v), so the 4D noise
# wraps seamlessly on both axes.
bake_col = bpy.data.collections.new("NoiseBake")
scene.collection.children.link(bake_col)
bpy.ops.mesh.primitive_plane_add(size=1, location=(0, -30, 0))
plane = bpy.context.active_object
plane.name = "NoiseBake"
for c in plane.users_collection:
    c.objects.unlink(plane)
bake_col.objects.link(plane)

bm, nt = new_material("noise_bake")
tc = node(nt, "ShaderNodeTexCoord", -1200, 0)
sep = node(nt, "ShaderNodeSeparateXYZ", -1000, 0)
nt.links.new(tc.outputs["UV"], sep.inputs[0])
au = math_node(nt, "MULTIPLY", sep.outputs[0], math.tau, -800, 100)
av = math_node(nt, "MULTIPLY", sep.outputs[1], math.tau, -800, -100)
comb = node(nt, "ShaderNodeCombineXYZ", -400, 100)
nt.links.new(math_node(nt, "COSINE", au, None, -600, 200), comb.inputs[0])
nt.links.new(math_node(nt, "SINE", au, None, -600, 100), comb.inputs[1])
nt.links.new(math_node(nt, "COSINE", av, None, -600, 0), comb.inputs[2])
sv = math_node(nt, "SINE", av, None, -600, -100)
noise = node(nt, "ShaderNodeTexNoise", -200, 0, noise_dimensions="4D", noise_type="FBM")
nt.links.new(comb.outputs[0], noise.inputs["Vector"])
nt.links.new(sv, noise.inputs["W"])
noise.inputs["Scale"].default_value = 0.9
noise.inputs["Detail"].default_value = 5.0
noise.inputs["Roughness"].default_value = 0.55
noise.inputs["Lacunarity"].default_value = 2.0
noise.inputs["Distortion"].default_value = 0.0
contrast = node(nt, "ShaderNodeMapRange", 0, 0, clamp=True)
nt.links.new(noise.outputs["Fac"], contrast.inputs["Value"])
contrast.inputs["From Min"].default_value = 0.25
contrast.inputs["From Max"].default_value = 0.75
emit = node(nt, "ShaderNodeEmission", 200, 0)
nt.links.new(contrast.outputs["Result"], emit.inputs["Color"])
out = node(nt, "ShaderNodeOutputMaterial", 400, 0)
nt.links.new(emit.outputs[0], out.inputs["Surface"])
bake_target = node(nt, "ShaderNodeTexImage", 200, 300)
bake_target.label = "Bake target (Bake type Emit)"
plane.data.materials.append(bm)

gen = bpy.data.images.new("noise_bake", 1024, 1024, alpha=False)
bake_target.image = gen
nt.nodes.active = bake_target
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 16
for o in scene.objects:
    o.select_set(False)
plane.select_set(True)
view_layer.objects.active = plane
bpy.ops.object.bake(type="EMIT", margin=0)
noise_path = os.path.join(ROOT, "noise.png")
gen.filepath_raw = noise_path
gen.file_format = "PNG"
gen.save()
noise_img = bpy.data.images.load(noise_path)
noise_img.name = "noise.png"
bake_target.image = noise_img
bpy.data.images.remove(gen)

grid = bpy.data.images.new("grid", 1024, 1024, alpha=False)
grid.generated_type = "COLOR_GRID"
grid_path = os.path.join(BL, "grid.png")
grid.filepath_raw = grid_path
grid.file_format = "PNG"
grid.save()
grid_img = bpy.data.images.load(grid_path)
grid_img.name = "grid.png"
grid_img.use_fake_user = True
bpy.data.images.remove(grid)

# --- Box projection material -------------------------------------------------------------
mat, nt = new_material("box_noise")
tc = node(nt, "ShaderNodeTexCoord", -800, 0)
mp = node(nt, "ShaderNodeMapping", -600, 0, vector_type="POINT")
mp.inputs["Scale"].default_value = (SCALE, SCALE, SCALE)
nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
tex = node(nt, "ShaderNodeTexImage", -400, 0, projection="BOX", projection_blend=BLEND,
           interpolation="Linear", extension="REPEAT")
tex.image = noise_img
nt.links.new(mp.outputs[0], tex.inputs["Vector"])
ramp = node(nt, "ShaderNodeValToRGB", -100, 0)
ramp.color_ramp.interpolation = "LINEAR"
ramp.color_ramp.elements[0].color = lin(COLOR_A)
ramp.color_ramp.elements[1].color = lin(COLOR_B)
nt.links.new(tex.outputs["Color"], ramp.inputs["Fac"])
bsdf = node(nt, "ShaderNodeBsdfPrincipled", 250, 0)
bsdf.inputs["Roughness"].default_value = 0.8
nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
mout = node(nt, "ShaderNodeOutputMaterial", 550, 0)
nt.links.new(bsdf.outputs[0], mout.inputs["Surface"])

# --- Shapes ------------------------------------------------------------------------------
shapes = []


def add(kind, name, loc, smooth=None, scale=None, apply_scale=False, **kw):
    getattr(bpy.ops.mesh, "primitive_" + kind + "_add")(location=loc, **kw)
    o = bpy.context.active_object
    o.name = name
    o.data.name = name
    if scale:
        o.scale = scale
        if apply_scale:
            bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if smooth == "all":
        bpy.ops.object.shade_smooth()
    elif smooth:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(smooth))
    o.data.materials.append(mat)
    view_layer.update()
    low = min((o.matrix_world @ v.co).z for v in o.data.vertices)
    if name != "Ground":
        o.location.z -= low
    shapes.append(o)
    return o


add("plane", "Ground", (0, 0, 0), size=1, scale=(14, 9, 1), apply_scale=True)
add("cube", "CubeSmall", (-4.5, -1.8, 0), size=0.5)
add("uv_sphere", "Sphere", (-2.5, -1.8, 0), smooth="all", radius=0.8, segments=48, ring_count=24)
monkey = add("monkey", "Monkey", (0, -1.8, 0), smooth="all", size=1.4)
monkey.modifiers.new("Subdivision", "SUBSURF").levels = 1
add("torus", "Torus", (2.5, -1.8, 0), smooth="all", major_radius=0.6, minor_radius=0.22,
    rotation=(math.radians(70), 0, math.radians(20)))
add("ico_sphere", "Ico", (4.6, -1.8, 0), subdivisions=1, radius=0.6)
add("cube", "CubeBig", (-4.3, 1.2, 0), size=2.0)
add("cylinder", "Cylinder", (-1.9, 1.2, 0), smooth=30, radius=0.5, depth=2.4, vertices=32)
add("cone", "Cone", (0.0, 1.2, 0), smooth=30, radius1=0.9, depth=1.8, vertices=32)
add("cube", "Rotated", (2.2, 1.2, 0), size=1.2,
    rotation=(math.radians(25), math.radians(15), math.radians(35)))
add("uv_sphere", "Stretched", (4.6, 1.2, 0), smooth="all", radius=0.5, scale=(2.2, 0.8, 0.8))
add("cube", "Wall", (0.0, 3.6, 0), size=1, scale=(6, 0.4, 2.5), apply_scale=True)

# --- Camera, light, world ----------------------------------------------------------------
cam_data = bpy.data.cameras.new("Camera")
cam_data.sensor_fit = "VERTICAL"
cam_data.angle_y = math.radians(FOV_Y)
cam = bpy.data.objects.new("Camera", cam_data)
scene.collection.objects.link(cam)
cam.location = CAM_POS
cam.rotation_euler = (Vector(CAM_TARGET) - Vector(CAM_POS)).to_track_quat("-Z", "Y").to_euler()
scene.camera = cam
print("camera fov_y", math.degrees(cam_data.angle_y))

sun_data = bpy.data.lights.new("Sun", "SUN")
sun_data.energy = 3.0
sun = bpy.data.objects.new("Sun", sun_data)
scene.collection.objects.link(sun)
sun.rotation_euler = (math.radians(50), 0, math.radians(30))

world = bpy.data.worlds.new("World")
scene.world = world
try:
    world.use_nodes = True
except Exception:
    pass
bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
bg.inputs["Color"].default_value = (0.35, 0.42, 0.55, 1)
bg.inputs["Strength"].default_value = 0.6

scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x, scene.render.resolution_y = RES
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = "Standard"

# --- Export + save -----------------------------------------------------------------------
for o in scene.objects:
    o.select_set(o in shapes)
gltf = dict(filepath=os.path.join(ROOT, "shapes.glb"), export_format="GLB", use_selection=True,
            export_apply=True, export_yup=True, export_cameras=False, export_lights=False)
try:
    bpy.ops.export_scene.gltf(export_image_format="NONE", **gltf)
except TypeError:
    bpy.ops.export_scene.gltf(**gltf)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BL, "box_projection.blend"))

# --- Unlit references (not saved into the .blend) ----------------------------------------
emit = node(nt, "ShaderNodeEmission", 250, -300)
nt.links.new(tex.outputs["Color"], emit.inputs["Color"])
nt.links.new(emit.outputs[0], mout.inputs["Surface"])
bg.inputs["Strength"].default_value = 0.0
scene.render.dither_intensity = 0.0
scene.render.film_transparent = False
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGB"
scene.render.image_settings.color_depth = "8"
scene.view_settings.look = "None"
scene.view_settings.exposure = 0.0
scene.view_settings.gamma = 1.0

# One unjittered sample, no pixel filter: aliased edges like Godot without MSAA.
scene.render.engine = "BLENDER_EEVEE"
scene.eevee.taa_render_samples = 1
scene.render.filter_size = 0.0
# Must match CASES in compare.gd.
for name, img, blend in (("noise", noise_img, BLEND), ("grid", grid_img, 0.0), ("grid_blend", grid_img, 0.6)):
    tex.image = img
    tex.projection_blend = blend
    scene.render.filepath = os.path.join(BL, f"ref_{name}.png")
    bpy.ops.render.render(write_still=True)
print("BUILD OK")
