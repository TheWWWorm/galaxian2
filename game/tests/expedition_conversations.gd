extends SceneTree
## Detached original conversations. These fixtures do not earn a campaign save
## or assert that travel to their destinations is connected in the current UI.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Campaign=preload("res://src/content/free_campaign_definitions.gd")
const Visit=preload("res://src/simulation/campaign_visit.gd")
const Post=preload("res://src/content/post_sahi_definitions.gd")
const Thynome=preload("res://src/content/thynome_expedition_definitions.gd")
const Dima=preload("res://src/content/dima_return_definitions.gd")

var checks:=0
var failures:=0
var library: RefCounted
var bindings: RefCounted
var catalogues: RefCounted

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=3:check(false,"Expected content, bindings and visuals");finish();return
	library=Library.new();bindings=Bindings.new();catalogues=Catalogues.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not catalogues.open(library) or not library.select_language("gb"):
		check(false,library.error+bindings.error+catalogues.error);finish();return
	var station_mission: Dictionary=Post.active_mission(bindings,27)
	var flight_mission: Dictionary=Post.active_mission(bindings,30)
	if not Thynome.available(bindings) or not Dima.parameters(bindings.mido_travel.get("dima_return",{})):
		var unavailable:=Visit.new()
		check(not unavailable.configure_station(bindings,library,catalogues,27,station_mission),"Earlier bindings invented Thynome station dialogue")
		check(not unavailable.configure(bindings,library,30,{"kind":156,"station_id":91,"reward":0,"bonus":0,"source_parameter":0}),"Earlier bindings invented Dima flight dialogue")
		check(unavailable.snapshot().is_empty() and unavailable.transition().is_empty(),"Unavailable expedition acquired state")
		finish();return
	check(station_mission=={"kind":11,"station_id":10,"reward":0,"bonus":0,"source_parameter":0},"Thynome's selected source mission changed")
	check(flight_mission=={"kind":156,"station_id":91,"reward":0,"bonus":0,"source_parameter":0},"Dima's selected source mission changed")
	verify_station(station_mission)
	verify_flight(flight_mission)
	finish()

func station_loadout(station_id:=10) -> Dictionary:
	# Explicit detached inventory identity; no earned station state is built.
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"station_id":station_id,"ship_id":0,"equipment_ids":[81],"cargo":{},"credits":1234}

