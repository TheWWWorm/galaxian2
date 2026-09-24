extends SceneTree
## Detached dialogue predicates and presentation. No career or save is created.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const Campaign=preload("res://src/content/free_campaign_definitions.gd")
const Return=preload("res://src/content/kappa_return_definitions.gd")
const Visit=preload("res://src/simulation/campaign_visit.gd")
const Speech=preload("res://src/presentation/station_audio.gd")
const DialoguePanel=preload("res://src/presentation/station_dialogue_panel.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Locations=preload("res://src/simulation/lounge_cache.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
var checks:=0
var failures:=0

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size() in [3,4]:await verify(args)
	else:check(false,"Expected content, bindings, visuals and optional captures")
	print("Campaign station visit: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify(args: PackedStringArray) -> void:
	var library:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new();var visuals:=Visuals.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not cat.open(library) or not visuals.open(args[2],library.manifest) or not library.select_language("gb"):
		check(false,library.error+bindings.error+cat.error+visuals.error);return
	var original: Dictionary=bindings.mido_travel.duplicate(true)
	if not Return.available(bindings):
		for rules in Return.VALUES.conversations:
			check(not Visit.new().configure_station(bindings,library,cat,int(rules.campaign_cursor),rules.mission),"Earlier bindings admitted undeclared return dialogue")
		return
	check(Travel.parameters(original),"The new capability failed native validation")
	for key in ["secondary_ownership","kappa_rescue"]:
		var missing:=original.duplicate(true);missing.erase(key)
		check(not Travel.parameters(missing),"Return declarations lost their preceding capability: "+key)
	var altered:=original.duplicate(true);altered.kappa_return.conversations[1].reward_credits=20001
	check(not Travel.parameters(altered),"A changed source reward was accepted")
	var fit: Dictionary=bindings.mido_travel.kappa_preparation.fitting
	verify_predicate(bindings,library,cat,fit,true)
	for rules in bindings.mido_travel.kappa_return.conversations:verify_predicate(bindings,library,cat,rules,false)
	verify_coordinates(bindings,library,cat)
	verify_briefing(bindings)
	var conversations: Array=[bindings.mido_travel.suttnar_visit,bindings.mido_travel.kappa_preparation.visit,fit]
	conversations.append_array(bindings.mido_travel.kappa_return.conversations)
	for language in library.manifest.languages:
		if not library.select_language(language):check(false,library.error);return
		for rules in conversations:
			var cursor:=int(rules.campaign_cursor);var visit:=Visit.new()
			check(visit.configure(bindings,library,cursor,rules.mission) if cursor in [18,19] else visit.configure_station(bindings,library,cat,cursor,rules.mission),visit.error+": "+language)
		if language not in ["gb","de","pl","ru"]:continue
		await verify_presentation(bindings,library,visuals,conversations,args)
	check(bindings.mido_travel==original,"Dialogue preparation changed imported declarations")
	for cursor in [20,21,22,23,24]:
		check(Campaign.supported(bindings.mido_travel,cursor)==Campaign.chapter_available(bindings.mido_travel),"Dialogue preparation changed the declared chapter's travel capability")

func verify_coordinates(bindings: RefCounted,library: RefCounted,cat: RefCounted) -> void:
	# Generate a detached cache with explicit catalogue inputs, as in the stock
	# component tests. This does not construct a career, fly a trip or save it.
	var locations:=Locations.new();var random:=Random.new();random.seed_from(917)
	var context:={"campaign_cursor":18,"station_id":55,"rank":2,"reputation":{"axes":[30,0],"override":-1}}
	var settings:={"difficulty":1.0,"valkyrie_owned":false,"supernova_owned":false,
		"energy_availability_percent":0,"missile_availability_percent":0,"ship_price_percent":0}
	if not locations.configure(bindings) or not locations.select_location(bindings,cat,library,context,settings,random.snapshot(),1789100000):check(false,locations.error);return
	var before:=locations.snapshot()
	check(not before.system_availability[6] and not locations.item_stock(55).is_empty(),"The coordinate fixture did not retain the original unavailable system and station stock")
	var rules: Dictionary=bindings.mido_travel.kappa_return.conversations[0]
	var visit:=Visit.new()
	var loadout:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"station_id":55,"slots":[]}
	if not visit.configure_station(bindings,library,cat,int(rules.campaign_cursor),rules.mission) or not visit.poll_station(loadout,true):check(false,visit.error);return
	for event in rules.events:
		check(not locations.acknowledge_campaign_coordinates(bindings,visit) and locations.snapshot()==before,"An unfinished return unlocked system coordinates")
		if not visit.navigate("next"):check(false,visit.error);return
	var staged: RefCounted=locations.fork()
	check(staged.acknowledge_campaign_coordinates(bindings,visit),staged.error)
	var expected:=before.duplicate(true);expected.system_availability[6]=true
	check(staged.snapshot()==expected and locations.snapshot()==before,"Coordinates changed stock, contacts, history, randomness or their original owner")
	check(staged.acknowledge_campaign_coordinates(bindings,visit) and staged.snapshot()==expected,"Repeated coordinates changed the retained cache")
	var invalid: RefCounted=visit.fork();invalid._state.binding_id="foreign"
	check(not locations.acknowledge_campaign_coordinates(bindings,invalid) and locations.snapshot()==before,"A foreign conversation changed the retained cache")
	invalid=visit.fork();invalid._rules.unlock_system_ids=[7]
	check(not locations.acknowledge_campaign_coordinates(bindings,invalid) and locations.snapshot()==before,"Changed coordinates unlocked an undeclared system")
	for availability in [[],before.system_availability.slice(1),before.system_availability.duplicate()]:
		if availability.size()==before.system_availability.size():availability[6]=1
		var malformed: RefCounted=locations.fork();malformed._state.system_availability=availability
		var held: Dictionary=malformed.snapshot()
		check(not malformed.acknowledge_campaign_coordinates(bindings,visit) and malformed.snapshot()==held,"Invalid retained availability was replaced by campaign coordinates")
	context.station_id=56
	var elsewhere: RefCounted=locations.fork()
	if not elsewhere.select_location(bindings,cat,library,context,settings,before.random,1789100001):check(false,elsewhere.error);return
	var held: Dictionary=elsewhere.snapshot()
	check(not elsewhere.acknowledge_campaign_coordinates(bindings,visit) and elsewhere.snapshot()==held,"A conversation at another station unlocked coordinates")
	check(not locations.acknowledge_campaign_coordinates(bindings,Visit.new()) and locations.snapshot()==before,"An unconfigured conversation changed the retained cache")

func verify_predicate(bindings: RefCounted,library: RefCounted,cat: RefCounted,rules: Dictionary,fitting: bool) -> void:
	var cursor:=int(rules.campaign_cursor);var visit:=Visit.new()
	check(visit.configure_station(bindings,library,cat,cursor,rules.mission),visit.error)
	var loadout:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,
		"station_id":int(rules.mission.station_id),"slots":[null]}
	var waiting:=visit.snapshot()
	check(not visit.matches_station_inventory(loadout),"A waiting conversation retained an unaccepted inventory")
	check(not visit.poll(loadout.station_id,10001,5001) and visit.snapshot()==waiting,"Flight polling completed a docked conversation")
	check(visit.poll_station(loadout,false) and visit.snapshot()==waiting,"A nearby flight completed a docking requirement")
	check(visit.poll_station(loadout,true,true) and visit.snapshot()==waiting,"A blocked poll opened a story conversation")
	var foreign:=loadout.duplicate(true);foreign.binding_id="foreign"
	check(not visit.poll_station(foreign,true) and visit.snapshot()==waiting,"A foreign inventory changed the waiting conversation")
	for station in [-1,cat.tables.stations.size(),55.5]:
		var malformed:=loadout.duplicate(true);malformed.station_id=station
		check(not visit.poll_station(malformed,true) and visit.snapshot()==waiting,"Invalid station opened a conversation")
	if fitting:
		loadout.cargo=[{"item_id":41,"quantity":10}]
		check(visit.poll_station(loadout,true) and visit.snapshot()==waiting,"Cargo-only EMP completed the fitted-weapon lesson")
		loadout.slots=[{"item_id":2,"quantity":1,"category":0,"slot":0}]
		check(visit.poll_station(loadout,true) and visit.snapshot()==waiting,"An unrelated fitted primary completed the lesson")
		# Original fitting completion is permitted at any station, unlike return.
		loadout.station_id=56;loadout.slots.append({"item_id":41,"quantity":2,"category":1,"slot":0})
	else:
		var elsewhere:=loadout.duplicate(true);elsewhere.station_id=56
		check(visit.poll_station(elsewhere,true) and visit.snapshot()==waiting,"Another station completed the authored return")
	var before:=loadout.duplicate(true)
	check(visit.poll_station(loadout,true) and visit.snapshot().dialogue.visible,visit.error)
	check(visit.matches_station_inventory(loadout),"The station conversation did not retain its actual inventory")
	var changed_inventory:=loadout.duplicate(true);changed_inventory.slots=[]
	check(not visit.matches_station_inventory(changed_inventory),"A changed inventory retained an earlier fitting acknowledgement")
	var changed_station:=loadout.duplicate(true);changed_station.station_id=57
	check(not visit.matches_station_inventory(changed_station),"A station conversation accepted another docked inventory")
	check(visit.transition().is_empty(),"Entry or installed equipment skipped explicit acknowledgement")
	var fork: RefCounted=visit.fork()
	check(fork.matches_station_inventory(loadout),"Forking the conversation lost its accepted inventory")
	check(fork.navigate("next") and visit.snapshot().dialogue.index==0,"A staged acknowledgement changed its original owner")
	if rules.events.size()>1:
		check(visit.navigate("next") and visit.navigate("previous") and visit.snapshot().dialogue.index==0,"Previous-line replay changed the conversation")
	for event in rules.events:
		var line: Dictionary=visit.snapshot().dialogue
		check(line.visible and line.text_id==int(event.text_id) and line.speaker_id==int(event.speaker_id) and line.voice_event_id==int(event.voice_event_id),"A source dialogue event moved or lost its voice")
		check(visit.transition().is_empty(),"A partial conversation unlocked coordinates or paid its reward")
		check(visit.navigate("next"),visit.error)
	var receipt:=visit.transition()
	check(receipt.from_cursor==cursor and receipt.campaign_cursor==int(rules.next_cursor) and Equal.equal_value(receipt.previous_mission,rules.mission) and Equal.equal_value(receipt.mission,rules.next_mission) and receipt.station_id==loadout.station_id and receipt.reward_credits==int(rules.reward_credits),"Acknowledgement changed the declared campaign transition: "+str(receipt))
	check(receipt.mission.values().all(func(value):return value is int) and receipt.previous_mission.values().all(func(value):return value is int),"Imported JSON values were not normalized to native mission integers")
	if not fitting:
		check(Equal.equal_value(receipt.unlock_system_ids,rules.unlock_system_ids) and Equal.equal_value(receipt.next_course,rules.next_course),"Acknowledgement changed the source coordinates or next course")
		check(receipt.unlock_system_ids.all(func(value):return value is int) and receipt.next_course.values().all(func(value):return value is int),"Coordinates did not use native integer IDs")
		if cursor==22:check(receipt.reward_credits==0 and receipt.unlock_system_ids==[6],"Kappa return paid the later reward")
		if cursor==23:check(receipt.reward_credits==20000 and receipt.mission.kind==4 and receipt.mission.station_id==48,"Deep Science lost its reward or Sahi objective")
	receipt.reward_credits=-1
	check(visit.transition().reward_credits==int(rules.reward_credits),"The caller could alter a retained acknowledgement")
	check(visit.snapshot().reward_credits==0 and loadout==before,"Dialogue directly paid or changed equipment")
	var acknowledged:=visit.snapshot()
	check(not visit.navigate("next") and visit.snapshot()==acknowledged,"A second acknowledgement changed a completed conversation")
	var invalid: Dictionary=rules.mission.duplicate(true);invalid.station_id=56
	check(not visit.configure_station(bindings,library,cat,cursor,invalid) and visit.snapshot()==acknowledged,"Invalid reconfiguration replaced an accepted conversation")

