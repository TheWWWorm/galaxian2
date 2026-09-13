extends SceneTree
const Drill=preload("res://src/simulation/mining_drill.gd")
const Extraction=preload("res://src/simulation/mining_extraction.gd")
const Cargo=preload("res://src/simulation/flight_cargo.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Station=preload("res://src/simulation/station_entry.gd")
const Arrival=preload("res://src/simulation/arrival_world_frame.gd")
const Handoff=preload("res://src/simulation/opening_handoff.gd")
const Fixture=preload("res://tests/opening_handoff_fixture.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Effects=preload("res://src/content/scenery_effect_resources.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Frame=preload("res://src/simulation/first_flight_frame.gd")
const Scene=preload("res://src/presentation/first_flight_scene.gd")
var checks:=0
var failures:=0
var bindings: RefCounted
var cat: RefCounted
var construction: RefCounted
var scenery: RefCounted
var cargo: RefCounted
var extraction:=Extraction.new()
var index:=-1
func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size() in [2,4],"Expected Mac content, bindings and optional visuals/capture directory")
	if args.size() in [2,4]:await verify(args)
	print("Mining extraction: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: Array):
	var lib:=Library.new();bindings=Bindings.new();cat=Catalogues.new();var bodies:=Bodies.new();var effects:=Effects.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib) or not lib.select_language("gb") or not bodies.configure(lib,bindings) or not effects.configure(lib,bindings):check(false,lib.error+bindings.error+cat.error+bodies.error+effects.error);return
	var player:=Player.new();var handoff:=Handoff.new();check(player.configure(bindings,cat),player.error)
	var packet:=handoff.prepare(bindings,cat,Fixture.completed(bindings,player,3))
	var arrival:=Arrival.new()
	if not arrival.configure(bindings,cat,lib,packet,[1,1,1],1789100000):check(false,arrival.error);return
	for i in 500:
		arrival=arrival.evaluate(100)
		if arrival==null:check(false,"Could not prepare rescue fixture");return
		if not arrival.snapshot().boundary.is_empty():break
	var station:=Station.new();check(station.configure(bindings,cat,lib,arrival.prepare_station()),station.error)
	for i in 19:station.acknowledge()
	var departure:=station.prepare_departure(bindings,cat)
	construction=Construction.new()
	if not construction.prepare(bindings,cat,departure,4096,1789100000,true,bodies,effects):check(false,construction.error);return
	scenery=construction.scenery_owner();cargo=Cargo.new()
	check(cargo.snapshot().is_empty() and not cargo.add_entries([]),"Unprepared cargo accepted entries")
	if not cargo.configure_departure(bindings,cat,construction):check(false,cargo.error);return
	var field: Dictionary=scenery.snapshot();var initial_hold: Dictionary=cargo.snapshot()
	print("First departure cargo capacity: ",initial_hold.capacity)
	check(initial_hold.used==0 and initial_hold.entries.is_empty() and initial_hold.capacity==cat.tables.ships[0].stats.cargo_capacity and initial_hold.free_space==initial_hold.capacity,"First departure hold differs from its source ship")
	check(initial_hold.capacity>1 and initial_hold.capacity<63,"Extraction fixture does not exercise capacity clamping")
	for row in field.objects:
		if row.source_size_value==7:index=int(row.index);break
	if index<0:check(false,"Reference field lacks a core asteroid");return
	var ore:=int(field.objects[index].item_id)
	for entries in [[{"item_id":ore,"quantity":-1}],[{"item_id":ore,"quantity":0}],[{"item_id":ore,"quantity":1.5}],[{"item_id":99999,"quantity":1}],[{"item_id":ore,"quantity":initial_hold.capacity+1}],[{"item_id":ore,"quantity":1},{"item_id":ore,"quantity":initial_hold.capacity}]]:
		check(not cargo.add_entries(entries) and cargo.snapshot()==initial_hold,"Invalid cargo partially changed the hold")
	check(not cargo.configure_departure(bindings,cat,Construction.new()) and cargo.snapshot()==initial_hold,"Failed preparation replaced valid cargo")
	var spare: RefCounted=cargo.fork_for_frame();check(spare.add_entries([{"item_id":ore,"quantity":1},{"item_id":ore,"quantity":2}]),spare.error)
	check(spare.snapshot().entries==[{"item_id":ore,"quantity":3}] and cargo.snapshot()==initial_hold,"Cargo did not merge quantities or changed its parent")
	var exported: Dictionary=spare.snapshot();exported.entries[0].quantity=99
	check(spare.snapshot().used==3 and spare.snapshot().entries[0].quantity==3,"Cargo snapshot aliases the owned hold")
	var drill:=make_drill();var live: Dictionary=drill.snapshot()
	check(extraction.evaluate(bindings,cat,drill,scenery,cargo,false).is_empty() and drill.snapshot()==live and scenery.snapshot()==field and cargo.snapshot()==initial_hold,"Running drill was extracted")
	for i in 70:steer(drill,100)
	check(drill.stop(),drill.error)
	check(drill.snapshot().ore_tons==3,"Partial drilling fixture changed")
	var partial:=extract(drill,cargo,false)
	if partial.is_empty():return
	check(partial.cargo.snapshot().entries==[{"item_id":ore,"quantity":3}],"Partial ore did not reach the actual hold")
	var hard:=extract(drill,cargo,true)
	check(not hard.is_empty() and hard.cargo.snapshot().entries==[{"item_id":ore,"quantity":1}],"Hard partial ore was not halved before insertion")
	check_retirement(partial,drill)
	check(scenery.snapshot()==field and cargo.snapshot()==initial_hold,"Prospective extraction mutated its accepted input owners")
	var committed_field: Dictionary=partial.scenery.snapshot();var committed_hold: Dictionary=partial.cargo.snapshot()
	check(extraction.evaluate(bindings,cat,drill,partial.scenery,partial.cargo,false).is_empty() and partial.scenery.snapshot()==committed_field and partial.cargo.snapshot()==committed_hold,"Extraction replay duplicated cargo or retirement")
	check(extraction.evaluate(bindings,cat,drill.fork(),partial.scenery,partial.cargo,false).is_empty(),"Cloned drill bypassed asteroid retirement")
	check(extraction.evaluate(bindings,cat,drill,scenery,partial.cargo,false).is_empty() and extraction.evaluate(bindings,cat,drill,partial.scenery,cargo,false).is_empty(),"Mixed old/new field and cargo owners duplicated or lost extraction")
	var reactivated: RefCounted=partial.scenery._bodies.fork_for_frame()
	check(not reactivated.set_permissions(index,true,true) and not reactivated.collision_context(index).eligible,"Mined asteroid was reactivated or collidable")
	check(not Drill.new().configure_for_scenery(bindings,cat,[90,81],partial.scenery,index,Vector2(640,360)),"Retired asteroid started another drill")
	var standalone:=Drill.new();check(standalone.configure(bindings,cat,[90,81],field.bodies,index,Vector2(640,360)) and standalone.stop(),standalone.error)
	check(extraction.evaluate(bindings,cat,standalone,scenery,cargo,false).is_empty(),"Geometry-only drill fabricated live ownership")
	var replacement:=Construction.new();check(replacement.prepare(bindings,cat,departure,4096,1789100000,true,bodies,effects),replacement.error)
	var foreign_hold:=Cargo.new();check(foreign_hold.configure_departure(bindings,cat,replacement),foreign_hold.error)
	check(extraction.evaluate(bindings,cat,drill,replacement.scenery_owner(),foreign_hold,false).is_empty(),"Old drill was accepted by an identically seeded replacement field")
	check(extraction.evaluate(bindings,cat,drill,scenery,foreign_hold,false).is_empty(),"Foreign hold accepted an extraction")
	var damaged: RefCounted=scenery.fork_for_frame();damaged._bodies=scenery._bodies.fork_for_frame();damaged._bodies.normal_hit(index,100000)
	var dead: Dictionary=damaged.snapshot()
	check(extraction.evaluate(bindings,cat,drill,damaged,cargo,false).is_empty() and damaged.snapshot()==dead and cargo.snapshot()==initial_hold,"Rejected retirement leaked its staged cargo into the accepted hold")
	var stopped:=make_drill();check(stopped.stop(),stopped.error)
	var zero:=extract(stopped,cargo,false)
	check(not zero.is_empty() and zero.cargo.snapshot()==initial_hold,"Immediate stop fabricated ore")
	if not zero.is_empty():check_retirement(zero,stopped)
	var failed:=make_drill();failed.set_command(Vector2(1,0))
	for i in 100:
		var state: Dictionary=failed.snapshot()
		if state.phase!="drilling":break
		failed.advance(100,field.random_state if state.random_state.is_empty() else state.random_state)
	check(failed.snapshot().phase=="failed","Failure fixture never exhausted outside time")
	var lost:=extract(failed,cargo,false)
	check(not lost.is_empty() and lost.cargo.snapshot()==initial_hold,"Failed drilling retained ore")
	if not lost.is_empty():check_retirement(lost,failed)
	var complete:=make_drill()
	for i in 427:steer(complete,100)
	check(complete.snapshot().phase=="extracted" and complete.snapshot().core,"Core fixture never completed drilling")
	var core:=ore+11
	var filled:=extract(complete,cargo,false)
	if filled.is_empty():return
	check(filled.cargo.snapshot().used==initial_hold.capacity and filled.cargo.snapshot().free_space==0 and filled.cargo.snapshot().entries==[{"item_id":core,"quantity":1},{"item_id":ore,"quantity":initial_hold.capacity-1}],"Core-first extraction did not clamp to the actual hold")
	check_retirement(filled,complete)
	spare=cargo.fork_for_frame();spare.add_entries([{"item_id":ore,"quantity":initial_hold.capacity-1}])
	var last:=extract(complete,spare,false)
	check(not last.is_empty() and last.extraction.ore_tons==0 and last.extraction.core_item_id==core and last.cargo.snapshot().entries==[{"item_id":ore,"quantity":initial_hold.capacity-1},{"item_id":core,"quantity":1}],"Last cargo space was not reserved for the core")
	spare.add_entries([{"item_id":ore,"quantity":1}]);var full_hold: Dictionary=spare.snapshot()
	var full:=extract(complete,spare,false)
	check(not full.is_empty() and full.cargo.snapshot()==full_hold and full.extraction.entries.is_empty(),"Full hold accepted ore or a core")
	if not full.is_empty():check_retirement(full,complete)
	check(construction.snapshot().departure==departure and station.prepare_departure(bindings,cat)==departure,"Extraction changed campaign state, mission or station progress")
	spare.clear();check(spare.snapshot().is_empty() and cargo.snapshot()==initial_hold,"Clearing a fork changed original cargo")
	# A second asteroid updates the same accepted hold and count independently.
	var second:=Drill.new();var other: int=(index+1)%field.objects.size()
	check(second.configure_for_scenery(bindings,cat,[90,81],partial.scenery,other,Vector2(640,360)) and second.stop(),second.error)
	var second_result:=extraction.evaluate(bindings,cat,second,partial.scenery,partial.cargo,false)
	check(not second_result.is_empty() and second_result.scenery.snapshot().mined_count==2 and second_result.scenery.snapshot().remaining_count==field.remaining_count-2 and second_result.cargo.snapshot()==committed_hold,"Sequential asteroid retirement lost accounting or existing cargo")
	var alternate:=Drill.new();alternate.configure_for_scenery(bindings,cat,[90,81],scenery,other,Vector2.ZERO);alternate.stop()
	var alternate_result:=extraction.evaluate(bindings,cat,alternate,scenery,cargo,false)
	check(not alternate_result.is_empty() and extraction.evaluate(bindings,cat,drill,alternate_result.scenery,partial.cargo,false).is_empty(),"Different branches with equal mining counts were combined")
	var absent:=Construction.new();check(absent.prepare(bindings,cat,departure,4096,1789100000,true,bodies),absent.error)
	var absent_world: RefCounted=absent.scenery_owner();var absent_hold:=Cargo.new();absent_hold.configure_departure(bindings,cat,absent)
	var absent_drill:=Drill.new();absent_drill.configure_for_scenery(bindings,cat,[90,81],absent_world,index,Vector2.ZERO);absent_drill.stop()
	check(extraction.evaluate(bindings,cat,absent_drill,absent_world,absent_hold,false).is_empty() and absent_world.snapshot().bodies.objects[index].active and absent_hold.snapshot().used==0,"Missing lifecycle support partially committed extraction")
	if args.size()==4:await render(lib,args[2],args[3],partial)

func render(lib: RefCounted, visual_path: String, directory: String, result: Dictionary):
	var visuals:=Visuals.new()
	if not visuals.open(visual_path,lib.manifest):check(false,visuals.error);return
	var flight:=Frame.new()
	if not flight.configure(bindings,cat,lib,construction,"E",0.5):check(false,flight.error);return
	var retired: RefCounted=flight.fork_for_frame();retired._scenery=result.scenery;retired._cargo=result.cargo
	check(retired.snapshot().cargo_used==3 and retired.snapshot().cargo.entries==result.cargo.snapshot().entries and flight.snapshot().cargo_used==0,"Flight snapshot did not consume the prospective cargo owner")
	var canvas:=SubViewport.new();canvas.size=Vector2i(960,720);canvas.own_world_3d=true;canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
	var scene:=Scene.new();canvas.add_child(scene)
	if not scene.build(lib,bindings,visuals,cat,flight):check(false,scene.error);canvas.free();return
	var field: Dictionary=scenery.snapshot();var asteroid: Dictionary=field.bodies.objects[index]
	var target: Vector3=asteroid.position
	# This close inspection camera is test-only. It does not stand in for the
	# unfinished player's approach or change either flight's physical position.
	var eye:=target+Vector3(0,0,asteroid.model_radius*asteroid.scale*4.0)
	for label in ["before","mined","restored"]:
		var current: RefCounted=retired if label=="mined" else flight
		check(scene.present(current),scene.error)
		check(scene.scenery.objects[index].visible==(label!="mined"),"First-flight scene ignored mined asteroid visibility")
		var visible:=0
		for object in scene.scenery.objects:
			if object.visible:visible+=1
		check(visible==field.objects.size()-(1 if label=="mined" else 0),"Mining hid unrelated asteroids")
		scene.camera.position=eye;scene.camera.look_at(target);scene.camera.near=1.0
		for i in 3:await process_frame
		var capture:=canvas.get_texture().get_image()
		check(capture.get_size()==canvas.size and capture.save_png(directory.path_join(label+".png"))==OK,"Could not save mining retirement capture")
	check(scene.present(retired),scene.error)
	var invalid: Dictionary=retired.snapshot().scenery.bodies.duplicate(true);invalid.objects.back().active="invalid"
	check(not scene.scenery.apply_activity(invalid) and not scene.scenery.objects[index].visible,"Rejected activity update changed accepted visibility")
	check(scene.scenery.apply_detail(retired.snapshot().scenery.detail) and not scene.scenery.objects[index].visible,"LOD refresh revealed a mined asteroid")
	var after: RefCounted=retired.evaluate(100)
	check(after!=null and after.snapshot().cargo_used==3 and after.snapshot().scenery.mined_count==1 and after.snapshot().mission==flight.snapshot().mission and after.snapshot().progress==flight.snapshot().progress,"Later flight frame lost cargo or invented mission completion")
	canvas.free()

func make_drill() -> RefCounted:
	var drill:=Drill.new();check(drill.configure_for_scenery(bindings,cat,[90,81],scenery,index,Vector2(640,360)),drill.error)
	return drill
func steer(drill: RefCounted, dt: int):
	var state: Dictionary=drill.snapshot()
	if state.phase!="drilling":return
	var desired: Vector2=(state.center-state.point)*20.0/float(dt)-state.drift
	var command:=Vector2.ZERO
	for axis in 2:command[axis]=signf(desired[axis])*sqrt(minf(1.0,absf(desired[axis])/3.0))
	if not drill.set_command(command) or not drill.advance(dt,scenery.snapshot().random_state if state.random_state.is_empty() else state.random_state):check(false,drill.error)
func extract(drill: RefCounted, hold: RefCounted, hard: bool) -> Dictionary:
	var result:=extraction.evaluate(bindings,cat,drill,scenery,hold,hard)
	check(not result.is_empty(),extraction.error)
	return result
func check_retirement(result: Dictionary, drill: RefCounted):
	var original: Dictionary=scenery.snapshot();var retired: Dictionary=result.scenery.snapshot()
	var body: Dictionary=retired.bodies.objects[index]
	check(body.mined and not body.active and not body.damage_allowed and not body.collision_enabled and not body.destruction_pending,"Mined body entered combat destruction or retained permissions")
	check(retired.remaining_count==original.remaining_count-1 and retired.mined_count==1 and retired.destroyed_count==original.destroyed_count,"Mining accounting was omitted or counted as combat destruction")
	check(retired.destruction[index].lifecycle.actor_state==4 and not retired.destruction[index].lifecycle.drop_allowed and retired.destruction[index].lifecycle.cargo.is_empty() and not retired.destruction[index].effect.active,"Mined asteroid created a combat drop or explosion")
	check(retired.random_state==original.random_state and result.scenery.take_events().is_empty() and not result.scenery.has_pending_destruction(),"Retirement consumed RNG, emitted a combat event or left pending destruction")
	var next: RefCounted=result.scenery.fork_for_frame()
	var stream: Dictionary=drill.snapshot().random_state
	if stream.is_empty():stream=original.random_state
	for i in 3:check(next.update(100,Vector3.ZERO,1.0,null,stream),next.error)
	var later: Dictionary=next.snapshot()
	check(later.objects[index].basis==retired.objects[index].basis and later.random_state==stream and later.remaining_count==retired.remaining_count and later.mined_count==1 and later.destroyed_count==retired.destroyed_count and next.take_events().is_empty(),"Later scenery update spun mined geometry, redrew RNG, duplicated accounting or emitted a drop")
	check(not later.destruction[index].lifecycle.update_enabled and result.scenery.snapshot()==retired,"Later frame failed to retire updates or mutated its parent")
func check(value: bool,message: String):
	checks+=1
	if not value:failures+=1;push_error(message)
