extends Node3D
## Original EMP bodies and retained burst wrappers share one accepted frame.
## Removing the last ammunition slot never removes a live projectile or effect.
const Ownership=preload("res://src/simulation/secondary_weapons.gd")
const Models=preload("res://src/presentation/model_resources.gd")
const Burst=preload("res://src/presentation/emp_detonation_geometry.gd")
const Vectors=preload("res://src/simulation/source_vectors.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
var error:=""
var bodies: Array[Node3D]=[]
var detonations: Array[Node3D]=[]
var _identity: RefCounted
var _content:={}
var _launchers:=[]
var _generation: RefCounted
var _revision:=0

func build(owner: RefCounted,library: RefCounted,visuals: RefCounted,bindings: RefCounted) -> bool:
	clear()
	if not owner is Ownership or owner.presentation_identity()==null or not Ownership.Definitions.available(bindings):return fail("EMP geometry requires its configured launcher")
	var state: Dictionary=owner.snapshot();var paths:=[];var launchers:=[]
	for key in ["base_content_id","binding_id"]:
		if state.loadout.get(key)!=bindings.get(key):return fail("EMP geometry belongs to another content identity")
	for gun in state.guns:
		var weapon: Dictionary=gun.bomb.weapon
		var id: int=weapon.model_id;var path: String=bindings.resolve(id,"mesh")
		if id!=14684 or not path.ends_with("/misc/bomb_emp_a.aem") or weapon.kind!=6:return fail("EMP geometry lost the original bomb model mapping")
		paths.append(path);launchers.append({"slot_index":gun.slot_index,"item_id":gun.equipment.item_id,"model_id":id,"resource":path})
	if launchers.is_empty():return fail("EMP geometry has no installed launcher")
	var resources:=Models.new()
	# Reject unknown animation rather than applying the model viewer's preview
	# convention. The supported original projectile body has static tracks.
	if not resources.prepare(paths,library,visuals,bindings,"high",true,true):return fail(resources.error)
	for launcher in launchers:
		var body: Node3D=resources.instantiate(launcher.resource)
		if body==null:resources.clear();return fail("Original EMP body could not be instantiated")
		add_child(body);body.hide();body.set_meta("source_resource_id",launcher.model_id);bodies.append(body)
	resources.clear()
	if owner.has_detonations():
		for launcher in launchers:
			var burst:=Burst.new();add_child(burst);detonations.append(burst)
			if not burst.build(owner.detonation_owner(launcher.slot_index),library,visuals,bindings):return fail(burst.error)
	_identity=owner.presentation_identity();_launchers=launchers
	_content={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_generation=RefCounted.new()
	return true

func prepare_world(owner: RefCounted,camera: Variant=null) -> Dictionary:
	error=""
	if _identity==null or not owner is Ownership or owner.presentation_identity()!=_identity:return failed("EMP geometry follows one retained launcher generation")
	var state: Dictionary=owner.snapshot()
	for key in _content:
		if state.loadout.get(key)!=_content[key]:return failed("EMP presentation changed content identity")
	if state.guns.size()!=_launchers.size():return failed("EMP presentation changed launcher count")
	if owner.has_detonations()!=(not detonations.is_empty()):return failed("EMP presentation lost its prepared burst wrappers")
	if not detonations.is_empty() and not camera is Transform3D:return failed("EMP bursts require the accepted flight camera")
	var poses:=[]
	for index in state.guns.size():
		var gun: Dictionary=state.guns[index];var launcher: Dictionary=_launchers[index]
		if gun.slot_index!=launcher.slot_index or gun.equipment.item_id!=launcher.item_id or gun.bomb.weapon.model_id!=launcher.model_id:return failed("EMP presentation changed the source launcher order")
		var shot: Dictionary=gun.bomb.shot
		if shot.is_empty() or shot.get("phase")=="detonated":poses.append({"visible":false,"pose":Transform3D.IDENTITY});continue
		if shot.get("phase")!="flying" or not Numbers.integer(shot.get("id"),1,2147483647) or not shot.get("position") is Vector3 or not shot.position.is_finite() or not shot.get("velocity") is Vector3 or not shot.velocity.is_finite():return failed("EMP presentation lost a finite live projectile")
		# Shared ordinary projectile convention: forward velocity and world-up.
		# Keep the source's degenerate vertical basis rather than inventing roll.
		var forward:=Vectors.normalized(shot.velocity)
		if forward==Vector3.ZERO:return failed("EMP presentation has no launch direction")
		var right:=Vectors.normalized(Vectors.cross(Vector3.UP,forward))
		var up:=Vectors.normalized(Vectors.cross(forward,right))
		var pose:=Transform3D(Basis(right,up,forward),shot.position)
		if not pose.is_finite():return failed("EMP presentation exceeded finite world coordinates")
		poses.append({"visible":true,"pose":pose})
	var frame:={"identity":_identity,"generation":_generation,"revision":_revision+1,"bodies":poses}
	if not detonations.is_empty():
		var effects:=[]
		for index in detonations.size():
			var effect: Dictionary=detonations[index].prepare_effect(owner.detonation_owner(_launchers[index].slot_index),camera,PackedByteArray([255,255,255,255]),Vector4.ONE,1.0)
			if effect.is_empty():return failed(detonations[index].error)
			effects.append(effect)
		frame.detonations=effects
	return frame

func commit_world(frame: Dictionary) -> void:
	error=""
	# Retired bodies and rebuilt launchers must not consume an older prepared
	# view. Owner identity alone also survives rebuilding this geometry.
	if _generation==null or frame.get("identity")!=_identity or frame.get("generation")!=_generation or frame.get("revision")!=_revision+1:
		error="EMP geometry cannot commit a stale prepared frame";return
	_revision+=1
	for index in bodies.size():
		bodies[index].transform=frame.bodies[index].pose
		bodies[index].visible=frame.bodies[index].visible
	for index in detonations.size():detonations[index].commit_effect(frame.detonations[index])

func clear() -> void:
	for child in get_children():child.free()
	bodies.clear();detonations.clear();_identity=null;_content={};_launchers=[];error=""
	_generation=null;_revision=0

func fail(message: String) -> bool:clear();error=message;return false
func failed(message: String) -> Dictionary:error=message;return {}
