extends SceneTree
const OpeningFixture=preload("res://tests/opening_handoff_fixture.gd")
## Source-bound control components with explicitly synthetic player positions.
## No mission dialogue, cargo drops, rewards or full encounter playback claimed.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Definitions=preload("res://src/content/full_hold_control_definitions.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Combat=preload("res://src/simulation/opening_combat_group.gd")
const Guns=preload("res://src/simulation/opening_npc_weapons.gd")
const NpcControl=preload("res://src/simulation/opening_npc_control.gd")
const Player=preload("res://src/simulation/opening_player_state.gd")
const Loadout=preload("res://src/simulation/opening_loadout.gd")
const Cache=preload("res://src/simulation/flight_player_cache.gd")
const ORIGIN=Vector3(0,0,-200000)
var failures:=0
var checks:=0
func _initialize():call_deferred("run")
func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:verify(args)
	print("Full-hold control: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func verify(args: PackedStringArray):
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest) or not cat.open(lib):check(false,lib.error+bindings.error+cat.error);return
	check(bindings.source_architecture=="x86_64","This check requires Mac content")
	var flight:=Construction.new();var control:=NpcControl.new()
	if bindings.full_hold_control.is_empty():
		check(not control.configure_full_hold(bindings,cat,flight,.5) and control.snapshot().is_empty(),"Legacy pack invented second-trip control")
		return
	if not flight.prepare(bindings,cat,packet_fixture(bindings,cat,3),4096,1789100000):check(false,flight.error);return
	var saved:=flight.snapshot();var random: Dictionary=saved.random_state
	var data: Dictionary=bindings.full_hold_control
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	check(Definitions.validate(data,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.full_hold_pirate,bindings.opening_actors).is_empty(),"Second-trip control proof rejected")
	for key in Definitions.VALUES:
		var bad:=data.duplicate(true);bad[key]=null
		check(not Definitions.parameters(bad),"Changed control declaration accepted: "+key)
	for key in Definitions.SPANS:
		var bad:=data.duplicate(true);bad.provenance[key].offset+=1
		check(not Definitions.validate(bad,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.full_hold_pirate,bindings.opening_actors).is_empty(),"Changed control extent accepted: "+key)
	for axis in 3:
		for sign_value in [-1,1]:
			for distance in [24999,25000,49999,50000]:
				var separation:=Vector3.ZERO;separation[axis]=distance*sign_value
				var pair:=owners(bindings,cat,flight)
				if pair.is_empty():return
				var player:=target(bindings,ORIGIN+separation)
				var before: Dictionary=pair.control.snapshot();var body: Dictionary=pair.combat.snapshot();var gun: Dictionary=pair.guns.snapshot()
				pair.guns.advance(16);gun=pair.guns.snapshot()
				var next: Dictionary=pair.control.evaluate(pair.combat,pair.guns,16,player,random)
				if next.is_empty():check(false,pair.control.error);return
				var event: Dictionary=next.actors[0];var actor: Dictionary=next.combat.snapshot().actors[0]
				var expected:="proximity" if distance<25000 else ("target" if distance<50000 else "")
				check(event.decision.activation==expected and actor.active==(distance<50000) and actor.actor_mode==(1 if distance<50000 else 5),"Activation boundary changed on axis%d at%d"%[axis,distance*sign_value])
				check(event.movement.is_empty()==(distance>=25000) and event.decision.holding==(distance>=25000),"Activation dispatched motion in the wrong source pass")
				check(actor.node_draw_requested==(distance<50000) and actor.model_draw_enabled and actor.targeting_blocked,"Activation mixed model submission, body visibility or targeting flags")
				check(pair.control.snapshot()==before and pair.combat.snapshot()==body and pair.guns.snapshot()==gun and next.random_state==random,"Candidate control modified inputs or invented random draws")
	verify_alternate(bindings,cat,flight,random)
	verify_live(bindings,cat,flight,random)
	verify_clocks(bindings,cat,flight)
	verify_failure(bindings,cat,flight,random)
	verify_reader(args[1],lib,header)
	check(flight.snapshot()==saved,"NPC control changed retained world, route, cargo or earned progress")

