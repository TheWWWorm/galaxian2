extends "res://tests/opening_application.gd"
## Connected opening collision checks on detached frames from one earned session.
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Visuals = preload("res://src/content/visual_library.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const StationExterior = preload("res://src/content/station_exterior_resources.gd")
var checks := 0

func _initialize() -> void:
	create_timer(360).timeout.connect(func():push_error("Opening contact checks timed out");quit(1))
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	check(args.size()>0 and args.size()%3==0,"Expected content/bindings/visuals triples")
	for i in range(0,args.size()-2,3):verify_contacts(args[i],args[i+1],args[i+2])
	print("Player-reported opening contacts: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_contacts(content: String, pack: String, textures: String) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var visuals:=Visuals.new()
	if not library.open(content) or not library.select_language("gb") or not bindings.open(pack,library.manifest) or not visuals.open(textures,library.manifest):
		check(false,library.error+bindings.error+visuals.error);return
	check(not bindings.physical_scenery_contacts.is_empty(),"Opening binding lacks physical scenery contact proof")
	if bindings.physical_scenery_contacts.is_empty():return
	var session:=Session.new();root.add_child(session)
	if not session.configure(library,bindings,visuals,0,0.5,1789100000,true,true,true):
		check(false,session.error);session.free();return
	var catalogues:=Catalogues.new();var station:=StationExterior.new()
	if not catalogues.open(library) or not station.configure_opening_location(library,bindings,catalogues,int(session._scenery.read_snapshot().station_id)):
		check(false,catalogues.error+station.error);session.free();return
	check(station.snapshot().station_id==78 and station.snapshot().collision.boxes.size()==7,"Source station 78 authored volumes are unavailable for the opening exclusion regression")
	check(session.interactive and session.escape_sequence and session.snapshot().world_frame.scenery_collision_supported,"Opening did not connect its physical contact and earned escape owners")
	var intro:=owners(session)
	check(int(intro.timeline.snapshot().camera.shot.phase)<4,"Opening did not start before ordinary flight")
	check_station_absent(intro,"intro")
	probe(intro,false,"intro",-1)
	var release: Dictionary={};var ordinary: Dictionary={};var now:=0
	for tick in 1800:
		var prior:=owners(session)
		var incoming:=int(prior.timeline.snapshot().camera.shot.phase)
		now+=100000
		if not session.step(now):check(false,"Opening release failed: "+session.error);break
		if incoming<4 and int(session.snapshot().camera.shot.phase)==4:
			release=prior;ordinary=owners(session);break
	check(not release.is_empty() and int(release.timeline.snapshot().camera.shot.phase)==3 and release.timeline.snapshot().radio.finished[8],"Opening missed the earned event-8 release input")
	if release.is_empty():session.free();return
	probe(release,false,"event-8 release",4)
	check_station_absent(release,"event-8 release")
	probe(ordinary,true,"ordinary phase 4",4)
	check_station_absent(ordinary,"ordinary phase 4")
	probe_absent_station(ordinary,station)
	complete_encounter_fixture(session)
	if failures:session.free();return
	check(int(session.snapshot().camera.shot.phase)==4 and session.snapshot().world_frame.controller.death_accounting.counter_deltas.player_kills==3,"Controlled encounter did not earn its three kills before escape")
	now=100000
	var entry: Dictionary={};var escape: Dictionary={}
	for tick in 4000:
		if session.status!="running":break
		var prior:=owners(session)
		var incoming:=int(prior.timeline.snapshot().camera.shot.phase)
		now+=100000
		if not session.step(now):check(false,"Opening escape failed: "+session.error);break
		if incoming==4 and int(session.snapshot().camera.shot.phase)>4:
			entry=prior;escape=owners(session);break
	check(not entry.is_empty() and entry.timeline.snapshot().radio.finished[10] and int(escape.timeline.snapshot().camera.shot.phase)==5,"Opening missed the earned event-10 escape input")
	if not entry.is_empty():
		check_station_absent(entry,"event-10 escape entry")
		probe(entry,true,"event-10 escape entry",5)
		check_station_absent(escape,"subsequent escape")
		probe(escape,false,"subsequent escape",-1)
	session.free()

func owners(session: Node3D) -> Dictionary:
	return {"frame":session._world_frame,"timeline":session._timeline,"scenery":session._scenery}

func probe(source: Dictionary, should_hit: bool, label: String, next_phase: int) -> void:
	var retained:={"frame":source.frame.snapshot(),"timeline":source.timeline.snapshot(),"scenery":source.scenery.snapshot()}
	var frame: RefCounted=source.frame.fork_for_frame()
	var timeline: RefCounted=source.timeline.fork_for_frame()
	var scenery: RefCounted=source.scenery.fork_for_frame()
	# DetailTimeline shares its private timeline until update; detach it before
	# this controlled staging relocation so the retained session stays immutable.
	timeline._timeline=timeline._timeline.fork_for_frame()
	var target:=single_asteroid(frame,scenery)
	check(not target.is_empty(),label+": no isolated intact asteroid for the contact branch")
	if target.is_empty():return
	var staging: RefCounted=timeline._timeline._sequence._motion._staging
	var scene: Dictionary=staging.snapshot()
	var moved: Transform3D=scene.player_pose
	moved.origin=target.point
	var motion:={"base_content_id":scene.base_content_id,"binding_id":scene.binding_id,"prior_pose":scene.player_pose,"pose":moved}
	if not staging.adopt_player_motion(motion):check(false,label+": "+staging.error);return
	var before: Dictionary=scenery.snapshot()
	var prior_player: Dictionary=frame.snapshot().player
	var expected: RefCounted=frame._player_state.fork_for_frame()
	if should_hit:check(not expected.normal_hit(20).is_empty(),label+": source player damage could not be applied")
	var result: Dictionary=frame.evaluate(timeline,scenery,0,false,1.0,Vector2.ZERO,false,Vector2i(root.get_visible_rect().size))
	if result.is_empty():check(false,label+": "+frame.error);return
	var after: Dictionary=result.scenery.snapshot()
	var player: Dictionary=result.world_frame.snapshot().player
	var body_before: Dictionary=before.bodies.objects[target.index]
	var body_after: Dictionary=after.bodies.objects[target.index]
	if should_hit:
		check(body_after.vitals.hull==0 and body_after.contact,"%s: physical asteroid hit did not damage and mark its body"%label)
		check(player.vitals==expected.snapshot().vitals,"%s: physical asteroid hit did not apply exactly 20 player damage"%label)
		var destruction: Dictionary=result.world_frame.evaluate(result.timeline,result.scenery,1,false,1.0,Vector2.ZERO,false,Vector2i(root.get_visible_rect().size))
		if destruction.is_empty():check(false,label+": next-tick destruction failed: "+result.world_frame.error)
		else:
			var broken: Dictionary=destruction.scenery.snapshot()
			check(broken.destruction[target.index].lifecycle.actor_state!=0,"%s: physical asteroid destruction did not enter the native explosion lifecycle"%label)
	else:
		check(body_after.vitals==body_before.vitals and body_after.contact==body_before.contact,"%s: collision-disabled asteroid received contact"%label)
		check(player.vitals==prior_player.vitals,"%s: collision-disabled asteroid damaged the player"%label)
	if next_phase>=0:check(int(result.timeline.snapshot().camera.shot.phase)==next_phase,label+": transition changed while checking contact")
	check(source.frame.snapshot()==retained.frame and source.timeline.snapshot()==retained.timeline and source.scenery.snapshot()==retained.scenery,label+": detached contact branch changed its original owners")

func single_asteroid(frame: RefCounted, scenery: RefCounted) -> Dictionary:
	var bodies: Dictionary=scenery.read_snapshot().bodies
	for body in bodies.objects:
		if not body.active or not body.collision_enabled or int(body.vitals.hull)<=0 or int(body.half_extent)<=1:continue
		var point: Vector3=body.position+Vector3(float(body.half_extent)*0.5,0,0)
		var pose:=Transform3D(Basis.IDENTITY,point)
		var planned: Dictionary=frame._physical_contacts.plan(frame._player_state.collision_context(pose),bodies,true)
		if planned.is_empty():continue
		if planned.operations.size()==1 and planned.operations[0].kind=="asteroid" and planned.operations[0].object_index==body.index:
			return {"index":body.index,"point":point}
	return {}

func check_station_absent(source: Dictionary, label: String) -> void:
	var contacts: RefCounted=source.frame._physical_contacts
	check(contacts!=null and contacts._station_shapes.is_empty() and contacts._station_half==0,label+": opening contact metadata includes the source-excluded station")

func probe_absent_station(source: Dictionary, station: RefCounted) -> void:
	var label:="ordinary phase-4 excluded station"
	var retained:={"frame":source.frame.snapshot(),"timeline":source.timeline.snapshot(),"scenery":source.scenery.snapshot()}
	var frame: RefCounted=source.frame.fork_for_frame()
	var timeline: RefCounted=source.timeline.fork_for_frame()
	var scenery: RefCounted=source.scenery.fork_for_frame()
	timeline._timeline=timeline._timeline.fork_for_frame()
	var state: Dictionary=station.snapshot()
	var point:=Vector3.INF
	for shape in state.collision.boxes:
		var candidate: Vector3=state.pose.origin+shape.center
		if station.point_volume(candidate)<0:continue
		var pose:=Transform3D(Basis.IDENTITY,candidate)
		var planned: Dictionary=frame._physical_contacts.plan(frame._player_state.collision_context(pose),scenery.read_snapshot().bodies,true)
		if not planned.is_empty() and planned.operations.is_empty():point=candidate;break
	check(point.is_finite(),label+": no authored station interior is isolated from asteroids")
	if not point.is_finite():return
	var staging: RefCounted=timeline._timeline._sequence._motion._staging
	var scene: Dictionary=staging.snapshot()
	var moved: Transform3D=scene.player_pose
	moved.origin=point
	var motion:={"base_content_id":scene.base_content_id,"binding_id":scene.binding_id,"prior_pose":scene.player_pose,"pose":moved}
	if not staging.adopt_player_motion(motion):check(false,label+": "+staging.error);return
	var before: Dictionary=scenery.snapshot()
	var prior_player: Dictionary=frame.snapshot().player
	var result: Dictionary=frame.evaluate(timeline,scenery,0,false,1.0,Vector2.ZERO,false,Vector2i(root.get_visible_rect().size))
	if result.is_empty():check(false,label+": "+frame.error);return
	check(result.world_frame.snapshot().player_motion.pose.origin==point and result.timeline.snapshot().scene.player_pose.origin==point,label+": absent station projected the player")
	check(result.world_frame.snapshot().player.vitals==prior_player.vitals,label+": absent station damaged the player")
	check(result.scenery.snapshot().bodies==before.bodies,label+": absent station damaged scenery bodies")
	check(source.frame.snapshot()==retained.frame and source.timeline.snapshot()==retained.timeline and source.scenery.snapshot()==retained.scenery,label+": excluded-station probe changed original owners")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
