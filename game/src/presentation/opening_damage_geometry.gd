extends Node3D
## Original locally imported sprites, batched in stable slot order. Camera-space
## square construction keeps particles facing the camera without rotating their
## velocity or source local offsets. Preparation never advances the simulation.
const State=preload("res://src/simulation/opening_damage_particles.gd")
const FullHold=preload("res://src/simulation/full_hold_particles.gd")
const Engines=preload("res://src/simulation/player_engine_particles.gd")
const EngineDefinitions=preload("res://src/content/engine_particle_definitions.gd")
const Appearance=preload("res://src/presentation/damage_particle_appearance.gd")
const Materials=preload("res://src/presentation/material_library.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")
var error:=""
var items: Array=[]
var frame:={}
var _descriptor:={}
var _owner_identity: RefCounted

func build(owner: RefCounted,library: RefCounted,visuals: RefCounted,bindings: RefCounted) -> bool:
	clear()
	if not (owner is State or owner is FullHold or owner is Engines) or owner.presentation_identity()==null:return reject("Damage geometry requires its configured flight owner")
	var state: Dictionary=owner.snapshot()
	if library==null or visuals==null or bindings==null or library.manifest.get("content_id")!=state.base_content_id or visuals.base_content_id!=state.base_content_id or bindings.base_content_id!=state.base_content_id or bindings.binding_id!=state.binding_id:return reject("Damage sprite resources belong to another content identity")
	var materials:={}
	for kind in ["trail","smoke","fire","burst","junk_burst","emp17","emp18","exhaust"]:
		var preset: Dictionary
		for key in state.owners:
			if not state.owners[key].has(kind):continue
			var current: Dictionary=state.owners[key][kind].preset
			if not Appearance.Definitions.sprite_preset(current):return reject("Unsupported damage sprite preset")
			if kind=="exhaust":
				if not EngineDefinitions.parameters(bindings.engine_particles) or key!="player_nozzle%d"%(int(current.preset_id)-int(bindings.engine_particles.first_preset)) or int(current.preset_id)<29 or int(current.preset_id)>32 or not state.owners[key].get("draw_enabled") is bool:return reject("Unsupported player nozzle owner")
			elif not preset.is_empty() and current!=preset:return reject("Damage owner sprite preset differs from its manager")
			preset=current
			var descriptor: Dictionary=bindings.resolve_material(int(preset.material_id))
			var render_type:=3 if kind=="exhaust" else (1 if kind=="smoke" else 2)
			if descriptor.is_empty() or not Materials.supports(descriptor) or descriptor.render_type!=render_type or descriptor.parameter_bits.map(func(value):return int(value))!=[0,3240099840,0,0] or descriptor.texture_paths[0].is_empty():return reject("Unsupported damage sprite material")
			var material_id:=int(preset.material_id)
			if not materials.has(material_id):
				var image: Image=visuals.load_image(descriptor.texture_paths[0])
				if image==null:return reject(visuals.error)
				materials[material_id]=Materials.create(int(descriptor.render_type),ImageTexture.create_from_image(image),null,true)
			var instance:=MeshInstance3D.new();instance.name=key+"_"+kind
			instance.material_override=materials[material_id];instance.visible=false
			instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.gi_mode=GeometryInstance3D.GI_MODE_DISABLED
			instance.set_meta("source_material_id",int(preset.material_id))
			instance.set_meta("source_texture_id",int(descriptor.texture_ids[0]))
			add_child(instance)
			items.append({"key":key,"kind":kind,"node":instance,"preset":preset.duplicate(true)})
	_owner_identity=owner.presentation_identity();_descriptor=state
	return true