func verify_station(mission: Dictionary) -> void:
	var rules: Dictionary=Thynome.conversation(bindings,27,mission)
	var events: Array=bindings.mido_travel.post_sahi.missions["27"].result_events
	check(not rules.is_empty() and rules.events==events and rules.campaign_cursor==27 and rules.next_cursor==28 and rules.reward_credits==0,"Thynome source dialogue was not selected")
	check(Campaign.dialogue_rules(bindings,27,mission,true)==rules and Campaign.dialogue_rules(bindings,27,mission).is_empty(),"Station-only Thynome conversation escaped its mode")
	check(events.size()==11 and bindings.mido_travel.thynome_expedition.station_ack.result_event_count==11,"Thynome's eleven source lines were truncated")
	var visit:=Visit.new();check(visit.configure_station(bindings,library,catalogues,27,mission),visit.error)
	if visit.snapshot().is_empty():return
	var original: Dictionary=visit.snapshot()
	check(visit.transition().is_empty() and not original.dialogue.visible,"Thynome completed before docked target contact")
	check(not visit.navigate("next") and visit.snapshot()==original,"Unopened Thynome result accepted Next")
	var wrong:=station_loadout(11)
	check(visit.poll_station(wrong,true) and visit.snapshot().phase=="waiting","A different station opened Thynome's result")
	check(visit.poll_station(station_loadout(),false) and visit.snapshot().phase=="waiting","Flight substituted for landed Thynome")
	check(visit.poll_station(station_loadout(),true,true) and visit.snapshot().phase=="waiting","A held station poll opened Thynome's result")
	var before: Dictionary=visit.snapshot()
	for altered in [{"station_id":-1},{"station_id":10.0},{"base_content_id":"other"},{"binding_id":"other"}]:
		var invalid:=station_loadout();invalid.merge(altered,true)
		check(not visit.poll_station(invalid,true) and visit.snapshot()==before,"Invalid Thynome location or identity changed its result: "+str(altered))
	var inventory:=station_loadout()
	check(visit.poll_station(inventory,true),visit.error)
	check(visit.snapshot().dialogue.visible and visit.snapshot().dialogue.count==11 and visit.transition().is_empty(),"Thynome did not open the original result")
	check(visit.matches_station_inventory(inventory),"Thynome lost the inventory presented at result opening")
	var changed:=inventory.duplicate(true);changed.credits+=1
	check(not visit.matches_station_inventory(changed),"Changed credits matched the retained station inventory")
	changed=inventory.duplicate(true);changed.cargo[131]=1
	check(not visit.matches_station_inventory(changed),"Changed cargo matched the retained station inventory")
	before=visit.snapshot()
	check(not visit.navigate("previous") and visit.snapshot()==before,"Previous escaped before Thynome's first line")
	check(visit.navigate("next") and visit.navigate("previous") and visit.snapshot()==before,"Thynome previous did not restore its first line")
	var fork: RefCounted=visit.fork()
	check(fork.navigate("next") and visit.snapshot()==before,"Speculative Thynome navigation mutated its parent")
	for event in events:
		var line: Dictionary=visit.snapshot().dialogue
		check(line.visible and line.text_id==int(event.text_id) and line.voice_event_id==int(event.voice_event_id) and line.speaker_id==int(event.speaker_id),"Thynome original speaker/text/voice order changed")
		check(line.text==library.strings[int(event.text_id)] and not line.speaker_name.is_empty(),"Thynome localized result line is missing")
		check(visit.transition().is_empty(),"Thynome advanced before all eleven acknowledgements")
		check(visit.navigate("next"),visit.error)
	var transition: Dictionary=visit.transition()
	var next_mission:={"kind":4,"station_id":91,"reward":0,"bonus":0,"source_parameter":0}
	check(visit.snapshot().acknowledged and not visit.snapshot().dialogue.visible,"Thynome final Next left result open")
	check(transition.get("base_content_id")==bindings.base_content_id and transition.get("binding_id")==bindings.binding_id and transition.get("from_cursor")==27 and transition.get("campaign_cursor")==28,"Thynome acknowledgement changed career/content identity")
	check(transition.get("station_id")==10 and transition.get("previous_mission")==mission and transition.get("mission")==next_mission and transition.get("reward_credits")==0,"Thynome moved station, paid credits or selected another pending mission")
	before=visit.snapshot()
	check(not visit.navigate("next") and visit.snapshot()==before,"Repeated Thynome acknowledgement changed progress")
	check(visit.poll_station(inventory,true) and visit.snapshot()==before,"Thynome result replayed after acknowledgement")
	transition.mission.station_id=0
	check(visit.transition().mission.station_id==91,"Caller changed retained Thynome transition")
	for cursor in [26,28]:check(not visit.configure_station(bindings,library,catalogues,cursor,mission) and visit.snapshot()==before,"Wrong cursor replaced Thynome result")
	var changed_mission:=mission.duplicate(true);changed_mission.reward=30000
	check(not visit.configure_station(bindings,library,catalogues,27,changed_mission) and visit.snapshot()==before,"A paid Thynome mission passed exact selection")
	check(not Visit.new().configure(bindings,library,27,mission),"Thynome station dialogue opened in flight mode")

