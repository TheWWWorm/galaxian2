extends SceneTree
## Component boundaries only. This test does not create campaign progress or
## claim that the destination is connected to the playable travel route.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Visit=preload("res://src/simulation/campaign_visit.gd")
const Definitions=preload("res://src/content/suttnar_visit_definitions.gd")
const Navigation=preload("res://src/content/free_navigation_definitions.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()==3:verify(args)
	else:check(false,"Expected content, bindings and visuals")
	print("Campaign visit component: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not library.select_language("gb"):
		check(false,library.error+bindings.error);return
	var mission: Dictionary=Definitions.VALUES.mission.duplicate(true)
	var visit:=Visit.new()
	if not Definitions.available(bindings):
		check(not visit.configure(bindings,library,18,mission),"Earlier bindings inferred the new conversation")
		return
	check(not visit.poll(56,10001,5001),"Unconfigured visit accepted a poll")
	if not visit.configure(bindings,library,18,mission):check(false,visit.error);return
	check(visit.transition().is_empty() and not visit.snapshot().dialogue.visible,"Fresh visit advanced the campaign")
	var initial: Dictionary=visit.snapshot()
	check(not visit.navigate("next") and visit.snapshot()==initial,"Navigation completed a visit before its trigger")
	check(visit.poll(56,10000,5001) and not visit.snapshot().dialogue.visible,"Exact10000ms incorrectly completed the visit")
	check(visit.poll(56,10001,5000) and not visit.snapshot().dialogue.visible,"The HUD poll ran at its exact5000ms boundary")
	check(visit.poll(55,10001,5001) and not visit.snapshot().dialogue.visible,"Another Union location completed Suttnar")
	check(visit.poll(56,10001,5001,true) and not visit.snapshot().dialogue.visible,"Docking substituted for the flight visit")
	check(visit.poll(56,10001,5001,false,true) and not visit.snapshot().dialogue.visible,"Blocked flight controls opened the conversation")
	var before: Dictionary=visit.snapshot()
	for invalid in [[-1,10001,5001],[56,-1,5001],[56,10001,-1],[56,10000.5,5001],[56,NAN,5001],[56,INF,5001],[56,9999,5001]]:
		check(not visit.poll(invalid[0],invalid[1],invalid[2]) and visit.snapshot()==before,"Invalid clock/location changed the retained visit")
	check(visit.poll(56,10001,5001),visit.error)
	check(visit.snapshot().dialogue.visible and visit.snapshot().dialogue.text_id==1838,"The flight threshold omitted its first original line")
	check(visit.snapshot().campaign_cursor==18 and visit.transition().is_empty(),"Opening the dialogue advanced the campaign")
	before=visit.snapshot()
	check(not visit.navigate("previous") and visit.snapshot()==before,"Previous escaped before the first line")
	check(not visit.navigate("skip") and visit.snapshot()==before,"Unsupported navigation skipped acknowledgements")
	var copy: RefCounted=visit.fork()
	check(copy.navigate("next") and visit.snapshot()==before,"A speculative dialogue frame mutated its parent")
	check(copy.navigate("previous") and copy.snapshot()==before,"Previous did not restore the first line")
	for event in bindings.mido_travel.suttnar_visit.events:
		var line: Dictionary=visit.snapshot().dialogue
		check(line.visible and line.text_id==int(event.text_id) and line.voice_event_id==int(event.voice_event_id) and line.speaker_id==int(event.speaker_id),"Dialogue ordering, voice or speaker changed")
		check(line.text==library.strings[int(event.text_id)] and not line.speaker_name.is_empty(),"Original localized dialogue is missing")
		check(visit.transition().is_empty(),"Dialogue advanced the campaign before final acknowledgement")
		check(visit.navigate("next"),visit.error)
	var transition:=visit.transition()
	check(visit.snapshot().acknowledged and not visit.snapshot().dialogue.visible,"Final acknowledgement left the dialogue open")
	check(transition.get("from_cursor")==18 and transition.get("campaign_cursor")==19 and transition.get("station_id")==56,"Acknowledgement selected a different campaign stage")
	check(transition.get("mission")=={"kind":156,"station_id":55,"reward":0,"bonus":0,"source_parameter":0} and transition.get("reward_credits")==0,"Acknowledgement invented a mission or reward")
	before=visit.snapshot()
	check(not visit.navigate("next") and visit.snapshot()==before,"Repeated acknowledgement changed the completed visit")
	check(visit.poll(56,20000,10000) and visit.snapshot()==before,"A later poll replayed the completed conversation")
	transition.mission.station_id=99
	check(visit.transition().mission.station_id==55,"A caller changed the retained transition")
	for cursor in [17,19,18.5]:check(not visit.configure(bindings,library,cursor,mission) and visit.snapshot()==before,"Unsupported cursor replaced the retained visit")
	var bad:=mission.duplicate(true);bad.reward=100
	check(not visit.configure(bindings,library,18,bad) and visit.snapshot()==before,"An unearned reward entered the visit")
	bad=mission.duplicate(true);bad.station_id=55
	check(not visit.configure(bindings,library,18,bad) and visit.snapshot()==before,"Another target used Suttnar's dialogue")
	for language in library.manifest.languages:
		check(library.select_language(language),library.error)
		check(Visit.new().configure(bindings,library,18,mission),"Visit text/speakers are missing in "+language)
	# Declarations and a component are insufficient to release this destination.
	check(not Navigation.ordinary_departure_at(bindings,18,mission,56),"The isolated component bypassed the playable story guard")
	print("Eight original voiced lines; strict clock and acknowledgement boundaries; route remains guarded")

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures+=1;push_error(message)
