extends "res://tests/kappa_rescue.gd"
## Native radio observations and shared result presentation. No career, fitted
## inventory or earned save is constructed by these detached component checks.
const Outcome=preload("res://src/content/kappa_outcome_definitions.gd")
const Campaign=preload("res://src/content/free_campaign_definitions.gd")
const Visit=preload("res://src/simulation/campaign_visit.gd")
const Visuals=preload("res://src/content/visual_library.gd")
const DialoguePanel=preload("res://src/presentation/station_dialogue_panel.gd")
const Speech=preload("res://src/presentation/station_audio.gd")

func _initialize() -> void:call_deferred("run_results")

func run_results() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size() in [3,4]:await verify_results(args)
	else:check(false,"Expected content, bindings, visuals and optional captures")
	await process_frame
	print("Kappa acknowledged result: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_results(args: PackedStringArray) -> void:
	library=Library.new();bindings=Bindings.new()
	var visuals:=Visuals.new()
	if not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not visuals.open(args[2],library.manifest):
		check(false,library.error+bindings.error+visuals.error);return
	var visit:=Visit.new()
	if not Outcome.available(bindings):
		check(not visit.configure_result(bindings,library,21,Outcome.VALUES.mission) and visit.snapshot().is_empty(),"An older pack inferred unimported failure/result support")
		check(Campaign.result_presentation(bindings,21,Outcome.VALUES.mission).is_empty(),"An older pack exposed result presentation")
		return
	var original: Dictionary=bindings.mido_travel.duplicate(true)
	var header: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(args[1].path_join("bindings.json")))
	for key in Outcome.SPANS:
		var bad:=original.duplicate(true);bad.provenance[key].offset+=1
		check(not Travel.validate(bad,header.source_executable_bytes,"x86_64",bindings.arrival_staging,bindings.station_entry,bindings.combat_training).is_empty(),"Changed result proof was accepted: "+key)
	for key in Outcome.VALUES:
		var bad:=original.duplicate(true);bad.kappa_outcome[key]=null
		check(not Travel.parameters(bad),"Changed result declaration was accepted: "+key)
	for cursor in [18,19,20,22,23,24]:
		check(not visit.configure_result(bindings,library,cursor,Outcome.VALUES.mission),"Another campaign cursor obtained the rescue result")
	var wrong: Dictionary=Outcome.VALUES.mission.duplicate(true);wrong.reward=1
	check(not visit.configure_result(bindings,library,21,wrong),"A fabricated rescue reward was accepted")
	for language in library.manifest.languages:
		if not library.select_language(language):check(false,library.error);return
		var resources:=Resources.new()
		if not resources.prepare(library,bindings,null,21):check(false,resources.error);return
		counts=resources.line_counts.duplicate()
		verify_result_boundaries()
		if language in ["gb","de","pl","ru"]:await verify_result_presentation(visuals,args)
	check(bindings.mido_travel==original,"Result preparation changed imported declarations")
	for cursor in [20,21,22,23,24]:check(Campaign.supported(bindings.mido_travel,cursor)==Campaign.chapter_available(bindings.mido_travel),"Result components bypassed the connected chapter capability")

func result_owner() -> RefCounted:
	var visit:=Visit.new()
	check(visit.configure_result(bindings,library,21,Outcome.VALUES.mission),visit.error)
	return visit

func result_observation(success: bool,retired: bool) -> RefCounted:
	var radio:=fresh_radio();var cast:=actors();var context:=targets();var now:=0
	if success:
		context.player_targets[1].active=true
		for id in 5:
			if id==2:context.route_index=1
			if id==3:context.player_targets[0].active=true
			if id==4:context.player_targets[0].systems_disabled=true
			check(radio.step_kappa_rescue(now,context)==[{"kind":"started","event":id}],"Result fixture lost authored radio order")
			now=finish(radio,id,now,context)
	if retired:cast.actors[0].actor_mode=4
	var rescue:=Rescue.new()
	check(rescue.configure(bindings) and rescue.advance(radio,cast),rescue.error)
	return rescue

