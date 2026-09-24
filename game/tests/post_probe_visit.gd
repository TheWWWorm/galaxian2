extends SceneTree
## Component-only station result checks. The loadout below supplies poll context;
## it is not an earned career, inventory fixture, save, or payment.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Campaign=preload("res://src/content/free_campaign_definitions.gd")
const Navigation=preload("res://src/content/free_navigation_definitions.gd")
const FreeFlight=preload("res://src/content/free_flight_definitions.gd")
const PlayerEntry=preload("res://src/content/player_entry_definitions.gd")
const StationView=preload("res://src/content/station_presentation_definitions.gd")
const Visit=preload("res://src/simulation/campaign_visit.gd")
const PopulationVectors=preload("res://tests/free_population.gd")
const Population=preload("res://src/simulation/traffic_population.gd")
const Factory=preload("res://src/simulation/opening_npc_construction.gd")
const Traffic=preload("res://src/content/free_traffic_definitions.gd")
const Lifecycle=preload("res://src/content/free_lifecycle_definitions.gd")
const SPEAKERS=[1,0,1,0,1,0,1,0,1,0]
const MISSION31={"kind":11,"station_id":98,"reward":30000,"bonus":0,"source_parameter":0}
const MISSION32={"kind":11,"station_id":10,"reward":0,"bonus":0,"source_parameter":0}
var checks:=0
var failures:=0
var library: RefCounted
var bindings: RefCounted
var catalogues: RefCounted

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=9:
		check(false,"Expected reader196, previous195 and older179 content/binding/visual triples")
	else:
		for index in range(0,args.size(),3):verify(args[index],args[index+1],index==0)
	print("Post-probe visit component: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(content: String,pack: String,expect_post_probe: bool) -> void:
	library=Library.new();bindings=Bindings.new();catalogues=Catalogues.new()
	if not library.open(content) or not bindings.open(pack,library.manifest) or not catalogues.open(library) or not library.select_language("gb"):
		check(false,library.error+bindings.error+catalogues.error);return
	var travel: Dictionary=bindings.mido_travel
	check(travel.has("post_probe_visits")==expect_post_probe,"Regression triple has an unexpected post-probe capability")
	if travel.has("post_probe_visits")!=expect_post_probe:return
	if not travel.has("post_probe_visits"):
		check(Campaign.dialogue_rules(bindings,31,MISSION31,true).is_empty() and Campaign.dialogue_rules(bindings,31,MISSION31).is_empty(),"Earlier binding opened the Alioth31 result")
		check(not Campaign.supported(travel,32) and Campaign.mission(travel,32).is_empty(),"Earlier binding admitted mission32")
		check(FreeFlight.flight(bindings,98,32).is_empty() and FreeFlight.docking(bindings,98,32).is_empty(),"Shared flight mechanics bypassed the absent mission32 source capability")
		check(not PlayerEntry.new().configure(bindings,32,98,false,0),"Player entry bypassed absent mission32 source capability")
		check(not Campaign.ordinary_story_at(travel,31,98) and not Navigation.destination_supported(bindings,32,MISSION32,10),"Earlier binding exposed a post-probe destination")
		check(not Visit.new().configure_station(bindings,library,catalogues,31,MISSION31),"Earlier binding configured the Alioth31 visit")
		return
	check(Campaign.supported(travel,31) and Campaign.supported(travel,32) and Campaign.mission(travel,31)==MISSION31 and Campaign.mission(travel,32)==MISSION32,"Post-probe mission identity changed")
	check(Campaign.ordinary_story_at(travel,31,98) and not Campaign.ordinary_story_at(travel,31,97),"Alioth31 actor-free station selection changed")
	check(not Navigation.destination_supported(bindings,32,MISSION32,10),"Mission32 destination opened before its native journey")
	check(Campaign.dialogue_rules(bindings,31,MISSION31).is_empty() and Campaign.dialogue_rules(bindings,32,MISSION32,true).is_empty(),"Post-probe result escaped its supported station/milestone")
	var rules: Dictionary=Campaign.dialogue_rules(bindings,31,MISSION31,true)
	check(not rules.is_empty(),"Source196 did not select the Alioth31 station result")
	if rules.is_empty():return
	var events: Array=rules.events
	check(events.size()==10 and rules.campaign_cursor==31 and rules.next_cursor==32 and rules.mission==MISSION31 and rules.next_mission==MISSION32 and rules.reward_credits==30000 and rules.target_station_required,"Alioth31 result/next mission differs from the source declaration")
	if events.size()!=10:return
	for index in 10:
		check(int(events[index].speaker_id)==SPEAKERS[index] and int(events[index].text_id)==1949+index and int(events[index].voice_event_id)==334+index,"Alioth31 source speaker/text/voice pair changed at line "+str(index+1))
	verify_station(events)
	verify_population()
	verify_flight_station_boundary()
	for language in library.manifest.languages:
		if not library.select_language(language):check(false,library.error);continue
		var translated:=Visit.new()
		if not translated.configure_station(bindings,library,catalogues,31,MISSION31):check(false,language+": "+translated.error);continue
		if not translated.poll_station(station_loadout(),true):check(false,language+": "+translated.error);continue
		for event in events:
			var line: Dictionary=translated.snapshot().dialogue
			check(line.visible and line.text_id==int(event.text_id) and line.text==library.strings[int(event.text_id)] and not line.speaker_name.is_empty(),"Alioth31 localized line is missing: "+language)
			check(translated.navigate("next"),translated.error)

func station_loadout(station_id:=98) -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"station_id":station_id,"ship_id":0,"equipment_ids":[],"cargo":{},"credits":0}