func prepare_world(owner: RefCounted,world: Dictionary,camera_pose: Variant) -> Dictionary:
	error=""
	if not (owner is State or owner is FullHold or owner is Engines) or _owner_identity==null or owner.presentation_identity()!=_owner_identity:return failed("Damage sprites follow one configured flight")
	var state: Dictionary=owner.snapshot()
	for key in ["base_content_id","binding_id"]:
		if state.get(key)!=_descriptor.get(key) or world.get(key)!=_descriptor.get(key):return failed("Damage sprite frame belongs to another identity")
	var elapsed: Variant=world.get("elapsed_ms")
	if owner is FullHold:
		# First mining has no encounter clock. Its accepted particle snapshot owns
		# the early simulation clock, including accelerated and modal-opening passes.
		elapsed=world.get("damage_particles",{}).get("elapsed_ms") if int(world.get("player_destruction",{}).get("departure_cursor",-1))==2 else world.get("encounter",{}).get("elapsed_ms")
	if world.get("engine_particles" if owner is Engines else "damage_particles")!=state or elapsed!=state.elapsed_ms:return failed("Damage sprite presentation requires its current world clock")
	if not Flight.rigid_pose(camera_pose):return failed("Damage sprite camera must be finite and rigid")
	var prepared:=[];var counts:=[]
	var view: Transform3D=camera_pose.affine_inverse()
	for item in items:
		if not is_instance_valid(item.node) or item.node.get_meta("source_material_id",-1)!=int(item.preset.material_id):return failed("Damage sprite surface identity changed")
		var emitter: Dictionary=state.owners[item.key][item.kind]
		if emitter.preset!=item.preset or emitter.slots.size()!=int(item.preset.capacity):return failed("Damage sprite population changed")
		var draw_enabled: bool=state.owners[item.key].get("draw_enabled",false) if item.kind=="exhaust" else true
		var vertices:=PackedVector3Array();var uvs:=PackedVector2Array();var colors:=PackedFloat32Array();var indices:=PackedInt32Array()
		for index in emitter.slots.size():
			var slot: Dictionary=emitter.slots[index]
			if slot.appearance.slot!=index or not slot.position is Vector3 or not slot.position.is_finite():return failed("Invalid damage sprite slot")
			var appearance:=Appearance.sample_prepared(item.preset,slot.appearance,emitter.get("fade_in_rgb",false))
			if appearance.has("error"):return failed(appearance.error)
			if not appearance.active or not emitter.visible or not draw_enabled:continue
			var quad:=sprite(view*slot.position,appearance)
			if quad.is_empty():return failed("Damage sprite exceeded finite view bounds")
			var offset:=vertices.size()
			vertices.append_array(quad.vertices);uvs.append_array(quad.uvs);colors.append_array(quad.colors)
			indices.append_array(PackedInt32Array([offset,offset+2,offset+1,offset,offset+3,offset+2]))
		var mesh: ArrayMesh
		if not vertices.is_empty():
			var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_TEX_UV]=uvs
			arrays[Mesh.ARRAY_CUSTOM0]=colors;arrays[Mesh.ARRAY_INDEX]=indices
			mesh=ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		prepared.append(mesh);counts.append(vertices.size()>>2)
	return {"meshes":prepared,"counts":counts,"pose":camera_pose,"elapsed_ms":state.elapsed_ms}

static func sprite(center: Vector3,appearance: Dictionary) -> Dictionary:
	if not center.is_finite():return {}
	# The source renderer uses an arithmetic shift of signed 16-bit size, so odd
	# sizes lose one unit and negative odd sizes round toward negative infinity.
	var half:=int(appearance["size"])>>1
	var vertices:=PackedVector3Array()
	for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
		var point:=Vector3(Appearance.single(center.x+corner.x*half),Appearance.single(center.y+corner.y*half),center.z)
		if not point.is_finite():return {}
		vertices.append(point)
	var rect: Vector4=appearance.uv_rect
	# The programmable sprite setter preserves V. Unlike imported mesh UVs,
	# these procedural atlas coordinates do not pass through the mesh row flip.
	var uvs:=PackedVector2Array([Vector2(rect.x,rect.y),Vector2(rect.z,rect.y),Vector2(rect.z,rect.w),Vector2(rect.x,rect.w)])
	var c: Color=appearance.color;var colors:=PackedFloat32Array()
	for index in 4:colors.append_array(PackedFloat32Array([c.r,c.g,c.b,c.a]))
	return {"vertices":vertices,"uvs":uvs,"colors":colors}

func commit_world(prepared: Dictionary) -> void:
	global_transform=prepared.pose
	for index in items.size():
		items[index].node.mesh=prepared.meshes[index]
		items[index].node.visible=prepared.meshes[index]!=null
	frame=prepared

func clear() -> void:
	for child in get_children():child.free()
	items=[];frame={};_descriptor={};_owner_identity=null;error=""

func reject(message: String) -> bool:clear();error=message;return false
func failed(message: String) -> Dictionary:error=message;return {}
