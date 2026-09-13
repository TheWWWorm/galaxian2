extends "res://tests/combat_training_focused.gd"
## Source dialogue with an earned loadout and explicitly activated NPC fixtures.
const StoryRules=preload("res://src/content/combat_training_story_definitions.gd")
const TrainingRadio=preload("res://src/simulation/radio_sequence.gd")
const RadioResources=preload("res://src/presentation/opening_radio_resources.gd")
const TrainingAudio=preload("res://src/content/audio_resources.gd")

func run():
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected content, bindings and visuals")
	if args.size()==3:verify(args)
	print("Combat-training story: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_training_destruction(args: PackedStringArray, equipment: RefCounted):
	super.verify_training_destruction(args,equipment)
	var rules: Dictionary=bindings.combat_training_story
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	if Bindings.reader_version(header.reader)>=122:check(StoryRules.parameters(rules),"Current Mac pack omitted training story")
	if rules.is_empty():
		check(StoryRules.radio(bindings).is_empty() and StoryRules.briefing(bindings).is_empty(),"Earlier pack invented training dialogue")
		return
	check(story_validation(rules,header.source_executable_bytes).is_empty(),"Training story rejected its recovered source")
	for key in StoryRules.VALUES:
		var bad:=rules.duplicate(true);bad[key]=null
		check(not StoryRules.parameters(bad),"Changed training story accepted: "+key)
	for key in StoryRules.SPANS:
		var bad:=rules.duplicate(true);bad.provenance[key].offset+=1
		check(not story_validation(bad,header.source_executable_bytes).is_empty(),"Disconnected training story accepted: "+key)
	if rules.has("station_return"):
		for key in StoryRules.RETURN_VALUES:
			var bad:=rules.duplicate(true);bad.station_return[key]=null
			check(not StoryRules.parameters(bad),"Changed training return accepted: "+key)
		for key in StoryRules.RETURN_SPANS:
			var bad:=rules.duplicate(true);bad.provenance[key].offset+=1
			check(not story_validation(bad,header.source_executable_bytes).is_empty(),"Disconnected training return accepted: "+key)
	if rules.has("navigation"):
		for key in StoryRules.NAVIGATION_VALUES:
			var bad:=rules.duplicate(true);bad.navigation[key]=null
			check(not StoryRules.parameters(bad),"Changed training navigation accepted: "+key)
		for key in StoryRules.NAVIGATION_SPANS:
			var bad:=rules.duplicate(true);bad.provenance[key].offset+=1
			check(not story_validation(bad,header.source_executable_bytes).is_empty(),"Disconnected training navigation accepted: "+key)
	var briefing:=StoryRules.briefing(bindings)
	check(briefing.campaign_cursor==7 and briefing.mission_kind==4 and briefing.entry_release_ms==7001 and briefing.briefing_minimum_ms==5001,"Training lost the shared entry/HUD clocks")
	check(briefing.events.map(func(row):return int(row.text_id))==[1726,1727,1728] and bindings.desktop_text_id(1728)==1729,"Training briefing or desktop fire instruction changed")
	check(rules.completion_events.map(func(row):return int(row.text_id))==[1733,1734,1735,1736,1737],"Training completion dialogue changed")
	var cat:=Catalogues.new();check(cat.open(lib),cat.error)
	var source:=TrainingWorld.new()
	check(source.configure_combat_training(bindings,cat,equipment,Vector3(10,10,10000),{"companions_empty":true,"location_match":false,"special_placement":false}),source.error)
	check(not source.generate({"state":int(TRAINING_GOLDEN[0].input_state)}).is_empty(),source.error)
	var sleeping:=LiveGroup.new();check(sleeping.configure_combat_training(bindings,cat,source,0,.5),sleeping.error)
	var live:=training_armed_group(cat,source)
	var resources:=RadioResources.new();check(resources.prepare(lib,bindings,visuals,7),resources.error)
	if resources.line_counts.size()!=2:return
	check(resources.speakers.has(0) and resources.speakers.has(2),"Training lost Keith or Gunant's presentation")
	var radio:=TrainingRadio.new();check(radio.configure(bindings,lib,resources.line_counts,7),radio.error)
	check(radio.step_combat_training(0,sleeping).is_empty() and radio.error.is_empty(),"Friendly Gunant or dormant pirates triggered retreat radio")
	var before:=radio.snapshot()
	check(radio.step(100,{0:0,1:0,2:0},0).is_empty() and not radio.error.is_empty() and radio.snapshot()==before,"A fabricated hull map bypassed training activity")
	check(radio.step_combat_training(100,LiveGroup.new()).is_empty() and not radio.error.is_empty() and radio.snapshot()==before,"Unconfigured combat changed radio")
	check(radio.step_combat_training(0,live)==[{"kind":"started","event":0}],"Active hostile training NPC did not start the first line")
	check(not radio.snapshot().visible and radio.snapshot().started==[true,false],"Started training radio was treated as displayed")
	check(radio.step_combat_training(2000,live).is_empty(),"Training display delay became inclusive")
	check(radio.step_combat_training(2001,live)==[{"kind":"display","event":0,"text_id":1731}],"Training display lost its text")
	var finished_at:=3500+2000*int(resources.line_counts[0])
	check(radio.step_combat_training(finished_at,live).is_empty(),"Training line finished at its strict boundary")
	check(radio.step_combat_training(finished_at+1,live)==[{"kind":"finished","event":0}],"Training line did not finish")
	check(radio.snapshot().started==[true,false],"Second line started inside the first line's completion pass")
	check(radio.step_combat_training(finished_at+1,sleeping)==[{"kind":"started","event":1}],"Dependent Keith line wrongly required active hostiles again")
	var fork: RefCounted=radio.fork_for_frame();before=radio.snapshot()
	check(fork.step_combat_training(100000,sleeping).size()==2 and radio.snapshot()==before,"Detached radio changed its original clock")
	check(radio.step_combat_training(0,live).is_empty() and not radio.error.is_empty() and radio.snapshot()==before,"Backward training time changed radio")
	# A lethal but still active NPC remains eligible for condition16. This is
	# distinct from condition18, which waits for the actual explosion modes.
	for id in 3:check(not live.normal_hit(id,9999999).is_empty(),live.error)
	var lethal:=TrainingRadio.new();check(lethal.configure(bindings,lib,resources.line_counts,7),lethal.error)
	check(lethal.step_combat_training(0,live)==[{"kind":"started","event":0}],"Training radio invented a positive-hull condition")
	verify_training_voice()

func story_validation(data: Dictionary, source_bytes: int) -> String:
	return StoryRules.validate(data,source_bytes,"x86_64",bindings.arrival_staging,bindings.combat_training,bindings.combat_training_destruction,bindings.mining_briefing,bindings.mining_objective,bindings.opening_dialogue,bindings.full_hold_story)

func verify_training_voice():
	for language in ["gb","de"]:
		check(lib.select_language(language),lib.error)
		var audio:=TrainingAudio.new();check(audio.configure(lib,bindings,7),audio.error)
		for id in [543,544]:
			var clip:=audio.prepare(id)
			check(not clip.is_empty() and not clip.has("unsupported") and clip.get("voice",false),"Unsupported training radio voice %d/%s: %s"%[id,language,audio.error])
		check(audio.configure_mining_briefing(lib,bindings,7),audio.error)
		var first:=audio.prepare(189)
		check(not first.is_empty() and not first.has("unsupported") and first.get("voice",false),"Training briefing voice unavailable")
		check(audio.configure_training_completion(lib,bindings),audio.error)
		for id in range(439,444):
			var clip:=audio.prepare(id)
			check(not clip.is_empty() and not clip.has("unsupported") and clip.get("voice",false),"Training completion voice unavailable: "+str(id))
	check(lib.select_language("gb"),lib.error)