func owners(bindings: RefCounted, cat: RefCounted, flight: RefCounted) -> Dictionary:
	var control:=NpcControl.new();var combat:=Combat.new();var guns:=Guns.new()
	if not control.configure_full_hold(bindings,cat,flight,.5) or not combat.configure_full_hold(bindings,cat,flight,.5) or not guns.configure_full_hold(bindings,cat,flight):check(false,control.error+combat.error+guns.error);return {}
	return {"control":control,"combat":combat,"guns":guns}

func target(bindings: RefCounted, position: Vector3) -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"ship_id":0,
		"pose":Transform3D(Basis.IDENTITY,position),"active":true,"hull":95,"targeting_blocked":false,"special_flight":false,"alternate_position":null}

func verify_alternate(bindings: RefCounted, cat: RefCounted, flight: RefCounted, random: Dictionary):
	for blocked in [false,true]:
		for distance in [24999,25000,49999,50000]:
			var pair:=owners(bindings,cat,flight);var player:=target(bindings,ORIGIN+Vector3(0,0,100000))
			player.alternate_position=ORIGIN+Vector3(distance,0,0);player.targeting_blocked=blocked
			var next: Dictionary=pair.control.evaluate(pair.combat,pair.guns,16,player,random)
			if next.is_empty():check(false,pair.control.error);return
			var desired:="proximity" if distance<25000 else ("target" if distance<50000 and not blocked else "")
			check(next.actors[0].decision.activation==desired,"Alternate body did not feed both source activation tests")
			if distance<25000:
				check(next.actors[0].decision.direction==Vector3.RIGHT and not next.actors[0].decision.fire_requested,"Prefix lost alternate steering vector or used it as ordinary weapon range")
	# The prefix has no player activity/hull/suppression gate; mode5's later test
	# checks suppression, but its retained player pointer is also independent of health.
	for distance in [20000,30000]:
		var pair:=owners(bindings,cat,flight);var player:=target(bindings,ORIGIN+Vector3(0,0,distance))
		player.active=false;player.hull=0
		var next: Dictionary=pair.control.evaluate(pair.combat,pair.guns,16,player,random)
		check(not next.is_empty() and next.combat.snapshot().actors[0].active and not next.actors[0].decision.fire_requested,"Dormant source target pointer gained an invented living-player activation gate")
	var pair:=owners(bindings,cat,flight);var player:=target(bindings,ORIGIN+Vector3(0,0,20000));player.alternate_position=ORIGIN+Vector3(0,0,50000)
	var next: Dictionary=pair.control.evaluate(pair.combat,pair.guns,0,player,random)
	check(not next.is_empty() and not next.combat.snapshot().actors[0].active,"Nearby normal body bypassed an out-of-range alternate body")

func verify_live(bindings: RefCounted, cat: RefCounted, flight: RefCounted, random: Dictionary):
	var pair:=owners(bindings,cat,flight);var player:=target(bindings,ORIGIN+Vector3(0,0,30000))
	var route: Dictionary=pair.control.snapshot().actors[0].guidance.route
	var fired:=[]
	for step in 65:
		pair.guns.advance(16)
		var next: Dictionary=pair.control.evaluate(pair.combat,pair.guns,16,player,random)
		if next.is_empty():check(false,pair.control.error);return
		var event: Dictionary=next.actors[0]
		if step==0:check(event.decision.activation=="target" and event.movement.is_empty() and event.firing.is_empty(),"Mode5 activation moved or fired immediately")
		else:check(not event.decision.holding and event.decision.activation.is_empty() and event.decision.target_kind=="player","Active pirate returned to holding or lost player pursuit")
		if not event.firing.is_empty() and event.firing.actors[0].outcome.fired:fired.append({"step":step,"shot":event.firing.actors[0].outcome.projectile})
		check(next.random_state==random,"Short unboosted trajectory consumed random draws")
		pair={"control":next.controller,"combat":next.combat,"guns":next.weapons}
	check(pair.combat.snapshot().actors[0].position==ORIGIN+Vector3(0,0,2048) and fired.size()==2 and fired[0].step==1 and fired[1].step==39,"Independent straight-flight/cadence fixture changed")
	check(fired[0].shot.position==ORIGIN and fired[1].shot.position==ORIGIN+Vector3(0,0,1216),"Pirate fired from its new pose rather than preceding motion pose")
	check(pair.control.snapshot().actors[0].guidance.route==route,"Player pursuit consumed generated patrol waypoints")
	# After range refresh clears selection, the living pirate uses its retained route.
	player.pose.origin=ORIGIN+Vector3(0,0,200000)
	var next: Dictionary=pair.control.evaluate(pair.combat,pair.guns,5001,player,random)
	check(not next.is_empty() and next.actors[0].decision.target_kind=="route" and not next.actors[0].decision.fire_requested,"Active pirate fabricated pursuit after an out-of-range refresh")

