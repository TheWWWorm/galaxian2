extends SceneTree
## Starts from the captured, acknowledged application return. No campaign state
## or inventory is created by this test. Negative cases only remove eligibility.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Checkpoint=preload("res://tests/fixtures/free_play_station_scenario.gd")
const AliothCheckpoint=preload("res://tests/fixtures/alioth_station_scenario.gd")
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Flight=preload("res://src/content/free_flight_definitions.gd")
const Bodies=preload("res://src/content/scenery_body_resources.gd")
const Effects=preload("res://src/content/scenery_effect_resources.gd")
const Cargo=preload("res://src/simulation/flight_cargo.gd")
const Briefing=preload("res://src/simulation/mining_briefing.gd")
const Encounter=preload("res://src/simulation/full_hold_encounter.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==3:verify(args)
	else:check(false,"Expected explicit content, bindings and visuals")
	print("Earned ordinary departure: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library) or not library.select_language("gb"):check(false,library.error+bindings.error+cat.error);return
	if not Flight.available(bindings):
		check(not Construction.new().prepare_free(bindings,cat,null,4096,1789100000),"Earlier bindings inferred ordinary departure")
		return
	var checkpoint:=Checkpoint.new();var station: RefCounted=checkpoint.open(OS.get_environment("GOF2_FREE_PLAY_STATION_SCENARIO"),bindings)
	if station==null:check(false,checkpoint.error);return
	var before: Dictionary=station.snapshot()
	var bodies:=Bodies.new();var effects:=Effects.new()
	if not bodies.configure(library,bindings) or not effects.configure(library,bindings):check(false,bodies.error+effects.error);return
	var construction:=Construction.new()
	if not construction.prepare_free(bindings,cat,station,4096,1789100000,true,bodies,effects):check(false,construction.error);return
	var entry:=construction.snapshot()
	check(Flight.ordinary_entry(bindings,entry),"Acknowledged ordinary construction lacks its full context")
	check(entry.campaign_cursor==18 and entry.location.station_id==98 and entry.location.system_id==19,"Ordinary departure changed its earned location or cursor")
	check(entry.player_pose.origin==Vector3(10,10,10000),"Ordinary departure replaced the source player position with a combat fixture")
	check(entry.departure.mission==before.mission and entry.departure.progress==before.progress and entry.departure.contracts==before.contracts,"Ordinary construction changed the pending Suttnar mission or earned career")
	check(construction.contract_owner().snapshot()==before.contracts and before.contracts.credits==7850 and before.contracts.completed_side_missions==4,"Ordinary construction paid an unearned reward or lost its four jobs")
	check(entry.departure.cargo==before.cargo and construction.equipment_owner().snapshot()==before.equipment and entry.departure.equipment.ship_affiliation==0,"Ordinary departure lost cargo, equipment or source affiliation")
	var world: Dictionary=entry.scenery.world_initialization
	var context: Dictionary=world.npc_construction.free_context
	check(context.mission_kind==-1 and context.mission_completed and not context.mission_story and not context.special_arrival and not context.void_encounter,"Pending story state leaked into the ordinary default world")
	check(context.rank==before.contracts.rank and context.difficulty==before.contracts.difficulty and entry.departure.free_context==context,"Ordinary world changed the retained rank/difficulty")
	check(entry.player.vitals.hull==95 and entry.player.vitals.armor==entry.player.capacities.armor and entry.player.vitals.shield==entry.player.capacities.shield,"Ordinary station departure failed to clear and restore its equipped pools")
	check(entry.player.gamma==100.0 and entry.player.free_context==context,"Ordinary player lost source gamma or population identity")
	check(entry.location.current_planet_texture_id==int(bindings.opening_sky.planet_resources.near_textures[cat.tables.stations[98].planet_type]),"Ordinary location used another station's planet texture")
	var cargo:=Cargo.new();var briefing:=Briefing.new()
	if not cargo.configure_departure(bindings,cat,construction) or not briefing.configure(bindings,library,construction,"D"):check(false,cargo.error+briefing.error);return
	check(cargo.snapshot()==before.cargo,"Flight cargo did not retain the actual station hold")
	for tick in 70:
		if not briefing.advance(100):check(false,briefing.error);return
	check(not briefing.snapshot().entry_released and briefing.snapshot().phase=="entry","Ordinary launch released at the exact7000ms boundary")
	check(briefing.advance(1),briefing.error)
	check(briefing.snapshot().entry_released and briefing.snapshot().phase=="flight" and not briefing.snapshot().briefing_started,"Ordinary entry invented a modal instruction or delayed release")
	check(briefing.snapshot().mission==before.mission and briefing.snapshot().progress==before.progress,"Empty ordinary briefing completed the pending mission")
	verify_encounter(library,bindings,cat,construction)
	check(station.snapshot()==before,"Preparing the complete ordinary entry mutated the earned station")
	var previous: Dictionary=construction.snapshot()
	for field in ["acknowledged","alioth_return_acknowledged"]:
		var blocked: RefCounted=station.fork();blocked._state[field]=false
		check(not construction.prepare_free(bindings,cat,blocked,4096,1789100000,true,bodies,effects) and construction.snapshot()==previous,"Unacknowledged station changed the retained prepared flight")
	var blocked: RefCounted=station.fork();blocked._state.phase="conversation"
	check(not construction.prepare_free(bindings,cat,blocked,4096,1789100000),"Incomplete station conversation enabled ordinary departure")
	blocked=station.fork();blocked._state.mission.station_id=98
	check(not construction.prepare_free(bindings,cat,blocked,4096,1789100000),"Ordinary departure exposed the unsupported pending encounter")
	var earlier_path:=OS.get_environment("GOF2_ALIOTH_STATION_SCENARIO")
	if not earlier_path.is_empty():
		var earlier:=AliothCheckpoint.new();var at16: RefCounted=earlier.open(earlier_path,bindings)
		if at16==null:check(false,earlier.error);return
		check(not construction.prepare_free(bindings,cat,at16,4096,1789100000),"The earned Alioth16 station bypassed its remaining battle and conversation")
	check(construction.snapshot()==previous and station.snapshot()==before,"Rejected preparations altered retained state")
	print("Earned18 ordinary world prepared at ",entry.player_pose.origin,"; ",world.npc_construction.actors.size()," actors; rank ",context.rank)

func verify_encounter(library: RefCounted,bindings: RefCounted,cat: RefCounted,construction: RefCounted) -> void:
	var encounter:=Encounter.new()
	if not encounter.configure_free(bindings,cat,library,construction):check(false,encounter.error);return
	var before: Dictionary=encounter.snapshot();var entry: Dictionary=construction.snapshot()
	var current: RefCounted=encounter.fork_for_frame();var player: RefCounted=construction.player_owner();var scenery: RefCounted=construction.scenery_owner()
	var random: Dictionary=entry.random_state
	for tick in 10:
		var world: Dictionary=current.evaluate_world_logic(100,random)
		if world.is_empty():check(false,current.error);return
		current=world.encounter;random=world.random_state
		var contacts: Dictionary=current.evaluate_weapons(player,entry.player_pose,100,scenery,random)
		if contacts.is_empty():check(false,current.error);return
		current=contacts.encounter;player=contacts.player;scenery=contacts.scenery;random=contacts.random_state
		var actors: Dictionary=current.evaluate_world(player,entry.player_pose,100,random)
		if actors.is_empty():check(false,current.error);return
		current=actors.encounter;random=actors.random_state
	check(current.snapshot().world_elapsed_ms==1000 and current.snapshot().elapsed_ms==1000,"Ordinary encounter did not commit its shared weapon/world phases")
	check(current.snapshot().combat.current_reputation==entry.departure.contracts.reputation,"Idle ordinary frame changed earned standing")
	check(encounter.snapshot()==before and construction.snapshot()==entry,"Prospective ordinary encounter changed its retained owners")
	verify_career(library,bindings,cat,construction)

func verify_career(library: RefCounted,bindings: RefCounted,cat: RefCounted,construction: RefCounted) -> void:
	# Explicit lethal-contact inputs isolate career retention. They do not form
	# part of the earned checkpoint or the successful flight/docking path.
	for nonplayer in [false,true]:
		var encounter:=Encounter.new();var career: RefCounted=construction.contract_owner()
		var before: Dictionary=career.snapshot();var entry: Dictionary=construction.snapshot()
		if not encounter.configure_free(bindings,cat,library,construction) or not encounter.bind_contract_session(career,bindings):check(false,encounter.error);return
		var combat: RefCounted=encounter.combat_owner();var targets: Array=combat.snapshot().actors.filter(func(actor):return actor.get("population_group") not in ["freighter","capital","debris"])
		if targets.is_empty():check(false,"The earned fixture has no small ship for accounting");return
		var actor: Dictionary=targets[0];var vitals: Dictionary=actor.vitals
		if not combat.begin_contact_pass(entry.random_state,true):check(false,combat.error);return
		var hit: Dictionary=combat.normal_hit(actor.actor_id,int(vitals.hull+vitals.armor+vitals.shield),nonplayer)
		if hit.is_empty() or not hit.destroyed_now:check(false,combat.error);return
		encounter._combat=combat
		var world: Dictionary=encounter.evaluate_world(construction.player_owner(),entry.player_pose,0,combat.contact_random_state())
		if world.is_empty():check(false,encounter.error);return
		encounter=world.encounter
		var result: Dictionary=encounter.evaluate_contract_session(career,false,false)
		if result.is_empty():check(false,encounter.error);return
		career=result.session
		var retained: Dictionary=career.snapshot();var scene: Dictionary=encounter.snapshot()
		check(scene.controller.accounting.events.size()==1,"Ordinary lethal contact did not reach the retained accounting ledger")
		check(retained.progress.reputation==scene.combat.current_reputation and retained.reputation==scene.combat.current_reputation,"Ordinary combat failed to retain standing")
		check(retained.credits==before.credits and retained.completed_side_missions==before.completed_side_missions and retained.mission==before.mission and retained.pending_result.is_empty(),"Ordinary combat granted a contract reward or changed the side slot")
		if nonplayer:check(retained.progress==before.progress,"NPC-inflicted destruction granted the player career progress")
		else:check(retained.reputation!=before.reputation,"Player-inflicted ordinary destruction failed to retain its standing consequence")
		result=encounter.evaluate_contract_session(career,false,false)
		check(not result.is_empty() and result.session.snapshot()==retained,"Repeated ordinary polling counted the same destruction twice")
		var arrival: RefCounted=encounter.finish_contract_session(career)
		if arrival==null:check(false,encounter.error);return
		check(not arrival.snapshot().has("flight") and arrival.snapshot().progress==retained.progress,"Ordinary arrival lost earned combat or retained its active ledger")

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures+=1;push_error(message)