func verify_flight(mission: Dictionary) -> void:
	var rules: Dictionary=Campaign.dialogue_rules(bindings,30,mission)
	var events: Array=bindings.mido_travel.dima_return.result30.result_events
	check(not rules.is_empty() and rules.events==events and rules.campaign_cursor==30 and rules.next_cursor==31 and rules.reward_credits==0,"Dima flight result was not selected")
	check(Campaign.dialogue_rules(bindings,30,mission,true).is_empty() and events.size()==5,"Dima flight result escaped its mode or line count")
	var visit:=Visit.new();check(visit.configure(bindings,library,30,mission),visit.error)
	if visit.snapshot().is_empty():return
	var initial: Dictionary=visit.snapshot()
	check(visit.transition().is_empty() and not initial.dialogue.visible,"Dima advanced before its flight result")
	check(not visit.navigate("next") and visit.snapshot()==initial,"Unopened Dima result accepted Next")
	check(visit.poll(91,10000,5001) and not visit.snapshot().dialogue.visible,"Dima completed at exact 10000ms")
	check(visit.poll(91,10001,5000) and not visit.snapshot().dialogue.visible,"Dima completed at HUD 5000ms")
	check(visit.poll(90,10001,5001) and not visit.snapshot().dialogue.visible,"Another station completed Dima")
	check(visit.poll(91,10001,5001,true) and not visit.snapshot().dialogue.visible,"Docked Dima opened the flight result")
	check(visit.poll(91,10001,5001,false,true) and not visit.snapshot().dialogue.visible,"Held controller opened Dima's result")
	var before: Dictionary=visit.snapshot()
	for invalid in [[91,-1,5001],[91,10001,-1],[91,10000.5,5001],[91,NAN,5001],[91,INF,5001],[91,9999,5001],[-1,10001,5001]]:
		check(not visit.poll(invalid[0],invalid[1],invalid[2]) and visit.snapshot()==before,"Invalid Dima clock/location changed its result")
	check(visit.poll(91,10001,5001),visit.error)
	check(visit.snapshot().dialogue.visible and visit.snapshot().dialogue.count==5 and visit.transition().is_empty(),"Dima failed to open after both strict clocks and hold clear")
	before=visit.snapshot()
	check(not visit.navigate("previous") and visit.snapshot()==before,"Previous escaped before Dima's first line")
	check(visit.navigate("next") and visit.navigate("previous") and visit.snapshot()==before,"Dima previous did not restore its first line")
	for event in events:
		var line: Dictionary=visit.snapshot().dialogue
		check(line.visible and line.text_id==int(event.text_id) and line.voice_event_id==int(event.voice_event_id) and line.speaker_id==int(event.speaker_id),"Dima original speaker/text/voice order changed")
		check(line.text==library.strings[int(event.text_id)] and not line.speaker_name.is_empty(),"Dima localized result line is missing")
		check(visit.transition().is_empty(),"Dima advanced before all five acknowledgements")
		check(visit.navigate("next"),visit.error)
	var transition: Dictionary=visit.transition()
	var next_mission:={"kind":11,"station_id":98,"reward":30000,"bonus":0,"source_parameter":0}
	check(visit.snapshot().acknowledged and not visit.snapshot().dialogue.visible,"Dima final Next left its result open")
	check(transition.get("base_content_id")==bindings.base_content_id and transition.get("binding_id")==bindings.binding_id and transition.get("from_cursor")==30 and transition.get("campaign_cursor")==31,"Dima acknowledgement changed career/content identity")
	check(transition.get("station_id")==91 and transition.get("previous_mission")==mission and transition.get("mission")==next_mission and transition.get("reward_credits")==0,"Dima moved location, paid pending credits or selected another mission")
	check(int(bindings.mido_travel.dima_return.next_mission_factory.reward_credits)==30000 and transition.reward_credits==0,"Alioth's pending reward was paid at Dima")
	before=visit.snapshot()
	check(not visit.navigate("next") and visit.snapshot()==before,"Repeated Dima acknowledgement changed progress")
	check(visit.poll(91,20000,10000) and visit.snapshot()==before,"Dima result replayed after acknowledgement")
	transition.mission.station_id=0
	check(visit.transition().mission.station_id==98,"Caller changed retained Dima transition")
	for cursor in [29,31]:check(not visit.configure(bindings,library,cursor,mission) and visit.snapshot()==before,"Wrong cursor replaced Dima result")
	var changed_mission:=mission.duplicate(true);changed_mission.reward=30000
	check(not visit.configure(bindings,library,30,changed_mission) and visit.snapshot()==before,"A paid Dima mission passed exact selection")
	check(not Visit.new().configure_station(bindings,library,catalogues,30,mission),"Dima flight result opened as a station conversation")

func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(message)

func finish() -> void:
	print("Expedition conversations: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)
