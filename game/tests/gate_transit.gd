extends "res://tests/gate_environment.gd"
## Isolated gate contact/acknowledgement/cinematic vectors using original assets.
## These diagnostic poses do not claim an earned journey or mutate a career.
const GateAnimation=preload("res://src/simulation/gate_animation.gd")
const Transit=preload("res://src/simulation/gate_transit.gd")
const TransitDefinitions=preload("res://src/content/gate_transit_definitions.gd")
const Navigation=preload("res://src/simulation/system_navigation.gd")
const Contracts=preload("res://src/simulation/contract_navigation.gd")

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size() in [2,3]:verify_transit(args)
	else:check(false,"Expected original content and binding paths")
	print("Gate transit: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_transit(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	var clock:=GateAnimation.new();var transit:=Transit.new();var navigation:=Navigation.new()
	if not TransitDefinitions.available(bindings):
		check(not clock.configure(bindings,cat,library,95) and clock.snapshot().is_empty(),"Older pack inferred gate animation")
		check(not transit.configure(bindings,clock,navigation) and transit.snapshot().is_empty(),"Older pack inferred gate transit")
		return
	if not clock.configure(bindings,cat,library,95) or not navigation.configure(bindings,cat,Contracts.initial_availability(bindings,cat,false)) or not transit.configure(bindings,clock,navigation):check(false,clock.error+navigation.error+transit.error);return
	var initial:=clock.snapshot();var outgoing: Dictionary=initial.layout.objects[0];var models: Array=initial.objects[0].models
	check(models.map(func(row):return row.start_ms)==[50,50,50,50],"Terran gate lost the first positive source key")
	check(models.map(func(row):return row.end_ms)==[2500,2500,2550,5000],"Terran gate duration differs from original animation")
	check(not clock.completed() and not clock.accelerating(),"Unused gate completed or accelerated")
	check(not clock.activate(2) and clock.snapshot()==initial,"Incoming gate became interactive")
	check(not clock.advance(-1) and not clock.advance(751 if not bindings.fast_forward.is_empty() else 151) and clock.snapshot()==initial,"Invalid clock frame changed gates")
	check(clock.advance(100,true) and clock.snapshot()==initial,"Pause advanced original gate layers")
	var origin: Vector3=outgoing.pose.origin
	var center:=Vector3(int(origin.x),int(origin.y),int(origin.z));var bound: float=outgoing.collision_radius
	check(transit.contains(center),"Outgoing center is not in its source contact volume")
	for axis in 3:
		for sign_value in [-1,1]:
			var point:=center;point[axis]+=bound*sign_value
			check(not transit.contains(point),"Gate face was treated as inside")
			point[axis]-=sign_value
			check(transit.contains(point),"Strict gate interior was rejected")
	check(not transit.contains(Vector3(NAN,0,0)),"Nonfinite contact was accepted")
	check(not transit.set_course(98),"Local travel was sent through an outgoing gate")
	check(transit.set_course(70),transit.error)
	var before:=transit.snapshot();var pose:=Transform3D(Basis.IDENTITY,center)
	var ordinary:={"kind":-1,"completed":true}
	check(not transit._begin_departure() and transit.snapshot()==before,"Departure bypassed contact and acknowledgement")
	check(transit.observe_contact(Transform3D.IDENTITY,2.0,true,true,ordinary) and transit.snapshot()==before,"Distant flight entered gate confirmation")
	check(transit.observe_contact(pose,2.0,true,true,{"kind":156,"completed":false}) and transit.snapshot()==before,"Pending unsupported encounter bypassed mission restrictions")
	check(not transit.observe_contact(pose,2.0,true,true,{"kind":-1}) and transit.snapshot()==before,"Absent mission status changed gate state")
	check(transit.observe_contact(pose,2.0,true,true,ordinary) and transit.snapshot().coasting and transit.snapshot().phase=="flight","First gate contact did not start coasting")
	check(transit.observe_contact(pose,2.0,true,true,ordinary) and transit.snapshot().phase=="confirmation","Coasting gate did not offer the retained destination")
	check(transit.confirmation()=={"text_ids":[563.0,410.0],"separators":[": ","\n"],"destination_station_id":70},"Gate confirmation text or destination changed")
	before=transit.snapshot()
	check(transit.advance(100) and transit.snapshot()==before,"Acknowledged modal was advanced by time")
	check(not transit.choose_confirmation(2) and transit.snapshot()==before,"Unmapped dialog result was accepted")
	check(transit.choose_confirmation(1) and transit.snapshot().phase=="map","Second confirmation choice did not select the map")
	check(transit.close_map(false),transit.error)
	var cancelled:=transit.snapshot()
	check(cancelled.phase=="flight" and not cancelled.coasting and cancelled.player_pose.origin==origin+Vector3(0,0,-8000) and cancelled.speed==2.0,"Map cancellation did not resume the source outward pose")
	check(cancelled.player_pose.basis.is_equal_approx(outgoing.pose.basis) and cancelled.course.destination_station_id==70,"Cancellation changed retained course or gate facing")
	check(clock.snapshot()==initial,"Transit mutated its source animation owner")
	var unused:=GateAnimation.new()
	check(unused.configure(bindings,cat,library,98),unused.error)
	check(not transit.configure(bindings,unused,navigation) and transit.snapshot()==cancelled,"Missing outgoing gate replaced the current transit")
	# A caller reconfiguring its route owner cannot mutate retained availability.
	var unavailable: Array=Contracts.initial_availability(bindings,cat,false);unavailable[14]=false
	check(navigation.configure(bindings,cat,unavailable) and transit.set_course(70),"Caller changed the detached gate route")
	var approach_speed:=23.0 if bindings.mido_travel.has("gate_arrival") else 2.0
	check(transit.observe_contact(pose,approach_speed,true,true,ordinary),transit.error)
	check(transit.observe_contact(pose,approach_speed,true,true,ordinary),transit.error)
	check(transit.choose_confirmation(0),transit.error)
	var accepted:=transit.snapshot()
	check(accepted.phase=="departing" and accepted.player_pose.origin==origin+Vector3(0,0,-10000) and accepted.player_pose.basis==Basis.IDENTITY,"Accepted jump lost the original ship placement")
	check(accepted.camera_position==origin+Vector3(-2000,300,-6000),"Jump camera initial position changed")
	if bindings.mido_travel.has("gate_arrival"):
		check(accepted.speed==2.0 and accepted.departure_permissions=={"damage_allowed":false,"collision_enabled":false,"boost_enabled":false},"Gate entry retained approach speed or combat permissions")
		check(accepted.reset_primary_fire_intervals,"Confirmation did not reset primary weapon intervals")
	check(transit.arrival_request().is_empty(),"Acknowledgement committed travel before animation")
	before=transit.snapshot();check(transit.advance(100,true) and transit.snapshot()==before,"Paused cinematic moved the player")
	advance_time(transit,1333)
	check(not transit.animation().object_state(1).active,"Gate activated before its camera plane was crossed")
	check(transit.advance(1) and transit.animation().object_state(1).active,"Gate did not activate after its camera plane")
	check(transit.animation().object_state(1).models[3].time_ms==50,"New jump animation skipped its first key")
	advance_time(transit,950)
	check(not transit.animation().accelerating() and transit.snapshot().speed==2.0,"Exactly1000ms crossed the strict acceleration threshold")
	check(transit.advance(1) and transit.animation().accelerating() and transit.snapshot().speed==90.0,"Gate did not accelerate after1000ms")
	var camera: Vector3=transit.snapshot().camera_position
	var saved:=transit.snapshot();var fork: RefCounted=transit.fork_for_frame()
	advance_time(fork,3999)
	check(fork.snapshot().phase=="departing" and fork.arrival_request().is_empty(),"Exactly the final animation key committed arrival")
	check(fork.snapshot().camera_position==camera,"Fast jump kept moving its cinematic camera")
	check(fork.advance(1) and fork.snapshot().phase=="ready",fork.error)
	check(fork.arrival_request()=={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"from_station_id":95,"destination_station_id":70},"Finished animation lost the actual selected station")
	check(fork.snapshot().elapsed_ms==6285,"Gate sequence replaced original camera/key timing with a fixed delay")
	check(transit.snapshot()==saved,"Detached future frame changed accepted cinematic")
	var complete: Dictionary=fork.snapshot();check(fork.advance(150) and fork.snapshot()==complete,"Completed arrival request advanced again")
	check(not fork.choose_confirmation(0) and fork.snapshot()==complete,"Repeated acceptance restarted travel")
	var unselected:=Transit.new()
	check(unselected.configure(bindings,clock,transit._navigation),unselected.error)
	check(unselected.observe_contact(pose,2.0,true,true,ordinary) and unselected.observe_contact(pose,2.0,true,true,ordinary),unselected.error)
	check(unselected.snapshot().phase=="map" and unselected.confirmation().is_empty(),"Gate without a selected destination skipped its map")
	before=unselected.snapshot()
	check(not unselected.close_map(true) and unselected.snapshot()==before,"Empty map selection started a jump")
	check(unselected.set_course(70) and unselected.close_map(true) and unselected.snapshot().phase=="departing","Accepted gate map did not start departure")
	if bindings.mido_travel.has("gate_arrival"):check(not unselected.snapshot().reset_primary_fire_intervals and unselected.snapshot().speed==2.0,"Accepted map used confirmation-only weapon reset or retained approach speed")
	verify_original_clocks(bindings,cat,library)
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	for key in TransitDefinitions.SPANS:
		var changed: Dictionary=bindings.mido_travel.duplicate(true);changed.provenance.erase(key)
		check(not Travel.validate(changed,int(header.source_executable_bytes),"x86_64",bindings.arrival_staging,bindings.station_entry,bindings.combat_training).is_empty(),"Missing transit proof was accepted: "+key)
	var changed: Dictionary=bindings.mido_travel.duplicate(true)
	var alternate_source: bool=int(changed.conversations[0].events[0].text_id)==int(Travel.MAC_VALUES.conversations[0].events[0].text_id)
	var other: Dictionary=TransitDefinitions.SPANS if alternate_source else TransitDefinitions.MAC_SPANS
	changed.provenance.gate_transit_contact.offset=int(bindings.arrival_staging.provenance.actor.offset)+int(other.gate_transit_contact[0])
	check(not Travel.validate(changed,int(header.source_executable_bytes),"x86_64",bindings.arrival_staging,bindings.station_entry,bindings.combat_training).is_empty(),"Mixed-source gate contact proof was accepted")

func advance_time(transit: RefCounted,milliseconds: int) -> void:
	while milliseconds>0:
		var step:=mini(milliseconds,150)
		if not transit.advance(step):check(false,transit.error);return
		milliseconds-=step

func verify_original_clocks(bindings: RefCounted,cat: RefCounted,library: RefCounted) -> void:
	var seen:={}
	for system in cat.tables.systems:
		var type:=int(system.fields[2]);var station:=int(system.fields[6])
		if type not in [0,1,2,3] or station<0 or seen.has(type):continue
		seen[type]=true;var clock:=GateAnimation.new()
		if not clock.configure(bindings,cat,library,station):check(false,clock.error);continue
		check(clock.activate(1),clock.error)
		var original:=clock.snapshot()
		for step in 34:check(clock.advance(150),clock.error)
		check(clock.completed(),"Faction gate original animation did not finish")
		var after:=clock.snapshot()
		check(after.objects[0].models[2]==original.objects[0].models[2],"Replaced gate child kept advancing")
		check(after.objects[1].models[2]!=original.objects[1].models[2],"Incoming ambient gate stopped with the outgoing jump")
		check(not after.objects[1].active and not after.objects[1].models[3].playing,"Incoming gate played an unrequested jump")
	check(seen.size()==4,"Original gate animation omitted a faction")