func verify_flight_station_boundary() -> void:
	# Native consumers must agree on the admitted transition, while source
	# capabilities remain authoritative for producing its flight/docking rules.
	for cursor in [31,32]:
		var flight:=FreeFlight.flight(bindings,98,cursor)
		var docking:=FreeFlight.docking(bindings,98,cursor)
		check(not flight.is_empty() and flight.campaign_cursor==cursor and flight.station_id==98 and flight.system_id==19,"Alioth transition lost its ordinary flight rules")
		check(not docking.is_empty() and FreeFlight.docking_parameters(docking),"An admitted Alioth flight was rejected by its docking consumer")
		check(not StationView.select(bindings,98,cursor).is_empty(),"An admitted Alioth station lost its original hangar presentation")
		var entry:=PlayerEntry.new()
		check(entry.configure(bindings,cursor,98,false,0) and entry.is_departure and entry.uses_equipment,"An admitted Alioth station lost its equipped player departure")
		check(entry.configure(bindings,cursor,98,true,0) and entry.restores_local and not entry.is_departure,"Alioth local arrival lost its restored player entry")
	check(FreeFlight.flight(bindings,98,33).is_empty() and FreeFlight.docking(bindings,98,33).is_empty(),"Imported future declarations admitted an unfinished mission33 flight")

func verify_station(events: Array) -> void:
	var visit:=Visit.new()
	check(visit.configure_station(bindings,library,catalogues,31,MISSION31),visit.error)
	if visit.snapshot().is_empty():return
	var waiting: Dictionary=visit.snapshot()
	check(waiting.phase=="waiting" and not waiting.dialogue.visible and not waiting.mission_completed and waiting.reward_credits==0 and visit.transition().is_empty(),"Alioth31 completed or paid before station contact")
	check(not visit.navigate("next") and visit.snapshot()==waiting,"Unopened Alioth31 result accepted Next")
	check(visit.poll_station(station_loadout(97),true) and visit.snapshot()==waiting,"Another landed station opened Alioth31")
	check(visit.poll_station(station_loadout(),false) and visit.snapshot()==waiting,"Flight opened the Alioth31 station result")
	check(visit.poll_station(station_loadout(),true,true) and visit.snapshot()==waiting,"Blocked station poll opened Alioth31")
	for changed in [{"station_id":-1},{"station_id":98.0},{"base_content_id":"foreign"},{"binding_id":"foreign"}]:
		var invalid:=station_loadout();invalid.merge(changed,true)
		check(not visit.poll_station(invalid,true) and visit.snapshot()==waiting,"Invalid station identity changed Alioth31: "+str(changed))
	var loadout:=station_loadout()
	check(visit.poll_station(loadout,true),visit.error)
	var opened: Dictionary=visit.snapshot()
	check(opened.dialogue.visible and opened.dialogue.count==10 and opened.mission_completed and opened.campaign_cursor==31 and opened.reward_credits==0 and visit.transition().is_empty(),"Alioth31 opening advanced or paid before final Next")
	check(visit.matches_station_inventory(loadout),"Alioth31 did not retain the presented station inventory")
	var changed:=loadout.duplicate(true);changed.credits+=1
	check(not visit.matches_station_inventory(changed),"Changed inventory matched the Alioth31 result")
	check(not visit.navigate("previous") and visit.snapshot()==opened,"Previous escaped before Alioth31's first line")
	check(visit.navigate("next") and visit.navigate("previous") and visit.snapshot()==opened,"Previous did not restore Alioth31's first line")
	var fork: RefCounted=visit.fork()
	check(fork.navigate("next") and visit.snapshot()==opened and fork.snapshot().dialogue.index==1,"Detached Alioth31 navigation changed its parent")
	check(fork.navigate("previous") and fork.snapshot()==opened,"Detached Alioth31 previous lost its first line")
	for event in events:
		var line: Dictionary=visit.snapshot().dialogue
		check(line.visible and line.text_id==int(event.text_id) and line.voice_event_id==int(event.voice_event_id) and line.speaker_id==int(event.speaker_id),"Alioth31 dialogue order or source pairing changed")
		check(line.text==library.strings[int(event.text_id)] and not line.speaker_name.is_empty(),"Alioth31 original localized speaker/text is missing")
		check(visit.snapshot().mission_completed and visit.snapshot().campaign_cursor==31 and visit.snapshot().reward_credits==0 and visit.transition().is_empty(),"An intermediate Alioth31 Next advanced or paid")
		check(visit.navigate("next"),visit.error)
	var transition: Dictionary=visit.transition()
	check(visit.snapshot().acknowledged and not visit.snapshot().dialogue.visible,"Alioth31 final Next left its result open")
	check(transition.get("base_content_id")==bindings.base_content_id and transition.get("binding_id")==bindings.binding_id and transition.get("from_cursor")==31 and transition.get("campaign_cursor")==32,"Alioth31 final Next changed career/content identity")
	check(transition.get("station_id")==98 and transition.get("previous_mission")==MISSION31 and transition.get("mission")==MISSION32 and transition.get("reward_credits")==30000,"Alioth31 transition changed its landed station, mission or prospective payment")
	var acknowledged: Dictionary=visit.snapshot()
	check(not visit.navigate("next") and visit.snapshot()==acknowledged,"Repeated Alioth31 acknowledgement changed progress")
	check(visit.poll_station(loadout,true) and visit.snapshot()==acknowledged,"Later station poll replayed Alioth31")
	transition.mission.station_id=0;transition.reward_credits=0
	check(visit.transition().mission.station_id==10 and visit.transition().reward_credits==30000,"Caller mutated the retained Alioth31 transition")
	for cursor in [30,32]:check(not visit.configure_station(bindings,library,catalogues,cursor,MISSION31) and visit.snapshot()==acknowledged,"Wrong cursor replaced the acknowledged Alioth31 result")
	for changed_mission in [{"reward":0},{"station_id":97},{"kind":156}]:
		var invalid:=MISSION31.duplicate(true);invalid.merge(changed_mission,true)
		check(not visit.configure_station(bindings,library,catalogues,31,invalid) and visit.snapshot()==acknowledged,"Wrong mission replaced the acknowledged Alioth31 result")
	check(not Visit.new().configure(bindings,library,31,MISSION31),"Alioth31 station result opened in flight mode")

