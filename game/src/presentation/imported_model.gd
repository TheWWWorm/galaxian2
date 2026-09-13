extends Node3D
## Native mesh renderer. Source-authored scene bindings are a separate layer.
const Tracks = preload("res://src/content/animation_tracks.gd")
const MaterialLibrary = preload("res://src/presentation/material_library.gd")
var surfaces: Array = []
var instances: Array[MeshInstance3D] = []
var materials: Array[ShaderMaterial] = []
var source_bounds := AABB()

func build(model: Dictionary, diffuse: Image = null, normal_specular: Image = null, render_type := 28, texture_cache: Dictionary = {}, source_uv := true) -> void:
	surfaces = model.surfaces
	for image in [diffuse, normal_specular]:
		if image != null and not texture_cache.has(image):
			texture_cache[image] = ImageTexture.create_from_image(image)
	var diffuse_texture: ImageTexture = texture_cache.get(diffuse)
	var normal_texture: ImageTexture = texture_cache.get(normal_specular)
	var first := true
	for surface in surfaces:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = surface.positions
		var indices: PackedInt32Array = surface.indices.duplicate()
		# AEM's outward normals correspond to counter-clockwise source triangles.
		# Godot uses clockwise front faces; preserve normals while reversing winding.
		for i in range(0, indices.size(), 3):
			var swap := indices[i + 1]
			indices[i + 1] = indices[i + 2]
			indices[i + 2] = swap
		arrays[Mesh.ARRAY_INDEX] = indices
		if not surface.uvs.is_empty():
			var uvs: PackedVector2Array=surface.uvs.duplicate()
			# Verified V4/V5 shader-path loading changes V before tangent creation.
			# Keep the raw decoder data intact for inspection and other paths.
			if source_uv and model.get("version",0) in [4,5]:
				for index in uvs.size():uvs[index].y=1.0-uvs[index].y
			arrays[Mesh.ARRAY_TEX_UV] = uvs
		if not surface.normals.is_empty():
			arrays[Mesh.ARRAY_NORMAL] = surface.normals
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var builder := SurfaceTool.new()
		builder.create_from(mesh, 0)
		if surface.normals.is_empty():
			builder.generate_normals()
		if not surface.uvs.is_empty():
			builder.generate_tangents()
		mesh = builder.commit()
		if not surface.colors.is_empty():
			# Preserve source floating-point/HDR colors; Godot's COLOR attribute
			# quantizes to eight bits. Add custom floats after tangent generation.
			var color_values := PackedFloat32Array()
			for color in surface.colors:
				color_values.append_array(PackedFloat32Array([color.r, color.g, color.b, color.a]))
			arrays = mesh.surface_get_arrays(0)
			arrays[Mesh.ARRAY_CUSTOM0] = color_values
			mesh = ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		var material := MaterialLibrary.create(render_type, diffuse_texture,
			normal_texture if not surface.uvs.is_empty() else null, not surface.colors.is_empty())
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = material
		add_child(instance)
		instances.append(instance)
		materials.append(material)
		source_bounds = mesh.get_aabb() if first else source_bounds.merge(mesh.get_aabb())
		first = false
	set_source_time(0.0)

func copy_from(template: Node3D) -> void:
	# Scene instances share immutable geometry/textures. Per-instance shader
	# parameters remain independent when animation time changes.
	surfaces = template.surfaces
	source_bounds = template.source_bounds
	for i in template.instances.size():
		var material: ShaderMaterial = template.materials[i].duplicate(false)
		var instance := MeshInstance3D.new()
		instance.mesh = template.instances[i].mesh
		instance.material_override = material
		add_child(instance)
		instances.append(instance)
		materials.append(material)
	set_source_time(0.0)

func set_source_time(time: float) -> void:
	for i in surfaces.size():
		var surface: Dictionary = surfaces[i]
		var tracks: Dictionary = surface.tracks
		var translation := Tracks.vector(tracks.get("translation", []), time, Vector3.ZERO)
		var rotation_value := Tracks.vector(tracks.get("rotation", []), time, Vector3.ZERO)
		var scale_value := Tracks.vector(tracks.get("scale", []), time, Vector3.ONE)
		# Preview convention: XYZ Euler angles and rotation around the stored pivot.
		# Original runtime rotation composition/interpolation remain to be verified.
		var basis_value := Basis.from_euler(rotation_value, EULER_ORDER_XYZ).scaled(scale_value)
		var pivot: Vector3 = surface.pivot
		instances[i].transform = Transform3D(basis_value, translation + pivot - basis_value * pivot)
		var uv: Array = tracks.get("uv", [])
		if uv.size() == 7:
			var offset := Vector2(Tracks.sample(uv[0], time, PackedFloat32Array([0]))[0],
				Tracks.sample(uv[1], time, PackedFloat32Array([0]))[0]) / 100.0
			var scale_uv := Vector2(Tracks.sample(uv[2], time, PackedFloat32Array([100]))[0],
				Tracks.sample(uv[3], time, PackedFloat32Array([100]))[0]) / 100.0
			var angle := deg_to_rad(Tracks.sample(uv[6], time, PackedFloat32Array([0]))[0] / 100.0)
			materials[i].set_shader_parameter("uv_offset", offset)
			materials[i].set_shader_parameter("uv_scale", scale_uv)
			materials[i].set_shader_parameter("uv_angle", angle)
