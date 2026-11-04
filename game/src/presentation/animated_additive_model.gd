extends RefCounted
## Shared material and surface adapter for source type-2 animated weapon models.
const ShaderSource=preload("res://src/presentation/effect_additive.gdshader")
const AlphaSource=preload("res://src/presentation/effect_alpha.gdshader")
const Sampler=preload("res://src/presentation/scenery_animation.gd")
const Colors=preload("res://src/presentation/effect_color.gd")
const Tracks=preload("res://src/content/animation_tracks.gd")
var error:=""
var reflected: Shader
var two_sided: Shader

func _init() -> void:
	# Godot automatically reverses culling for mirrored instance transforms.
	# Counter that adjustment while preserving source screen winding.
	reflected=Shader.new();reflected.code=ShaderSource.code.replace("cull_back","cull_front")

## Source material type 3 (expansion beams) draws both faces.
func use_two_sided() -> void:
	two_sided=Shader.new();two_sided.code=ShaderSource.code.replace("cull_back","cull_disabled")

func prepare_model(model: Node3D,alpha:=false) -> bool:
	error=""
	for i in model.surfaces.size():
		var surface: Dictionary=model.surfaces[i]
		if not supported_surface(surface):
			error="Unsupported additive model vertex or UV animation layout";return false
		var material:=ShaderMaterial.new();material.shader=AlphaSource if alpha else ShaderSource
		material.set_shader_parameter("diffuse_texture",model.materials[i].get_shader_parameter("diffuse_texture"))
		material.set_shader_parameter("vertex_colors",not surface.colors.is_empty())
		model.materials[i]=material;model.instances[i].material_override=material
		model.instances[i].top_level=true
	model.set_meta("alpha_blend",alpha)
	return true

static func supported_surface(surface: Dictionary) -> bool:
	return not surface.uvs.is_empty() and not surface.normals.is_empty()

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

## The mesh's own texture animation (offset/scale/angle tracks), sampled at
## the effect's playback time like an ordinary imported model.
func apply_uv(model: Node3D, time_ms: float) -> void:
	for i in mini(model.surfaces.size(),model.materials.size()):
		var uv: Array=model.surfaces[i].get("tracks",{}).get("uv",[])
		if uv.size()!=7:continue
		var offset:=Vector2(Tracks.sample(uv[0],time_ms,PackedFloat32Array([0]))[0],Tracks.sample(uv[1],time_ms,PackedFloat32Array([0]))[0])/100.0
		var scale_uv:=Vector2(Tracks.sample(uv[2],time_ms,PackedFloat32Array([100]))[0],Tracks.sample(uv[3],time_ms,PackedFloat32Array([100]))[0])/100.0
		model.materials[i].set_shader_parameter("uv_offset",offset)
		model.materials[i].set_shader_parameter("uv_scale",scale_uv)
		model.materials[i].set_shader_parameter("uv_angle",deg_to_rad(Tracks.sample(uv[6],time_ms,PackedFloat32Array([0]))[0]/100.0))

func apply_surfaces(model: Node3D, surfaces: Array, darken: float) -> void:
	for i in model.instances.size():
		var row: Dictionary=surfaces[i]
		model.instances[i].transform=row.pose
		model.materials[i].shader=AlphaSource if model.get_meta("alpha_blend",false) else two_sided if two_sided!=null else (reflected if row.pose.basis.determinant()<0 else ShaderSource)
		model.materials[i].set_shader_parameter("effect_tint",row.tint)
		model.materials[i].set_shader_parameter("darken_value",darken)