func verify_population() -> void:
	# Detached source context only. No player, earned mission or station state is created.
	var story: Dictionary=PopulationVectors.CONTEXT.duplicate(true)
	story.campaign_cursor=31;story.mission_kind=11;story.mission_completed=false;story.mission_story=true
	check(Campaign.empty_story(bindings.mido_travel,story),"Selected Alioth31 lost its source-defined empty story scene")
	var altered:=story.duplicate(true);altered.system_id=18
	check(not Campaign.empty_story(bindings.mido_travel,altered),"Alioth31 empty story escaped Augmenta/system19")
	var factory:=Factory.new()
	if not factory.configure_free_factory(bindings,catalogues,0,[81,86],story,1700000000):check(false,factory.error);return
	var packet: Dictionary=factory.generate({"state":98765})
	if packet.is_empty():check(false,factory.error);return
	check(packet.actors.is_empty() and packet.population.actor_count==0 and packet.population.groups.values().all(func(count):return count==0) and packet.population.mission_kind==11,"Selected Alioth31 constructed ordinary actors")
	check(not Traffic.population(bindings,packet,story.rank,story.difficulty).is_empty() and not Lifecycle.population(bindings,packet).is_empty(),"Alioth31 empty scene was rejected by ambient combat/lifecycle owners")
	var ordinary: Dictionary=PopulationVectors.CONTEXT.duplicate(true)
	ordinary.campaign_cursor=32
	check(not Campaign.empty_story(bindings.mido_travel,ordinary),"Ordinary mission32 retained Alioth31's empty scene")
	var population:=Population.new()
	if not population.configure_free(bindings,catalogues,ordinary,1700000000):check(false,population.error);return
	var generated: Dictionary=population.generate({"state":98765})
	check(not generated.is_empty() and generated.actor_count>=2 and generated.has("unix_seconds") and not generated.has("mission_kind"),"Ordinary mission32 at Alioth98 lost ambient traffic")
	if generated.is_empty():return
	var ordinary_factory:=Factory.new()
	if not ordinary_factory.configure_free_factory(bindings,catalogues,0,[81,86],ordinary,1700000000):check(false,ordinary_factory.error);return
	var ordinary_packet: Dictionary=ordinary_factory.generate({"state":98765})
	check(not ordinary_packet.is_empty() and ordinary_packet.population==generated and ordinary_packet.actors.size()==generated.actor_count and not ordinary_packet.actors.is_empty(),"Ordinary mission32 population did not construct traffic")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)
