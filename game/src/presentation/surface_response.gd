extends RefCounted
## Explicit two-light material adapter. It does not select source settings or
## silently replace an unknown shader variant. Opaque material 28 only.
const ShaderSource = preload("res://src/presentation/surface_response.gdshader")
const Lights = preload("res://src/presentation/material_light_state.gd")
const ImportedShader = preload("res://src/presentation/imported_material.gdshader")
var error := ""
var material: ShaderMaterial

func prepare_models(models: Array, surface: Dictionary, environment: Dictionary, reflection: Cubemap, diffuse_bias: Variant, normal_bias: Variant, variant: String) -> Array:
	error=""
	var changes := []
	for model in models:
		for index in model.materials.size():
			var original: ShaderMaterial=model.materials[index]
			if original.shader!=ImportedShader:continue
			var adapter: RefCounted=get_script().new()
			if not adapter.from_imported(original,surface,environment,reflection,diffuse_bias,normal_bias,variant):
				error=adapter.error;return []
			changes.append({"model":model,"index":index,"material":adapter.material})
	if changes.is_empty():error="Assembly has no supported source surface materials"
	return changes

static func commit_models(changes: Array) -> void:
	for row in changes:
		row.model.materials[row.index]=row.material
		row.model.instances[row.index].material_override=row.material

func from_imported(original: ShaderMaterial, surface: Dictionary, environment: Dictionary, reflection: Cubemap, diffuse_bias: Variant, normal_bias: Variant, variant: String) -> bool:
	material=null;error=""
	if original==null or original.shader!=ImportedShader:return fail("Surface response requires an imported opaque material 28")
	if not original.get_shader_parameter("has_diffuse") or not original.get_shader_parameter("has_normal_specular"):return fail("Imported material has no complete diffuse/normal pair")
	if not build(surface,environment,original.get_shader_parameter("diffuse_texture"),original.get_shader_parameter("normal_specular_texture"),reflection,diffuse_bias,normal_bias,variant):return false
	for key in ["uv_offset","uv_scale","uv_angle"]:
		material.set_shader_parameter(key,original.get_shader_parameter(key))
	return true

func build(surface: Dictionary, environment: Dictionary, diffuse: Texture2D, detail: Texture2D, reflection: Cubemap, diffuse_bias: Variant, normal_bias: Variant, variant: String) -> bool:
	error="";material=null
	if variant!="two_light_cube":return fail("Unsupported source material response variant: "+variant)
	if diffuse==null or detail==null or reflection==null:return fail("Source material response needs diffuse, normal/specular and cube textures")
	for value in [diffuse_bias,normal_bias]:
		if not (value is float or value is int) or not is_finite(float(value)) or absf(value)>16:return fail("Invalid source texture sampling bias")
	var lights := Lights.new()
	if not lights.build(surface,environment):return fail(lights.error)
	if lights.state.lights.size()!=2:return fail("Two-light material requires both explicit source lights")
	var staged := ShaderMaterial.new();staged.shader=ShaderSource
	staged.set_shader_parameter("diffuse_texture",diffuse)
	staged.set_shader_parameter("normal_specular_texture",detail)
	staged.set_shader_parameter("reflection_texture",reflection)
	staged.set_shader_parameter("diffuse_bias",float(diffuse_bias))
	staged.set_shader_parameter("normal_bias",float(normal_bias))
	staged.set_shader_parameter("specular_power",lights.state.specular_power)
	staged.set_shader_parameter("rim_color",lights.state.rim_color)
	staged.set_shader_parameter("reflection_enabled",true)
	for field in ["ambient","diffuse","specular","direction_to_light"]:
		var values := PackedVector3Array()
		for row in lights.state.lights:values.append(row[field])
		staged.set_shader_parameter("light_directions" if field=="direction_to_light" else field+"_colors",values)
	material=staged
	return true

func fail(message: String) -> bool:
	error=message;material=null
	return false
