extends RefCounted
## Independently authored native material families. Other source enums unsupported.
const SHADERS := {
	0: preload("res://src/presentation/material_opaque.gdshader"),
	1: preload("res://src/presentation/material_alpha.gdshader"),
	2: preload("res://src/presentation/material_additive.gdshader"),
	3: preload("res://src/presentation/material_additive_twosided.gdshader"),
	6: preload("res://src/presentation/material_lit.gdshader"),
	# Original opaque cutouts: alpha test with depth writes, no blending.
	10: preload("res://src/presentation/material_cutout.gdshader"),
	18: preload("res://src/presentation/material_alpha.gdshader"),
	28: preload("res://src/presentation/imported_material.gdshader")}

static func supports(descriptor: Dictionary) -> bool:
	if not SHADERS.has(int(descriptor.get("render_type", -1))):
		return false
	var slots: Array = descriptor.get("texture_paths", [])
	var used := 2 if int(descriptor.render_type) == 28 else 1
	return slots.size() == 8 and slots.slice(used).all(func(path): return path.is_empty())

static func create(render_type: int, diffuse: Texture2D, normal_specular: Texture2D, colors: bool) -> ShaderMaterial:
	if not SHADERS.has(render_type):
		return null
	var material := ShaderMaterial.new()
	material.shader = SHADERS[render_type]
	# Source type 18 joins the later alpha pass, after ordinary additive type 2.
	# Keep the material identifier; only the native shader arithmetic is shared.
	if render_type == 18: material.render_priority = 1
	material.set_shader_parameter("has_diffuse", diffuse != null)
	material.set_shader_parameter("has_vertex_color", colors)
	if diffuse != null:
		material.set_shader_parameter("diffuse_texture", diffuse)
	if render_type == 28:
		material.set_shader_parameter("has_normal_specular", normal_specular != null)
		if normal_specular != null:
			material.set_shader_parameter("normal_specular_texture", normal_specular)
	return material
