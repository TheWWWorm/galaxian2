extends SceneTree
## A detached declaration fixture can validate the native owner against an
## unchanged identified content pack. It never installs a gameplay capability.
const Owner=preload("res://src/simulation/player_engine_particles.gd")
const Definitions=preload("res://src/content/engine_particle_owner_definitions.gd")
const Sprites=preload("res://src/presentation/opening_damage_geometry.gd")
const Ship=preload("res://src/presentation/ship_geometry.gd")
const Library=preload("res://src/content/library.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Mounts=preload("res://src/content/weapon_mounts.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visuals=preload("res://src/content/visual_library.gd")

class DetachedBindings extends RefCounted:
	var base_content_id: String
	var binding_id: String
	var source_architecture: String
	var engine_particle_owners: Dictionary
	var engine_particles: Dictionary
	var damage_particles: Dictionary

var library:=Library.new()
var catalogues:=Catalogues.new()
var mounts:=Mounts.new()
var bindings:=Bindings.new()
var visuals:=Visuals.new()
var fixture:=DetachedBindings.new()
var source_bytes:=0
var checks:=0
var failures:=0

func _initialize():
	create_timer(40).timeout.connect(func():push_error("Player engine owner checks timed out");quit(1))
	call_deferred("run")

func run():
	var args:=OS.get_cmdline_user_args()
	if args.size() not in [3,4]:check(false,"Expected content, bindings, visuals and optional detached owner declarations")
	elif not library.open(args[0]) or not catalogues.open(library) or not mounts.open(library,catalogues) or not bindings.open(args[1],library.manifest) or not visuals.open(args[2],library.manifest):check(false,library.error+catalogues.error+mounts.error+bindings.error+visuals.error)
	elif load_fixture(args):
		verify_definitions()
		verify_samples_and_clock()
		verify_jump_rollover()
		verify_flags()
		verify_transactional_lifetime()
		await verify_geometry()
	print("Player engine owner: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func load_fixture(args: PackedStringArray) -> bool:
	var metadata: Variant=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	if not metadata is Dictionary:check(false,"Missing source identity metadata");return false
	source_bytes=int(metadata.source_executable_bytes)
	var owner: Variant=bindings.get("engine_particle_owners")
	if args.size()==4:
		var detached: Variant=JSON.parse_string(FileAccess.get_file_as_string(args[3]))
		if not detached is Dictionary or detached.get("scope")!="detached_engine_owner_component_fixture" or detached.get("base_content_id")!=bindings.base_content_id or detached.get("binding_id")!=bindings.binding_id or detached.get("source_executable_sha256")!=metadata.source_executable_sha256:
			check(false,"Detached engine-owner proof belongs to another source or pack");return false
		owner=detached.get("engine_particle_owners")
	var error:=Definitions.validate(owner,source_bytes,bindings.source_architecture,bindings.arrival_staging,bindings.engine_particles)
	if not error.is_empty() or not Definitions.parameters(owner):check(false,"Missing verified normal engine-owner capability: "+error);return false
	fixture.base_content_id=bindings.base_content_id;fixture.binding_id=bindings.binding_id
	fixture.source_architecture=bindings.source_architecture
	fixture.engine_particle_owners=owner.duplicate(true)
	fixture.engine_particles=bindings.engine_particles.duplicate(true)
	fixture.damage_particles=bindings.damage_particles.duplicate(true)
	return true

func configured() -> RefCounted:
	var owner:=Owner.new()
	check(owner.configure(fixture,mounts,0,73),owner.error)
	return owner

func pose(z: float) -> Transform3D:return Transform3D(Basis.IDENTITY,Vector3(0,0,z))

func verify_definitions():
	check(Definitions.available(fixture),"Verified detached source declarations were unavailable")
	var data: Dictionary=fixture.engine_particle_owners.duplicate(true)
	for key in Definitions.VALUES:
		var changed:=data.duplicate(true);changed.erase(key)
		check(not Definitions.parameters(changed),"Owner accepted a missing parameter: "+key)
	for key in data.provenance:
		for field in ["offset","bytes"]:
			var changed:=data.duplicate(true);changed.provenance[key][field]+=1
			check(not Definitions.validate(changed,source_bytes,bindings.source_architecture,bindings.arrival_staging,bindings.engine_particles).is_empty(),"Owner accepted a changed source extent: "+key+" "+field)
	check(Definitions.validate({},source_bytes,"x86_64",bindings.arrival_staging,bindings.engine_particles).is_empty(),"Retained content lost its optional declaration boundary")
	var legacy:=fixture.engine_particle_owners
	fixture.engine_particle_owners={}
	check(Definitions.available_for(fixture,0) and not Definitions.available_for(fixture,10),"Legacy Mac nozzle declaration did not enable Betty alone")
	fixture.engine_particle_owners=legacy
	check(not Definitions.validate(data,source_bytes,"armv7",bindings.arrival_staging,bindings.engine_particles).is_empty(),"Deferred architecture inherited Mac owner gates")

func verify_samples_and_clock():
	var owner:=configured();var initial: Dictionary=owner.snapshot()
	check(initial.engine_enabled and not initial.player_hidden and initial.draw_enabled and initial.manager_ms==0 and initial.elapsed_ms==0,"Fresh exhaust lost its declared flags or clock")
	check(initial.owners.size()==4,"Normal owner registered an unrelated effect manager")
	check(owner.advance(pose(0),0) and owner.snapshot()==initial,"Paused registration consumed its first movement baseline")
	check(owner.advance(pose(0),10) and owner.snapshot().births.values()==[0,0,0,0],"Nozzle registration emitted across an uninitialized baseline")
	var statistics:=Transform3D(Basis(Vector3.BACK,0.3),Vector3(80,0,0))
	check(owner.advance(statistics,40),owner.error)
	var state: Dictionary=owner.snapshot()
	check(state.births.values()==[10,10,10,10] and state.elapsed_ms==50 and state.manager_ms==0,"Nozzle count used a time rate or lost the shared manager interval")
	for index in 4:
		var emitter: Dictionary=state.owners["player_nozzle%d"%index].exhaust
		check(emitter.preset.preset_id==29+index and emitter.preset.material_id==20090 and emitter.preset.size==[125,125,250,250][index],"Owner changed original nozzle preset or scale")
		var mount: Vector3=mounts.snapshot().ships[0].groups[3][index].position
		check(emitter.slots[9].position.distance_to(statistics.origin+statistics.basis*mount)<0.4,"Nozzle did not use the retained statistics basis")
		check(emitter.random==state.owners.player_nozzle0.exhaust.random,"Nozzle registration did not retain independent same-second seeds")
	check(owner.advance(statistics,0) and owner.snapshot()==state,"Pause changed retained exhaust age, RNG, clock or births")
	var staged: RefCounted=owner.fork_for_frame()
	check(staged.presentation_identity()==owner.presentation_identity(),"Staging changed the exhaust flight identity")
	check(staged.set_engine_enabled(false) and staged.advance(statistics,81),staged.error)
	check(owner.snapshot()==state,"Staged engine changes mutated the accepted particle slots")
	for row in staged.snapshot().owners.values():check(row.exhaust.slots.all(func(slot):return slot.appearance.age_ms==-1),"Disabled exhaust stopped ageing")
	owner=configured()
	for entry in [[0,3,3],[8,3,6],[16,3,9],[24,1,0]]:
		check(owner.advance(pose(entry[0]),entry[1]) and owner.snapshot().manager_ms==entry[2],"Shared exhaust interval failed its strict ten-millisecond boundary")

func verify_jump_rollover():
	var owner:=configured()
	check(owner.advance(pose(0),10),owner.error)
	var identity: RefCounted=owner.presentation_identity()
	check(owner.advance(pose(136000),100),owner.error)
	var state: Dictionary=owner.snapshot()
	check(owner.presentation_identity()==identity and state.elapsed_ms==110,"Scripted jump replaced the exhaust owner or clock")
	for index in 4:
		var key: String="player_nozzle%d"%index
		var count: int=int(state.births.get(key,0))
		var emitter: Dictionary=state.owners[key].exhaust
		check(count>16384 and emitter.cursor==count%20 and emitter.slots.all(func(slot):return slot.appearance.age_ms>=0),"Jump lost the final source nozzle ring: "+key)
		check(emitter.random==state.owners.player_nozzle0.exhaust.random,"Same-second nozzle streams diverged during jump")

func verify_flags():
	var owner:=configured();owner.advance(pose(0),1);owner.advance(pose(80),40)
	var before: Dictionary=owner.snapshot()
	check(owner.set_player_hidden(true),owner.error)
	var hidden: Dictionary=owner.snapshot()
	check(hidden.player_hidden and hidden.engine_enabled and not hidden.draw_enabled,"Player hiding changed the requested engine flag")
	for key in hidden.owners:
		check(hidden.owners[key].exhaust==before.owners[key].exhaust and not hidden.owners[key].draw_enabled,"Manager draw hiding reset or disabled a nozzle")
	check(owner.advance(pose(160),40) and owner.snapshot().births.values()==[10,10,10,10],"Hidden manager stopped updating or emitting")
	check(owner.snapshot().owners.player_nozzle0.exhaust.random!=before.owners.player_nozzle0.exhaust.random,"Hidden manager froze its private random stream")
	check(owner.set_player_hidden(false) and owner.snapshot().draw_enabled,"Unhiding did not restore the requested draw flag")
	before=owner.snapshot()
	check(owner.set_engine_enabled(false),owner.error)
	var stopped: Dictionary=owner.snapshot()
	check(not stopped.engine_enabled and not stopped.draw_enabled,"Entry/mining/death disable did not stop drawing and emission")
	for key in stopped.owners:
		var emitter: Dictionary=stopped.owners[key].exhaust
		check(not emitter.enabled and emitter.visible and emitter.slots==before.owners[key].exhaust.slots and emitter.random==before.owners[key].exhaust.random and not emitter.dirty,"Engine stop discarded old sprites or their movement baseline")
	check(owner.advance(pose(168),10) and owner.snapshot().births.values()==[0,0,0,0],"Disabled engine emitted")
	check(owner.snapshot().owners.player_nozzle0.exhaust.slots!=stopped.owners.player_nozzle0.exhaust.slots,"Hidden old sprites failed to age and move")
	before=owner.snapshot()
	check(owner.set_engine_enabled(true),owner.error)
	for key in before.owners:
		var emitter: Dictionary=owner.snapshot().owners[key].exhaust
		check(emitter.slots==before.owners[key].exhaust.slots and emitter.random==before.owners[key].exhaust.random and emitter.remainder_ms==0,"Mining/revive enable reset particles or retained its disabled fraction")
	check(owner.advance(pose(176),10) and owner.snapshot().births.values()==[1,1,1,1],"Reenabled nozzles lost the retained movement baseline")
	owner.set_player_hidden(true);owner.set_engine_enabled(false);owner.set_engine_enabled(true)
	check(owner.snapshot().player_hidden and owner.snapshot().draw_enabled,"A later engine enable was incorrectly combined with an earlier hide")
	owner.set_player_hidden(true)
	check(not owner.snapshot().draw_enabled and owner.snapshot().engine_enabled,"A later hide failed to suppress drawing alone")
	owner.set_engine_enabled(false);owner.set_player_hidden(false)
	check(not owner.snapshot().draw_enabled and not owner.snapshot().engine_enabled,"Unhiding silently reenabled a stopped engine")

func verify_transactional_lifetime():
	var owner:=configured();owner.advance(pose(0),1);owner.advance(pose(80),40)
	var accepted: Dictionary=owner.snapshot();var identity: RefCounted=owner.presentation_identity()
	for value in [-1,1001,0.5,"1"]:
		check(not owner.advance(pose(90),value) and owner.snapshot()==accepted,"Invalid exhaust time changed accepted state")
	for value in [true,1,null]:
		check(not owner.advance(pose(90),10,value) and owner.snapshot()==accepted,"Unsupported boost state changed normal exhaust")
	check(not owner.advance(Transform3D(Basis.from_scale(Vector3(2,1,1)),Vector3.ZERO),10) and owner.snapshot()==accepted,"Nonrigid statistics pose changed accepted exhaust")
	check(not owner.advance(pose(2e10),1000) and owner.snapshot()==accepted,"Out-of-range source birth count partially committed emitters or clocks")
	check(not owner.set_engine_enabled(1) and not owner.set_player_hidden(null) and owner.snapshot()==accepted,"Invalid manager flags changed accepted state")
	check(not owner.configure(fixture,mounts,1,73) and owner.snapshot()==accepted and owner.presentation_identity()==identity,"Unsupported hull replaced accepted exhaust")
	check(not owner.configure(fixture,mounts,0,0.5) and owner.snapshot()==accepted,"Invalid seed replaced accepted exhaust")
	var declarations: Dictionary=fixture.engine_particle_owners
	fixture.engine_particle_owners={}
	check(owner.configure(fixture,mounts,0,73) and owner.snapshot().owners.size()==4,"Legacy Betty nozzle pack lost its verified native manager")
	fixture.engine_particle_owners=declarations
	owner=configured();accepted=owner.snapshot()
	var nozzle_data: Dictionary=fixture.engine_particles
	fixture.engine_particles={}
	check(not owner.configure(fixture,mounts,0,73) and owner.snapshot()==accepted,"Missing nozzle declaration enabled a legacy exhaust manager")
	fixture.engine_particles=nozzle_data
	var content_id: String=fixture.base_content_id;fixture.base_content_id="0".repeat(64)
	check(not owner.configure(fixture,mounts,0,73) and owner.snapshot()==accepted,"Another content identity replaced accepted exhaust")
	fixture.base_content_id=content_id
	var former: WeakRef=weakref(owner._emitters[0])
	check(owner.configure(fixture,mounts,0,73) and owner.presentation_identity()!=identity and owner.snapshot().elapsed_ms==0 and former.get_ref()==null,"Repeated configuration retained old manager resources or clocks")
	check(owner.advance(pose(700000),1) and owner.snapshot().births.values()==[0,0,0,0],"A new flight emitted across its preceding path")
	former=weakref(owner._emitters[0]);owner.clear()
	check(owner.snapshot().is_empty() and owner.presentation_identity()==null and former.get_ref()==null,"Clear retained nozzle resources or flight identity")
	check(not owner.advance(pose(0),1) and not owner.set_engine_enabled(true),"Cleared manager accepted live operations")

func world(owner: RefCounted) -> Dictionary:
	var state: Dictionary=owner.snapshot()
	return {"base_content_id":state.base_content_id,"binding_id":state.binding_id,"elapsed_ms":state.elapsed_ms,"engine_particles":state}

func verify_geometry():
	var viewport:=SubViewport.new();viewport.size=Vector2i(960,540);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var camera:=Camera3D.new();viewport.add_child(camera)
	camera.look_at_from_position(Vector3(0,320,-1400),Vector3(0,30,0));camera.near=1;camera.far=10000;camera.current=true
	var light:=DirectionalLight3D.new();light.rotation=Vector3(-0.3,PI,0);viewport.add_child(light)
	var ship:=Ship.new();viewport.add_child(ship)
	check(ship.build(0,library,visuals,bindings,"high",null,true) and ship.apply_selection({"visible":true,"level":0}),ship.error)
	var owner:=configured();owner.advance(pose(-40),10);owner.advance(pose(0),20)
	var sprites:=Sprites.new();viewport.add_child(sprites)
	check(sprites.build(owner,library,visuals,bindings),sprites.error)
	check(sprites.items.size()==4,"Shared renderer lost the four independent nozzle presets")
	for item in sprites.items:check(item.node.get_meta("source_material_id")==20090 and item.node.get_meta("source_texture_id")==24202,"Shared exhaust renderer replaced the original additive atlas")
	var camera_pose: Transform3D=camera.global_transform
	var prepared:=sprites.prepare_world(owner,world(owner),camera_pose)
	check(prepared.get("counts")==[5,5,5,5],"Shared renderer changed retained exhaust samples: "+sprites.error)
	if prepared.is_empty():viewport.free();return
	sprites.commit_world(prepared)
	var visible: Image
	if DisplayServer.get_name()!="headless":visible=await rendered(viewport)
	var accepted: Dictionary=owner.snapshot()
	check(sprites.prepare_world(owner,world(owner),camera_pose).get("counts")==[5,5,5,5] and owner.snapshot()==accepted,"Presentation advanced exhaust simulation or RNG")
	var wrong:=world(owner);wrong.elapsed_ms+=1
	check(sprites.prepare_world(owner,wrong,camera_pose).is_empty(),"Renderer accepted a stale exhaust clock")
	wrong=world(owner);wrong.binding_id="0".repeat(64)
	check(sprites.prepare_world(owner,wrong,camera_pose).is_empty(),"Renderer accepted foreign exhaust resources")
	owner.set_player_hidden(true)
	prepared=sprites.prepare_world(owner,world(owner),camera_pose)
	check(prepared.get("counts")==[0,0,0,0],"Manager draw suppression left visible exhaust")
	sprites.commit_world(prepared)
	var hidden: Image
	if DisplayServer.get_name()!="headless":hidden=await rendered(viewport)
	owner.set_player_hidden(false)
	prepared=sprites.prepare_world(owner,world(owner),camera_pose);sprites.commit_world(prepared)
	check(prepared.get("counts")==[5,5,5,5],"Unhiding lost retained particles")
	if DisplayServer.get_name()!="headless":
		check((await rendered(viewport)).get_data()==visible.get_data(),"Hiding and restoring changed retained exhaust pixels")
		var changed:=0
		for y in visible.get_height():
			for x in visible.get_width():
				var a:=visible.get_pixel(x,y);var b:=hidden.get_pixel(x,y)
				if a.r-b.r+a.g-b.g+a.b-b.b>0.08:changed+=1
		check(changed>100,"Original exhaust added too few visible pixels: "+str(changed))
		print("Original engine-owner additive pixels: ",changed)
		var captures:=OS.get_environment("GOF2_CAPTURE_DIR")
		if not captures.is_empty():
			DirAccess.make_dir_recursive_absolute(captures)
			check(visible.save_png(captures.path_join("player-engine-owner-visible.png"))==OK and hidden.save_png(captures.path_join("player-engine-owner-hidden.png"))==OK,"Engine-owner capture failed")
	owner.configure(fixture,mounts,0,73)
	check(sprites.prepare_world(owner,world(owner),camera_pose).is_empty(),"Old geometry accepted a freshly configured exhaust flight")
	check(sprites.build(owner,library,visuals,bindings) and sprites.items.size()==4,"Repeated build retained old exhaust surfaces")
	var material: WeakRef=weakref(sprites.items[0].node.material_override)
	sprites.clear()
	check(sprites.items.is_empty() and sprites.get_child_count()==0 and material.get_ref()==null,"Clearing shared geometry retained exhaust materials or surfaces")
	viewport.free()

func rendered(viewport: SubViewport) -> Image:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;push_error(message)