func verify_clocks(bindings: RefCounted, cat: RefCounted, flight: RefCounted):
	var pair:=owners(bindings,cat,flight);var player:=target(bindings,ORIGIN+Vector3(0,0,100000))
	var seed:={"state":25214903913} # Independent seed4 LCG fixtures, recorded privately.
	var route: Dictionary=pair.control.snapshot().actors[0].guidance.route
	var first: Dictionary=pair.control.evaluate(pair.combat,pair.guns,5000,player,seed)
	if first.is_empty():check(false,pair.control.error);return
	check(first.random_state==seed and not first.combat.snapshot().actors[0].active,"Holding selection refreshed at exact timer equality")
	var second: Dictionary=first.controller.evaluate(first.combat,first.weapons,1,player,first.random_state)
	if second.is_empty():check(false,first.controller.error);return
	var guide: Dictionary=second.controller.snapshot().actors[0].guidance
	check(second.random_state.state==255458207629771 and guide.selection_elapsed_ms==0 and guide.boost_elapsed_ms==5001 and not guide.boost_active,"Holding consumed incorrect selection/boost draws")
	check(guide.target_selected and not guide.fire_desired and guide.route==route,"Dormant target refresh consumed patrol waypoints or invented firing desire")
	player.pose.origin=ORIGIN+Vector3(0,0,20000)
	var third: Dictionary=second.controller.evaluate(second.combat,second.weapons,0,player,second.random_state)
	if third.is_empty():check(false,second.controller.error);return
	guide=third.controller.snapshot().actors[0].guidance
	check(third.random_state.state==228198391288061 and guide.boost_active and guide.boost_duration_ms==6558 and guide.speed==2.0999999046325684,"Prefix activation failed to consume the deferred boost in its own dispatch pass")
	check(third.actors[0].decision.activation=="proximity" and third.combat.snapshot().actors[0].position==ORIGIN,"Zero-time activation invented displacement or waited an extra pass")

func verify_failure(bindings: RefCounted, cat: RefCounted, flight: RefCounted, random: Dictionary):
	var pair:=owners(bindings,cat,flight);var player:=target(bindings,ORIGIN+Vector3(0,0,20000))
	var before: Dictionary=pair.control.snapshot();var body: Dictionary=pair.combat.snapshot();var gun: Dictionary=pair.guns.snapshot()
	for field in ["alternate_position","pose","targeting_blocked","ship_id","binding_id"]:
		var bad:=player.duplicate(true);bad.erase(field)
		check(pair.control.evaluate(pair.combat,pair.guns,16,bad,random).is_empty() and pair.control.snapshot()==before and pair.combat.snapshot()==body and pair.guns.snapshot()==gun,"Incomplete player advanced pirate control: "+field)
	for position in [Vector3(INF,0,0),Vector3(1.0e30,0,0),false]:
		var bad:=player.duplicate(true);bad.alternate_position=position
		# The finite large vector is a supported out-of-range source position.
		var result: Dictionary=pair.control.evaluate(pair.combat,pair.guns,16,bad,random)
		check(not result.is_empty() if position is Vector3 and position.is_finite() else result.is_empty(),"Alternate position validation changed")
	var next: Dictionary=pair.control.evaluate(pair.combat,pair.guns,16,player,random)
	if next.is_empty():check(false,pair.control.error);return
	next.combat.normal_hit(0,50)
	var dead: Dictionary=next.combat.snapshot();var current: Dictionary=next.controller.snapshot()
	check(next.controller.evaluate(next.combat,next.weapons,16,player,random).is_empty() and next.combat.snapshot()==dead and next.controller.snapshot()==current,"Unprepared cargo-bearing death was completed or awarded credit")
	var opening:=Combat.new();opening.configure(bindings,cat,.5)
	check(pair.control.evaluate(opening,pair.guns,16,player,random).is_empty(),"Second-trip controller accepted Opening actors")
	check(not pair.control.configure_full_hold(bindings,cat,RefCounted.new(),.5) and pair.control.snapshot().is_empty(),"Unowned construction retained NPC control")

