extends RefCounted
## Shared material and surface adapter for source type-2 animated weapon models.
const ShaderSource=preload("res://src/presentation/effect_additive.gdshader")
const Sampler=preload("res://src/presentation/scenery_animation.gd")
const Colors=preload("res://src/presentation/effect_color.gd")
var error:=""
var reflected: Shader

func _init() -> void:
	# Godot automatically reverses culling for mirrored instance transforms.
	# Counter that adjustment while preserving source screen winding.
	reflected=Shader.new();reflected.code=ShaderSource.code.replace("cull_back","cull_front")

func prepare_model(model: Node3D) -> bool:
	error=""
	for i in model.surfaces.size():
		var surface: Dictionary=model.surfaces[i]
		if surface.uvs.is_empty() or surface.normals.is_empty() or not surface.colors.is_empty() or not surface.tracks.get("uv",[]).is_empty():
			error="Unsupported additive model vertex or UV animation layout";return false
		var material:=ShaderMaterial.new();material.shader=ShaderSource
		material.set_shader_parameter("diffuse_texture",model.materials[i].get_shader_parameter("diffuse_texture"))
		model.materials[i]=material;model.instances[i].material_override=material
		model.instances[i].top_level=true
	return true

func prepare_surfaces(animation: Dictionary, root: Transform3D, parent_rgba: PackedByteArray, global_tint: Vector4) -> Array:
	error=""
	var surfaces:=[]
	for surface in animation.surfaces:
		var color:=Colors.tint(parent_rgba,global_tint,surface.get("color_byte",-1))
		if color.is_empty():error="Additive model color exceeds source precision";return []
		var pose:=Sampler.multiply(root,surface.pose)
		if not pose.is_finite():error="Additive model surface exceeds source precision";return []
		surfaces.append({"pose":pose,"tint":color.value})
	return surfaces

func apply_surfaces(model: Node3D, surfaces: Array, darken: float) -> void:
	for i in model.instances.size():
		var row: Dictionary=surfaces[i]
		model.instances[i].transform=row.pose
		model.materials[i].shader=reflected if row.pose.basis.determinant()<0 else ShaderSource
		model.materials[i].set_shader_parameter("effect_tint",row.tint)
		model.materials[i].set_shader_parameter("darken_value",darken)
