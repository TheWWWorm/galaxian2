extends "res://tests/combat_training_story.gd"
## Detached departure built from the captured, acknowledged station transition.
const PreparedTraining=preload("res://src/simulation/first_flight_construction.gd")
const TrainingBriefing=preload("res://src/simulation/mining_briefing.gd")
const PreparedBodies=preload("res://src/content/scenery_body_resources.gd")
const PreparedEffects=preload("res://src/content/scenery_effect_resources.gd")
const TrainingSession=preload("res://src/presentation/first_flight_session.gd")

func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected content, bindings and visuals")
	if args.size()==3:verify(args)
	print("Combat-training flight preparation: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_training_destruction(args: PackedStringArray, equipment: RefCounted):
	super.verify_training_destruction(args,equipment)
	if bindings.combat_training_story.is_empty():return
	var cat:=Catalogues.new();check(cat.open(lib),cat.error)
	var capture:=Scenario.new()
	check(capture.open(OS.get_environment("GOF2_SCENARIO_INPUT"),bindings,cat)!=null,capture.error)
	var station: RefCounted=capture.station_owner(bindings,cat)
	if station==null:check(false,capture.error);return
	var before: Dictionary=station.snapshot()
	var packet: Dictionary=station.prepare_departure(bindings,cat)
	check(not packet.is_empty(),station.error)
	if packet.is_empty():return
	check(station.snapshot()==before,"Departure preparation changed the acknowledged station")
	check(packet.size()==18 and packet.confirmation_required and packet.confirmation_text_id==386,"Training lost the normal departure confirmation")
	check(packet.loadout.equipment_ids==[22,90,81,55] and packet.cargo.entries==[{"item_id":0,"quantity":1}] and packet.cargo_used==1,"Departure discarded the equipped or spare weapon")
	check(packet.player.vitals.hull==95 and packet.player.vitals.armor==40 and packet.player.vitals.shield==0 and packet.player.gamma==100,"Training did not use the source departure pool reset")
	check(packet.progress==before.progress and packet.mission==before.mission,"Preparing departure granted progress or changed the mission")
	var unack: RefCounted=station.fork();unack._state.equipment_acknowledged=false
	check(unack.prepare_departure(bindings,cat).is_empty(),"Unacknowledged equipment departure was accepted")
	var bodies:=PreparedBodies.new();var effects:=PreparedEffects.new()
	check(bodies.configure(lib,bindings) and effects.configure(lib,bindings),bodies.error+effects.error)
	var flight:=PreparedTraining.new()
	check(flight.prepare(bindings,cat,packet,1789100000,1789100000,true,bodies,effects,equipment),flight.error)
	var state:=flight.snapshot()
	if state.is_empty():return
	check(state.location.campaign_cursor==7 and state.location.station_id==78 and state.location.system_id==15 and state.location.equipment_ids==packet.loadout.equipment_ids,"Training environment reverted to the unarmed replacement ship")
	check(state.player_pose.origin==Vector3(10,10,10000) and state.player_yaw_units==-1600,"Training inherited the wrong placement or yaw")
	check(state.environment_object=={"resource_id":16994,"position":Vector3(-3286,-8199,56915)} and state.before_yaw_random_state=={"state":48304870645230} and state.yaw_random_state=={"state":219906188857953},"Training environment or yaw consumed the wrong random stream")
	check(state.scenery.world_initialization.input_random_state=={"state":153548941033574} and state.camera_input_random_state=={"state":29269289608543},"Training camera did not follow the field and all four NPC constructors")
	check(state.camera_offset==Vector3(-517,1339,9000) and state.random_state=={"state":271576659757395},"Training camera duplicated or omitted an offset/sign draw")
	check(state.scenery.world_initialization.npc_construction.actors.size()==4 and state.scenery.objects.size()==130,"Prepared training population is incomplete")
	var owned: RefCounted=flight.equipment_owner();check(owned.transact("unmount",22),owned.error)
	check(flight.equipment_owner().snapshot()==equipment.snapshot() and station.snapshot()==before,"Mutable departure equipment escaped into its source owner")
	for key in ["cargo_used","cargo","equipment","loadout","progress","mission","player_cache"]:
		var broken:=packet.duplicate(true);broken[key]=-1 if key=="cargo_used" else {}
		check(not flight.prepare(bindings,cat,broken,1789100000,1789100000,true,bodies,effects,equipment) and flight.snapshot()==state,"Rejected departure changed the previous prepared world: "+key)
	check(not flight.prepare(bindings,cat,packet,1789100000,1789100000,true,bodies,effects) and flight.snapshot()==state,"Missing native equipment was reconstructed from packet data")
	var briefing:=TrainingBriefing.new();check(briefing.configure(bindings,lib,flight,"Space"),briefing.error)
	if briefing.snapshot().is_empty():return
	for i in 46:check(briefing.advance(150),briefing.error)
	check(briefing.advance(100) and not briefing.snapshot().entry_released,"Training entry released at 7000ms")
	check(briefing.advance(1) and briefing.snapshot().entry_released and not briefing.snapshot().dialogue.visible,"Entry release also displayed the modal")
	for i in 32:check(briefing.advance(150),briefing.error)
	check(briefing.advance(50) and not briefing.snapshot().dialogue.visible,"Training briefing opened at 5000ms HUD time")
	check(briefing.advance(1) and briefing.snapshot().dialogue.visible and briefing.snapshot().dialogue.text_id==1726,"Training briefing did not wait for entry release and its HUD poll")
	var held:=briefing.snapshot()
	check(briefing.advance(150) and briefing.simulation_delta_ms()==0 and briefing.snapshot()==held,"Training modal instructions auto-dismissed or advanced the flight")
	check(briefing.navigate("next") and briefing.snapshot().dialogue.text_id==1727,"Training marker explanation was skipped")
	check(briefing.navigate("next") and briefing.snapshot().dialogue.text_id==1728 and briefing.snapshot().dialogue.desktop_text_id==1729,"Training fire controls were substituted twice")
	check(briefing.navigate("previous") and briefing.navigate("next") and briefing.navigate("next"),briefing.error)
	check(briefing.snapshot().acknowledged and not briefing.snapshot().dialogue.visible and briefing.snapshot().mission==packet.mission and briefing.snapshot().progress==packet.progress,"Briefing acknowledgement completed the combat mission")
	check(not TrainingSession.supported(bindings,7),"Preparation exposed the unfinished training application scene")