func verify_briefing(bindings: RefCounted) -> void:
	var context:={"campaign_cursor":23,"system_id":6,"station_id":10,"mission_kind":11,"mission_story":true,"mission_completed":false}
	check(Return.selected(bindings.mido_travel,context) and Equal.equal_value(Return.briefing(bindings.mido_travel,context),bindings.mido_travel.kappa_return.arrival_briefing.events),"Deep Science arrival omitted its original briefing")
	for key in context:
		var changed:=context.duplicate()
		changed[key]=not changed[key] if changed[key] is bool else int(changed[key])+1
		check(Return.briefing(bindings.mido_travel,changed).is_empty(),"Arrival speech was selected for a different mission context: "+key)
	context.campaign_cursor=22;context.system_id=11;context.station_id=55
	check(Return.selected(bindings.mido_travel,context) and Return.briefing(bindings.mido_travel,context).is_empty(),"Kappa docking invented an arrival briefing")
	context.campaign_cursor=23
	check(Return.briefing(bindings.mido_travel,context).is_empty(),"Leaving Kappa played the Deep Science arrival speech")

func verify_presentation(bindings: RefCounted,library: RefCounted,visuals: RefCounted,conversations: Array,args: PackedStringArray) -> void:
	var viewport:=SubViewport.new();viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	for rules in conversations:
		var cursor:=int(rules.campaign_cursor);var station_only:=cursor>=20
		var panel:=DialoguePanel.new();viewport.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if not panel.configure_campaign_visit(library,bindings,visuals,cursor,rules.mission,station_only):check(false,panel.error);viewport.free();return
		var speech:=Speech.new();root.add_child(speech)
		if not speech.configure_campaign_visit(library,bindings,cursor,rules.mission,station_only):check(false,speech.error);speech.free();viewport.free();return
		check(speech._clips.size()==rules.events.size(),"Voice slots differ from dialogue positions")
		speech.set_paused(true)
		var reader: RefCounted=load("res://src/content/dialogue_lines.gd").new()
		var lines: Array=reader.read(bindings,library,rules.events)
		if lines.size()!=rules.events.size():check(false,reader.error);speech.free();viewport.free();return
		var longest:=0
		for index in lines.size():
			if lines[index].desktop_text.length()>lines[longest].desktop_text.length():longest=index
		for mobile in [false,true]:
			viewport.size=Vector2i(1280,720) if mobile else Vector2i(960,540);panel.set_mobile_layout(mobile)
			for index in lines.size():
				var state:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"language":library.active_language,"dialogue":lines[index].duplicate(true)}
				state.dialogue.merge({"visible":true,"index":index,"count":lines.size(),"previous_available":index>0})
				check(panel.present(state),panel.error)
				for frame in 2:await process_frame
				check(Rect2(Vector2.ZERO,Vector2(viewport.size)).encloses(panel._panel.get_rect()),"Conversation leaves the landscape viewport")
				check(panel._portrait.texture!=null and panel._body.text==(lines[index].text if mobile else lines[index].desktop_text),"Original portrait or localized text is missing")
				check(panel._next.text==library.strings[180 if index==lines.size()-1 else 179] and panel._previous.disabled==(index==0),"Conversation lost its original acknowledgement controls")
				check(speech.present(index),speech.error)
				var event: Dictionary=rules.events[index]
				check(speech._clips[index]==null if int(event.voice_event_id)<0 else speech._clips[index].id==int(event.voice_event_id),"Voice ordering or a silent instruction changed")
				if args.size()==4 and DisplayServer.get_name()!="headless" and index in [longest,lines.size()-1]:
					await RenderingServer.frame_post_draw
					check(viewport.get_texture().get_image().save_png(args[3].path_join("campaign-%d-%s-%s-%d.png"%[cursor,library.active_language,"touch" if mobile else "desktop",index]))==OK,"Could not save the conversation capture")
		speech.free();panel.free()
	viewport.free()

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures+=1;push_error(message)