func packet_fixture(bindings: RefCounted, cat: RefCounted, kills: int) -> Dictionary:
	var loadout:=Loadout.new();var player:=Player.new()
	if not loadout.configure_station(bindings,cat,bindings.base_content_id) or not player.configure_departure(bindings,cat,4):check(false,loadout.error+player.error);return {}
	var seed:=loadout.snapshot();var current:=player.snapshot();var rules: Dictionary=bindings.full_hold_departure
	var reset:=Cache.departure_cache(bindings.opening_actors.player_initialization.flight_cache,rules,seed,current.max_hull,current.capacities,true)
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":4,
		"source_state":2,"world_type":3,"audio_selector":1,"confirmation_required":true,"confirmation_text_id":386,
		"loadout":seed,"reset_cache":reset,"player_cache":player.cache_snapshot(),"player":current,
		"progress":OpeningFixture.progress(bindings,4,kills),
		"mission":{"kind":154,"station_id":78,"reward":0,"bonus":0,"source_parameter":25},"cargo_used":0,"source_ship_configuration":8}

func verify_reader(pack: String, lib: RefCounted, header: Dictionary):
	var body: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(pack.path_join("registrations.json")))
	var directory:=OS.get_cache_dir().path_join("gof2-full-hold-pirate-%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	for scenario in ["missing","wrong_type","changed","extent","flight_absent","flight_tuning_absent","empty"]:
		var changed:=body.duplicate(true);var metadata:=header.duplicate(true)
		match scenario:
			"missing":changed.erase("full_hold_control")
			"wrong_type":changed.full_hold_control=false
			"changed":changed.full_hold_control.player_target_count=2
			"extent":changed.full_hold_control.provenance.npc_update.offset+=1
			"flight_absent":changed.full_hold_pirate={}
			"flight_tuning_absent":changed.opening_actors.npc_initialization.flight={}
			"empty":
				changed.full_hold_control={};changed.full_hold_destruction={};changed.full_hold_appearance={}
		var serialized:=JSON.stringify(changed,"",true,true)
		metadata.records_sha256=serialized.sha256_text();metadata.records_bytes=serialized.to_utf8_buffer().size()
		metadata.binding_id=("gof2-bindings-v1\n%s\n%s\n%s\n%s\n"%[metadata.base_content_id,metadata.source_executable_sha256,metadata.architecture,metadata.records_sha256]).sha256_text()
		var file:=FileAccess.open(directory.path_join("registrations.json"),FileAccess.WRITE);file.store_string(serialized);file.close()
		file=FileAccess.open(directory.path_join("bindings.json"),FileAccess.WRITE);file.store_string(JSON.stringify(metadata));file.close()
		var reader:=Bindings.new();check(reader.open(pack,lib.manifest),reader.error)
		var accepted:=reader.open(directory,lib.manifest)
		if scenario=="empty":check(accepted and reader.full_hold_control.is_empty() and not reader.full_hold_flight.is_empty(),"Optional pirate capability cannot be absent")
		else:check(not accepted and reader.binding_id.is_empty() and reader.source_architecture.is_empty() and reader.full_hold_control.is_empty(),"Failed reopen exposed stale pirate or architecture state")
	DirAccess.remove_absolute(directory.path_join("registrations.json"));DirAccess.remove_absolute(directory.path_join("bindings.json"));DirAccess.remove_absolute(directory)

func check(ok: bool, message: String):
	checks+=1
	if not ok:failures+=1;push_error(message)