func verify_result_boundaries() -> void:
	var visit:=result_owner();var waiting: Dictionary=visit.snapshot()
	check(not visit.navigate("next") and visit.transition().is_empty() and visit.snapshot()==waiting,"Waiting rescue dialogue awarded a transition")
	check(not visit.poll(55,100000,100000) and not visit.poll_station({"station_id":55},true) and visit.snapshot()==waiting,"Visit/station predicates bypassed the rescue")
	var rescue:=result_observation(false,false)
	check(visit.poll_result(rescue,true) and visit.snapshot()==waiting and not visit.matches_result_observation(rescue),"Dormant ships completed the result")
	check(not visit.poll_result(Rescue.new(),true) and visit.snapshot()==waiting,"Unconfigured observations changed a result")
	var foreign: RefCounted=rescue.fork();foreign._state.binding_id="0".repeat(64)
	check(not visit.poll_result(foreign,true) and visit.snapshot()==waiting,"Foreign observations changed a result")
	check(not visit.poll_result(Visit.new(),true) and visit.snapshot()==waiting,"Another owner bypassed the rescue predicate")
	for successful in [false,true]:
		rescue=result_observation(successful,not successful)
		visit=result_owner()
		var observed: Dictionary=rescue.snapshot()
		if successful:
			check(visit.poll_result(rescue,false) and visit.snapshot().phase=="waiting","A gated completion opened the result")
		check(visit.poll_result(rescue,successful),visit.error)
		var offered: Dictionary=visit.snapshot()
		check(offered.outcome==("completed" if successful else "failed") and offered.campaign_cursor==21 and offered.dialogue.visible and offered.dialogue.count==1 and not offered.dialogue.previous_available,"Rescue result changed progress or lost its single acknowledged page")
		check(visit.transition().is_empty() and visit.matches_result_observation(rescue),"An unacknowledged result provided a receipt or lost its observation")
		check(visit.poll_result(rescue,true) and visit.snapshot()==offered and rescue.snapshot()==observed,"Repeated polling dismissed the result or changed its controller")
		check(not visit.navigate("previous") and visit.snapshot()==offered,"A one-line result navigated backwards")
		var branch: RefCounted=visit.fork()
		check(branch.navigate("next") and visit.snapshot()==offered,"Speculative acknowledgement changed the original result")
		var receipt: Dictionary=branch.transition()
		check(receipt.outcome==offered.outcome and receipt.from_cursor==21 and receipt.reward_credits==0 and branch.snapshot().campaign_cursor==21 and rescue.snapshot()==observed,"Acknowledgement fabricated earned progress or altered observations")
		if successful:
			check(receipt.campaign_cursor==22 and receipt.mission==Outcome.VALUES.success.next_mission and receipt.station_id==55 and not receipt.has("source_state"),"Rescue success selected the wrong return mission")
		else:
			check(receipt.source_state==1 and not receipt.has("campaign_cursor") and not receipt.has("mission"),"Rescue failure advanced the story or used the success return")
			check(offered.dialogue.speaker_id==16 and offered.dialogue.voice_event_id==-1 and offered.dialogue.text==library.strings[381]+"\n\n\n"+library.strings[308],"Failure lost original composed text, instruction portrait or silence")
		var acknowledged: Dictionary=branch.snapshot()
		check(not branch.navigate("next") and branch.snapshot()==acknowledged and branch.transition()==receipt,"Duplicate acknowledgement replayed a transaction")
		foreign=rescue.fork();foreign._state.phase+=1
		check(not branch.matches_result_observation(foreign),"Changed rescue observations reused a receipt")
		# Reconfiguration must not leak failure or result mode into a visit.
		var previous: Dictionary=bindings.mido_travel.suttnar_visit
		check(branch.configure(bindings,library,18,previous.mission) and branch.poll(int(previous.mission.station_id),100000,100000) and branch.snapshot().dialogue.visible and not branch.matches_result_observation(rescue),"A reused conversation retained rescue-only state")
	rescue=result_observation(true,true)
	for allowed in [false,true]:
		visit=result_owner()
		check(visit.poll_result(rescue,allowed) and visit.snapshot().outcome==("completed" if allowed else "failed"),"Simultaneous results lost completion priority or independent failure polling")
		var offered: Dictionary=visit.snapshot()
		check(visit.poll_result(rescue,not allowed) and visit.snapshot()==offered,"An offered result was replaced when poll eligibility changed")

func verify_result_presentation(visuals: RefCounted,args: PackedStringArray) -> void:
	var viewport:=SubViewport.new();viewport.size=Vector2i(960,540);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	for failed in [false,true]:
		var visit:=result_owner();var rescue:=result_observation(not failed,failed)
		check(visit.poll_result(rescue,not failed),visit.error)
		var panel:=DialoguePanel.new();viewport.add_child(panel);panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if not panel.configure_campaign_result(library,bindings,visuals,21,Outcome.VALUES.mission,failed):check(false,panel.error);panel.free();continue
		for mobile in [false,true]:
			viewport.size=Vector2i(1280,720) if mobile else Vector2i(960,540);panel.set_mobile_layout(mobile)
			check(panel.present(visit.snapshot()),panel.error)
			for frame in 3:await process_frame
			check(panel._portrait.texture!=null and panel._body.text==visit.snapshot().dialogue.text and panel._next.text==library.strings[180] and panel._previous.disabled,"Original result portrait, text or acknowledgement is missing")
			check(Rect2(Vector2.ZERO,Vector2(viewport.size)).encloses(panel._panel.get_rect()),"Result panel leaves the landscape viewport")
			check(panel._body.get_content_height()<=panel._body.size.y,"Original result text is clipped or requires scrolling")
			if args.size()==4 and DisplayServer.get_name()!="headless":
				await RenderingServer.frame_post_draw
				DirAccess.make_dir_recursive_absolute(args[3])
				check(viewport.get_texture().get_image().save_png(args[3].path_join("rescue-"+("failure" if failed else "success")+"-"+library.active_language+("-touch" if mobile else "-desktop")+".png"))==OK,"Could not capture result presentation")
		panel.set_active(false);check(panel._next.disabled and panel._previous.disabled,"A paused result can be acknowledged")
		panel.free()
		if library.active_language not in ["gb","de"]:continue
		var speech:=Speech.new();root.add_child(speech)
		if not speech.configure_campaign_result(library,bindings,21,Outcome.VALUES.mission,failed):check(false,speech.error);speech.free();continue
		check(speech._clips.size()==1 and (speech._clips[0]==null if failed else speech._clips[0].id==286),"Failure spoke or success used the wrong original voice")
		speech.set_paused(true)
		check(speech.present(0) and speech.snapshot().history.size()==(0 if failed else 1),"Wrong result voice history")
		var heard: Dictionary=speech.snapshot()
		check(speech.present(0) and speech.snapshot()==heard and not speech.present(1),"Result voice repeated or accepted an invented second page")
		speech.free()
	viewport.free()
