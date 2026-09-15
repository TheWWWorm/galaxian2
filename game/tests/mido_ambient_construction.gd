extends "res://tests/mido_traffic.gd"
## Construction component with a captured, earned equipment prerequisite.
## Training release, exchange and the already-supported relocation event are
## applied explicitly here. This does not claim a live Kernstal departure.
const Population=preload("res://tests/traffic_population.gd")
const FreighterMotion=preload("res://src/simulation/freighter_motion.gd")

func verify(args: PackedStringArray) -> void:
	super.verify(args)
	if failures:return
	var library:=Library.new();var bindings:=Bindings.new();var catalogues:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not catalogues.open(library):check(false,library.error+bindings.error+catalogues.error);return
	if bindings.ambient_population.is_empty():
		check(not Construction.new().configure_ambient_traffic(bindings,catalogues,null,Population.CONTEXT,0),"Earlier packs invented mixed traffic");return
	var path:=OS.get_environment("GOF2_AMBIENT_VECTORS")
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>1024*1024:check(false,"Supply independent local construction vectors with GOF2_AMBIENT_VECTORS");return
	var vectors: Variant=JSON.parse_string(file.get_as_text());file.close()
	if not vectors is Array or vectors.size()!=7:check(false,"Unsupported construction vectors");return
	var scenario:=Scenario.new();var equipment: RefCounted=scenario.open(OS.get_environment("GOF2_SCENARIO_INPUT"),bindings,catalogues)
	if equipment==null:check(false,scenario.error);return
	check(not Construction.new().configure_ambient_traffic(bindings,catalogues,equipment,Population.CONTEXT,0),"Mixed traffic accepted unreleased tutorial equipment")
	if not equipment.prepare_training_completion(bindings,catalogues) or not equipment.complete_training(equipment.snapshot().cargo) or not equipment.apply_station_exchange(bindings,catalogues,9):check(false,equipment.error);return
	check(not Construction.new().configure_ambient_traffic(bindings,catalogues,equipment,Population.CONTEXT,0),"Mixed traffic accepted the wrong player location")
	var arrival:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":10,
		"from_station_id":78,"station_id":79,"system_id":15,"source_state":2,"world_type":3,"audio_selector":1}
	if not equipment.relocate_local_arrival(bindings,catalogues,arrival):check(false,equipment.error);return
	var retained: Dictionary=equipment.snapshot()
	for vector in vectors:
		var owner:=Construction.new()
		if not owner.configure_ambient_traffic(bindings,catalogues,equipment,Population.CONTEXT,int(vector.seed)):check(false,owner.error);return
		check(owner.generate({"state":-1}).is_empty(),"Invalid incoming stream generated mixed traffic")
		var state:=owner.generate({"state":98765})
		if state.is_empty():check(false,owner.error);return
		check(state.campaign_cursor==11 and state.actors.size()==vector.actors.size(),"Mixed construction lost its context or a source group")
		check(state.random_state.state==int(vector.random_state),"Mixed construction changed the independent final random state for seed "+str(vector.seed))
		for id in state.actors.size():
			var actor: Dictionary=state.actors[id];var expected: Dictionary=vector.actors[id]
			check(actor.actor_id==id and actor.actor_kind==3 and actor.population_group==expected.group and actor.hull_catalogue_id==int(expected.hull),"Construction changed group order, faction or hull")
			check(actor.body_pose.origin==point(expected.position) and actor.body_pose==actor.statistics_pose,"Construction changed the independently calculated actor position")
			var cargo:=[]
			for item in expected.cargo:cargo.append({"item_id":int(item[0]),"quantity":int(item[1])})
			check(actor.cargo==cargo and actor.discarded_cargo.is_empty(),"Construction changed the independently calculated cargo")
			if expected.group=="freighter":
				check(actor.subtype==1 and actor.world_flag and actor.model_assembly_required and actor.assembly.container_count==int(expected.assembly_count) and actor.fragments.is_empty() and actor.route.is_empty(),"Freighter borrowed a small ship's route or breakup geometry")
				check(owner.route(id)==null,"Freighter acquired a generated patrol route")
				verify_freighter_motion(bindings,owner,id,actor)
			else:
				check(not FreighterMotion.new().configure(bindings,owner,id),"A small ship acquired the freighter cruise controller")
				var route: RefCounted=owner.route(id)
				check(route!=null and route.snapshot()==actor.route and actor.route.waypoints==expected.route.map(point),"Small ship lost its independently calculated route")
				check(actor.subtype==0 and actor.fragments.size()>=3 and actor.fragments.size()<=9,"Small ship lost its standard constructor")
				if expected.group=="travel":
					check(actor.flight_mode==4 and actor.travel_flag and actor.discarded_route.loop and not actor.route.loop,"Travel ship lost its original destination replacement")
					var step: Dictionary=route.advance(actor.route.waypoints[0])
					check(step.completed and step.target==null and step.arrived,"Travel route did not finish at its destination")
				else:check(actor.route.loop and not actor.has("discarded_route"),"Patrol replaced its generated route")
		check(owner.generate({"state":0}).is_empty() and owner.snapshot()==state,"Construction regenerated a committed population")
		check(equipment.snapshot()==retained,"Traffic changed player inventory or location")
		verify_population(bindings,catalogues,equipment,owner)

func verify_population(_bindings: RefCounted,_catalogues: RefCounted,_equipment: RefCounted,_construction: RefCounted) -> void:
	pass

func verify_freighter_motion(bindings: RefCounted,construction: RefCounted,id: int,actor: Dictionary) -> void:
	var motion:=FreighterMotion.new()
	check(not motion.update(16,true) and motion.snapshot().is_empty(),"An unconfigured freighter moved")
	if not motion.configure(bindings,construction,id):check(false,motion.error);return
	var before:=motion.snapshot()
	for invalid in [-1,true,1.5,int(bindings.frame_clock.max_frame_milliseconds)+1]:
		check(not motion.update(invalid,true) and motion.snapshot()==before,"Invalid freighter duration advanced the ship")
	check(not motion.update(1,0) and motion.snapshot()==before,"Invalid freighter permission advanced the ship")
	check(motion.update(32,false) and motion.update(0,true) and motion.snapshot()==before,"Paused or held freighter moved")
	var fork:=motion.fork_for_frame()
	for duration in [16,16,17,32,19]:check(fork.update(duration,true),fork.error)
	var moved: Dictionary=fork.snapshot()
	check(moved.body_pose.origin==actor.body_pose.origin+Vector3(0,0,100) and moved.statistics_pose==moved.body_pose,"Freighter changed its source cruise direction, rate or statistics pose")
	check(moved.source_position==before.source_position+Vector3i(0,0,100) and moved.elapsed_motion_ms==100,"Freighter lost its retained integer position or elapsed time")
	check(motion.snapshot()==before and construction.snapshot().actors[id]==actor,"Tentative freighter frame mutated its committed owner or construction")
	moved.body_pose.origin=Vector3.ZERO
	check(fork.snapshot().body_pose.origin!=Vector3.ZERO,"Freighter snapshot aliases retained motion")
	check(not motion.configure(bindings,construction,-1) and motion.snapshot().is_empty(),"An invalid actor retained a previous freighter")

func point(values: Array) -> Vector3:
	return Vector3(float(values[0]),float(values[1]),float(values[2]))
