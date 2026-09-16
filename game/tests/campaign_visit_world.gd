extends "res://tests/free_world.gd"
## Detached world/player composition using the earned equipment prerequisite.
## This does not create campaign progress; the application test earns the visit.
const GateArrival=preload("res://src/content/gate_arrival_definitions.gd")
const StationView=preload("res://src/content/station_presentation_definitions.gd")
const StationCamera=preload("res://src/simulation/station_camera.gd")

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==3:verify(args)
	else:check(false,"Expected content, bindings and visuals")
	print("Campaign visit world: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library):check(false,library.error+bindings.error+cat.error);return
	for station_id in [55,56,57]:
		var view:=StationView.select(bindings,station_id,19)
		var camera:=StationCamera.new()
		check(not view.is_empty() and camera.configure(view,4096),"Union station camera rejected its supported hangar: "+camera.error)
	var scenario:=Scenario.new();var equipment: RefCounted=scenario.open(OS.get_environment("GOF2_SCENARIO_INPUT"),bindings,cat)
	if equipment==null:check(false,scenario.error);return
	if not Scenario.prepare_alioth_component(equipment,bindings,cat):check(false,equipment.error);return
	for destination in [95,70,55,56]:
		var from: int=equipment.snapshot().loadout.station_id
		var current_system: int=equipment.snapshot().loadout.system_id
		var to_system: int=cat.tables.stations[destination].system_id
		if current_system!=to_system:
			var packet:=GateArrival.packet(bindings,cat,{"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"from_station_id":from,"destination_station_id":destination})
			if not equipment.relocate_gate_arrival(bindings,cat,packet):check(false,equipment.error);return
		else:
			var packet:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":18,"from_station_id":from,"station_id":destination,"system_id":to_system,"source_state":2,"world_type":3,"audio_selector":1}
			if not equipment.relocate_local_arrival(bindings,cat,packet):check(false,equipment.error);return
	var bodies:=Bodies.new();var effects:=Effects.new();var mounts:=Mounts.new()
	if not bodies.configure(library,bindings) or not effects.configure(library,bindings) or not mounts.open(library,cat):check(false,bodies.error+effects.error+mounts.error);return
	for cursor in [18,19]:
		var context:=FreePopulation.CONTEXT.duplicate(true)
		context.campaign_cursor=cursor;context.system_id=11;context.station_id=56
		if cursor==18:context.mission_kind=156;context.mission_story=true;context.mission_completed=false
		var scenery:=Scenery.new()
		if not scenery.configure_free(bindings,cat,equipment,context,CONDITIONS,2,true,bodies,effects):check(false,scenery.error);return
		var world: Dictionary=scenery.snapshot()
		check(world.system_id==11 and world.station_id==56 and world.objects.size()==world.bodies.objects.size(),"Suttnar lost its source field or collision owners")
		var factory: RefCounted=scenery.world_initialization_owner().npc_construction_owner()
		check(factory.snapshot().actors.is_empty()==(cursor==18),"The active visit and next ordinary world have the wrong populations")
		if cursor==19:
			var before: Dictionary=factory.snapshot()
			var cargo: Dictionary=factory.sample_relaunch_cargo(before.random_state)
			check(not cargo.is_empty() and factory.snapshot()==before,"Post-visit traffic cannot prepare detached replacement cargo")
		var player:=Player.new()
		if not player.configure_free(bindings,cat,equipment,factory):check(false,player.error);return
		check(player.snapshot().campaign_cursor==cursor and player.cache_snapshot().station_id==56,"The Union player lost its current cursor or location")
		var primaries:=Primary.new()
		if not primaries.configure(bindings,cat,mounts,player.loadout()):check(false,primaries.error);return
		check(not primaries.snapshot().guns.is_empty(),"The next campaign stage lost the retained primary gun")
