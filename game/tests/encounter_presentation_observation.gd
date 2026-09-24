extends SceneTree
## Reuse an earned station save for detached render observations. The adapter
## supplies the prior complete snapshot to the same geometry implementation.
const Encounter=preload("res://src/simulation/full_hold_encounter.gd")
const Geometry=preload("res://src/presentation/full_hold_encounter_geometry.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Archive=preload("res://src/simulation/station_archive.gd")
const SaveFile=preload("res://src/simulation/station_save_file.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Effects=preload("res://src/content/scenery_effect_resources.gd")
const Frame=preload("res://src/simulation/first_flight_frame.gd")
var checks:=0
var failures:=0

class CompleteObservation extends "res://src/simulation/full_hold_encounter.gd":
	var retained: RefCounted
	func snapshot() -> Dictionary:return retained.snapshot()
	func presentation_snapshot() -> Dictionary:return retained.snapshot()
	func npc_destruction_owner(actor_id: int) -> RefCounted:return retained.npc_destruction_owner(actor_id)
	func freighter_assembly(actor_id: int) -> Dictionary:return retained.freighter_assembly(actor_id)
	func freighter_resources() -> RefCounted:return retained.freighter_resources()
	func projectile_visual_owner() -> RefCounted:return retained.projectile_visual_owner()
	func impact_visual_owner() -> RefCounted:return retained.impact_visual_owner()
	func has_secondaries() -> bool:return retained.has_secondaries()
	func secondary_owner() -> RefCounted:return retained.secondary_owner()

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected one original content/binding/visual triple")
	check(Encounter.new().presentation_snapshot().is_empty(),"An unconfigured encounter invented a render observation")
	if args.size()==3:verify(args)
	await process_frame
	print("Encounter presentation observation: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new();var visuals:=Visuals.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not library.select_language("gb") or not cat.open(library) or not visuals.open(args[2],library.manifest):
		check(false,library.error+bindings.error+cat.error+visuals.error);return
	var file:=SaveFile.new();var archive:=Archive.new()
	var document:=file.load_document(OS.get_environment("GOF2_SOURCE_SAVE"),bindings,cat,library)
	if document.is_empty():check(false,file.error);return
	var station:=archive.restore(bindings,cat,library,document)
	if station==null:check(false,archive.error);return
	var original: Dictionary=station.snapshot()
	check(original.campaign_cursor in [18,19,21],"Supply an earned ordinary or rescue departure")
	var construction:=Construction.new();var bodies:=Bodies.new();var effects:=Effects.new()
	if not bodies.configure(library,bindings) or not effects.configure(library,bindings):check(false,bodies.error+effects.error);return
	if not construction.prepare_free(bindings,cat,station,4096,1789100000,true,bodies,effects):check(false,construction.error);return
	var world:=Frame.new()
	if not world.configure(bindings,cat,library,construction,"E",0.5):check(false,world.error);return
	var observed:=Geometry.new();var complete:=Geometry.new();root.add_child(observed);root.add_child(complete)
	var legacy:=CompleteObservation.new();legacy.retained=world.encounter_owner()
	if not observed.build(legacy.retained,library,visuals,bindings) or not complete.build(legacy,library,visuals,bindings):
		check(false,observed.error+complete.error);observed.free();complete.free();return
	for index in 4:
		var owner: RefCounted=world.encounter_owner();legacy.retained=owner
		verify_observation(owner)
		var state: Dictionary=world.snapshot()
		verify_geometry(observed,complete,owner,legacy,state.camera_view.pose,state.ship_detail)
		if failures:break
		var next: RefCounted=world.evaluate(150)
		if next==null:check(false,world.error);break
		world=next
	if not failures:
		legacy.retained=world.encounter_owner()
		var state: Dictionary=world.snapshot()
		verify_rejections(observed,complete,legacy.retained,legacy,state.camera_view.pose,state.ship_detail)
		if OS.get_environment("GOF2_ENCOUNTER_OBSERVATION_BENCHMARK")=="1":measure_observations(legacy.retained)
	check(station.snapshot()==original and archive.capture(station,bindings)==document,"Presentation changed the earned station or career")
	observed.free();complete.free()

func expected_observation(full: Dictionary) -> Dictionary:
	var expected:={}
	for key in ["base_content_id","binding_id","campaign_cursor","elapsed_ms","weapons","projectile_visuals","impact_visuals"]:expected[key]=full[key]
	expected.combat={"actors":full.combat.actors}
	if full.has("primaries"):expected.primaries=full.primaries
	return expected

func verify_observation(owner: RefCounted) -> void:
	var original: Dictionary=owner.snapshot();var view: Dictionary=owner.presentation_snapshot()
	check(view==expected_observation(original),"Ordered render observations differ from the full encounter snapshot")
	var retained: Dictionary=view.duplicate(true)
	view.binding_id="foreign"
	if not view.combat.actors.is_empty():
		view.combat.actors[0].vitals.hull=-1;view.combat.actors[0].pose=Transform3D.IDENTITY
		view.combat.actors.reverse()
	for row in view.weapons.actors:row.projectiles["observation_mutation"]=true
	for row in view.projectile_visuals.models:row.time_ms=-1
	for row in view.impact_visuals.weapons:
		if not row.slots.is_empty():row.slots[0].position=Vector3.INF
	if view.has("primaries"):
		for gun in view.primaries.guns:gun.projectiles["observation_mutation"]=true
	view.clear()
	check(owner.snapshot()==original and owner.presentation_snapshot()==retained,"Mutable render observation aliases retained state")
	var full: Dictionary=owner.snapshot();full.combat.actors.clear();full.controller.clear();full.weapons.clear()
	check(owner.snapshot()==original and owner.presentation_snapshot()==retained,"Full public snapshot aliases the narrower render observation")
	var fork: RefCounted=owner.fork_for_frame()
	check(fork.presentation_snapshot()==retained,"A retained encounter fork changed ordered render observations")

func verify_geometry(observed: Node3D,complete: Node3D,owner: RefCounted,legacy: RefCounted,camera: Transform3D,detail: Dictionary) -> void:
	var original: Dictionary=owner.snapshot()
	var narrow: Dictionary=observed.prepare_world(owner,camera,detail)
	var prior: Dictionary=complete.prepare_world(legacy,camera,detail)
	check(not narrow.is_empty() and not prior.is_empty(),observed.error+complete.error)
	if narrow.is_empty() or prior.is_empty():return
	check(canonical(narrow,reference_labels(observed))==canonical(prior,reference_labels(complete)),"Narrow observations changed the complete prepared geometry frame")
	check(owner.snapshot()==original,"Preparing geometry advanced retained gameplay")
	observed.commit_world(narrow);complete.commit_world(prior)
	for geometry in [observed,complete]:
		if geometry.secondaries!=null:
			check(geometry.secondaries.error.is_empty(),"Valid secondary geometry failed its retained generation guard")
			for effect in geometry.secondaries.detonations:check(effect.error.is_empty(),"Valid EMP effect failed its retained generation guard")
	check(rendered(observed)==rendered(complete),"Narrow observations changed committed model transforms or visibility")
	check(owner.snapshot()==original,"Committing geometry advanced retained gameplay")

func verify_rejections(observed: Node3D,complete: Node3D,owner: RefCounted,legacy: RefCounted,camera: Transform3D,detail: Dictionary) -> void:
	var original: Dictionary=owner.snapshot();var retained:=rendered(observed);var previous:=rendered(complete)
	var invalid:=detail.duplicate(true);invalid.binding_id="foreign"
	check(observed.prepare_world(owner,camera,invalid).is_empty() and complete.prepare_world(legacy,camera,invalid).is_empty(),"Foreign detail manager reached encounter geometry")
	var bad_camera:=camera;bad_camera.origin=Vector3.INF
	check(observed.prepare_world(owner,bad_camera,detail).is_empty() and complete.prepare_world(legacy,bad_camera,detail).is_empty(),"A late invalid effect camera reached encounter geometry")
	var broken: RefCounted=owner.fork_for_frame();broken._combat=owner.combat_owner()
	if not broken._combat._actors.is_empty():
		broken._combat._actors[-1]._state.hull_resource="missing"
		legacy.retained=broken
		check(observed.prepare_world(broken,camera,detail).is_empty() and complete.prepare_world(legacy,camera,detail).is_empty(),"A late changed hull reached encounter geometry")
		legacy.retained=owner
	check(rendered(observed)==retained and rendered(complete)==previous,"Rejected preparation changed committed encounter geometry")
	check(owner.snapshot()==original,"Rejected presentation changed the retained encounter")
	verify_geometry(observed,complete,owner,legacy,camera,detail)

func canonical(value: Variant,references: Dictionary) -> Variant:
	if value is Dictionary:
		var result:={}
		for key in value:result[key]=canonical(value[key],references)
		return result
	if value is Array:
		var result:=[]
		for child in value:result.append(canonical(child,references))
		return result
	if value is Node:
		check(value.get_script()==Geometry.DeathEffect,"Unexpected node in the prepared geometry frame")
		return {"effect_node_script":value.get_script().resource_path}
	if value is RefCounted:
		# Rebuilt geometry has a distinct generation token. Require the exact
		# token retained by that geometry, then compare its corresponding role.
		if references.has(value):return {"retained_reference":references[value]}
		check(value.has_method("snapshot"),"Unexpected opaque owner in the prepared geometry frame")
		return {"sampler_script":value.get_script().resource_path,"state":canonical(value.snapshot(),references)} if value.has_method("snapshot") else {}
	return value

func reference_labels(node: Node,path:="root") -> Dictionary:
	var result:={}
	for property in node.get_property_list():
		if property.name in ["_identity","_generation"] and node.get(property.name) is RefCounted:result[node.get(property.name)]=path+"/"+property.name
	for index in node.get_child_count():result.merge(reference_labels(node.get_child(index),path+"/"+str(index)))
	return result

func rendered(node: Node) -> Array:
	var rows:=[]
	if node is Node3D:rows.append({"class":node.get_class(),"transform":node.transform,"visible":node.visible})
	for child in node.get_children():rows.append_array(rendered(child))
	return rows

func measure_observations(owner: RefCounted) -> void:
	var original: Dictionary=owner.snapshot();var expected:=expected_observation(original)
	for method in ["snapshot","presentation_snapshot"]:
		var samples:=[]
		for batch in 68:
			var start:=Time.get_ticks_usec()
			for index in 16:owner.call(method)
			var elapsed:=Time.get_ticks_usec()-start
			if batch>=4:samples.append(float(elapsed)/16.0)
			check(owner.snapshot()==original and owner.presentation_snapshot()==expected,"Observation timing changed retained state")
		var ordered:=samples.duplicate();ordered.sort()
		print("OBSERVATION_BENCHMARK ",JSON.stringify({"method":method,"actors":original.combat.actors.size(),"campaign_cursor":original.campaign_cursor,
			"base_content_id":original.base_content_id,"binding_id":original.binding_id,"batches":64,"observations_per_batch":16,
			"per_observation_us":{"median":ordered[32],"p95":ordered[60],"min":ordered[0],"max":ordered[-1]},"samples_us":samples}))

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)
