extends "res://tests/kappa_preparation_application.gd"
## Earned station entry and live rescue composition. Further encounter scenarios
## use this same session, inventory, radio and acknowledged result owner.

func verify_free_application() -> void:
	var station: Dictionary=app.session.station_owner().snapshot()
	print("Earned Kappa resume: cursor ",station.campaign_cursor," station ",station.loadout.station_id," credits ",station.contracts.credits)
	if not station.campaign_cursor in [21,23]:
		await super.verify_free_application()
		return
	chapter_directory=OS.get_environment("GOF2_SAVE_TEST_DIRECTORY")
	if chapter_directory.is_empty():check(false,"Set a private chapter save directory");return
	app.enable_saves(chapter_directory)
	app.show();app.present_session();await process_frame;resume_application_focus()
	retained_job=station.contracts.mission.duplicate(true)
	if station.campaign_cursor==21:await after_kappa_fitting(station)
	else:await fly_onward()

func after_kappa_fitting(ready: Dictionary) -> void:
	if not app.request_departure() or not app.enter_first_flight(now_us,4096,1789100000):check(false,app.status.text);return
	await after_kappa_launch(ready)

func after_kappa_launch(ready: Dictionary) -> void:
	var entry: Dictionary=app.session.snapshot()
	check(entry.campaign_cursor==21 and entry.location.station_id==55 and entry.encounter.combat.actors.size()==4 and entry.player_route.waypoints.size()==2,"The earned rescue lost its authored world, cast or route")
	check(entry.contracts.credits==ready.contracts.credits and entry.contracts.mission==retained_job and entry.contracts.passengers==3,"Rescue departure changed the retained wallet or passengers")
	check(not app._flight_actions.visible and not app.touch_overlay.visible,"Desktop rescue ignored hidden touch controls")
	var shown:=[]
	for tick in 180:
		var current: Dictionary=app.session.snapshot()
		if current.dialogue.visible:
			shown.append(current.dialogue.text_id)
			await capture_free_application("kappa-rescue-instruction-%d"%current.dialogue.text_id)
			var frozen: Dictionary=app.session.snapshot()
			if not application_step():return
			check(app.session.snapshot().world_elapsed_ms==frozen.world_elapsed_ms,"The acknowledged rescue lesson advanced simulation time")
			if not app.session.navigate("next"):check(false,app.session.error);return
		elif app.session.can_control() and shown.size()==2:break
		if not application_step():return
	var expected: Dictionary=load("res://src/content/kappa_rescue_definitions.gd").presentation_briefing(definitions)
	check(shown==expected.events.map(func(event):return int(event.text_id)) and app.session.can_control(),"The rescue omitted an original briefing/instruction or kept controls frozen: "+str(shown))
	check(app.session.snapshot().campaign_cursor==21 and app.session.snapshot().contracts.credits==ready.contracts.credits,"The briefing granted rescue progress or rewards")
	if not app.open_secondary_menu(now_us):check(false,app.status.text);return
	app.secondary_panel.handle_selection_event(gate_key_event(KEY_DOWN,true))
	if not app.confirm_secondary_selection(41,now_us):check(false,app.status.text);return
	check(app.session.snapshot().encounter.selected_secondary==41 and app.session.snapshot().encounter.secondaries.guns[0].ammunition==10,"The original weapons menu did not select the installed EMP without firing it")
	await capture_free_application("kappa-rescue-flight")
	print("Earned rescue launch, four native actors, original modal briefing/instruction and released flight controls")
	if failures:return
	await fly_rescue(ready)

func fly_rescue(ready: Dictionary) -> void:
	var first_point: Vector3=app.session.snapshot().player_route.waypoints[0]
	var pulses:=0
	var prior_positions:={}
	var previous_ms:=-1
	var escape_goal: Variant=null
	var voices:=[]
	for tick in 2400:
		resume_application_focus()
		var state: Dictionary=app.session.snapshot()
		if state.dialogue.visible:
			check(state.phase=="campaign_visit" and state.mining_objective.campaign_visit.outcome=="completed","The rescue failed during normal guided flight: "+str(state.dialogue))
			break
		var radio: Dictionary=state.radio
		if radio.get("visible",false) and not voices.has(radio.get("event_index",-1)):
			voices.append(radio.get("event_index",-1))
		var target: Dictionary=state.encounter.combat.actors[0]
		if state.player_route.index>0:
			var escorts: Array=state.encounter.combat.actors.slice(1).filter(func(actor):return actor.vitals.hull>0)
			escorts.sort_custom(func(a,b):return a.position.distance_squared_to(state.player_pose.origin)<b.position.distance_squared_to(state.player_pose.origin))
			if not escorts.is_empty():target=escorts[0]
		if state.player_route.index>0 and target.actor_id==0 and target.systems_disabled and escape_goal==null:escape_goal=target.position+Vector3(25000,25000,20000)
		var goal: Vector3=first_point if state.player_route.index==0 else (escape_goal if escape_goal!=null else target.position)
		var offset: Vector3=goal-state.player_pose.origin
		var aim_offset:=offset
		if escape_goal==null and state.player_route.index>0 and target.actor_id==0 and offset.length()>18000:
			aim_offset+=Vector3(sin(float(tick)*.1)*12000,cos(float(tick)*.1)*12000,0)
		if state.player_route.index>0 and target.actor_id!=0 and prior_positions.has(target.actor_id) and state.world_elapsed_ms>previous_ms:
			var velocity: Vector3=(target.position-prior_positions[target.actor_id])/float(state.world_elapsed_ms-previous_ms)
			var speed: float=state.encounter.primaries.guns[0].projectiles.weapon.speed_units_per_millisecond
			aim_offset+=velocity*minf(offset.length()/speed,2000.0)
		for actor in state.encounter.combat.actors:prior_positions[actor.actor_id]=actor.position
		previous_ms=state.world_elapsed_ms
		var local: Vector3=state.player_pose.basis.inverse()*aim_offset
		var angles:=Vector2(-atan2(local.y,sqrt(local.x*local.x+local.z*local.z)),atan2(local.x,local.z))
		var command:=Vector2(signf(angles.x)*sqrt(minf(absf(angles.x)*2.0,1.0)),signf(angles.y)*sqrt(minf(absf(angles.y)*2.0,1.0)))
		if escape_goal==null and state.player_route.index>0 and target.actor_id==0 and offset.length()>18000:
			command=(command+Vector2(sin(float(tick)*.07),cos(float(tick)*.07))*.8).clamp(Vector2(-1,-1),Vector2.ONE)
		var desired:=1.0 if escape_goal!=null or state.player_route.index==0 or offset.length()>(6000.0 if target.actor_id==0 else 14000.0) else 0.0
		while absf(float(app.session.snapshot().input_throttle)-desired)>.05:
			if not app.session.action("throttle_down" if app.session.snapshot().input_throttle>desired else "throttle_up"):check(false,app.session.error);return
		var gun: Dictionary=state.encounter.secondaries.guns[0]
		var bomb: Dictionary=gun.bomb
		var near: bool=offset.length()<(7000.0 if target.actor_id==0 else float(bomb.weapon.radius)*.6+400)
		if state.player_route.index>0 and near and angles.length()<.7 and not target.systems_disabled and (bomb.shot.get("phase")=="flying" or (gun.ammunition>0 and bomb.elapsed_ms>bomb.weapon.interval_ms)):
			if not app.session.action("missiles"):check(false,app.session.error);return
			if bomb.shot.get("phase")=="flying":pulses+=1
		if state.player_route.index>0 and target.actor_id==0 and offset.length()<20000 and tick%20==0:print("Rescue target approach: distance ",int(offset.length())," systems ",target.systems," disabled ",target.systems_disabled," ammo ",gun.ammunition," shot ",bomb.shot.get("phase")," pools ",state.player.vitals)
		now_us+=100000
		var fire_primary: bool=state.player_route.index>0 and target.actor_id!=0 and offset.length()<24000 and angles.length()<.2
		if not app.session.step(now_us,command,fire_primary):check(false,app.session.error);return
		if tick%200==0:print("Kappa flight ",tick," route ",state.player_route.index," target ",target.actor_id," distance ",int(offset.length())," pools ",state.player.vitals," target pools ",target.vitals," radio ",radio.get("started")," EMP ",pulses)
		if tick%20==0:await process_frame
		if app.session.flight_owner().death_active():check(false,"The guided rescue player died before its acknowledgement: tick %d, target %d, distance %d, prior hull %d"%[tick,target.actor_id,int(offset.length()),state.player.vitals.hull]);return
	var completed: Dictionary=app.session.snapshot()
	check(completed.dialogue.visible and completed.mining_objective.campaign_visit.outcome=="completed" and completed.radio.finished.all(func(value):return value),"The live route/radio/EMP sequence did not produce an acknowledged result")
	if failures:return
	check(completed.campaign_cursor==21 and completed.contracts.credits==ready.contracts.credits,"The success panel granted campaign progress before acknowledgement")
	await capture_free_application("kappa-rescue-success")
	if not app.session.navigate("next"):check(false,app.session.error);return
	var acknowledged: Dictionary=app.session.snapshot()
	check(acknowledged.campaign_cursor==22 and acknowledged.mission.kind==11 and acknowledged.mission.station_id==55 and acknowledged.contracts.credits==ready.contracts.credits,"Acknowledged rescue lost its return mission or awarded an unearned payment")
	if failures or not await clear_return_attacker() or not await dock_application():return
	var landed: Dictionary=app.session.station_owner().snapshot()
	check(landed.campaign_cursor==22 and landed.loadout.station_id==55 and landed.contracts.mission==retained_job and landed.contracts.passengers==3,"The rescued return lost its earned mission or passengers")
	if failures or not await acknowledge_station_chapter(22):return
	if not retain_chapter_save("kappa23-coordinates"):return
	print("Actual Kappa21 steering/EMP/radio -> acknowledged22 -> native station return")
	await fly_onward()

func clear_return_attacker(actor_id: int=0) -> bool:
	# Fight one live attacker using steering, remaining installed EMP rounds
	# and ordinary primary fire. The rescue and travel acceptance paths share it.
	resume_application_focus();app.session.rebase_time(now_us)
	var previous: Variant=null
	for tick in 900:
		resume_application_focus()
		var state: Dictionary=app.session.snapshot()
		var target: Dictionary=state.encounter.combat.actors[actor_id]
		if target.vitals.hull<=0:return true
		var offset: Vector3=target.position-state.player_pose.origin
		var aim:=offset
		if previous!=null:
			var speed: float=state.encounter.primaries.guns[0].projectiles.weapon.speed_units_per_millisecond
			aim+=(target.position-previous)/100.0*minf(offset.length()/speed,2000.0)
		previous=target.position
		var local: Vector3=state.player_pose.basis.inverse()*aim
		var angles:=Vector2(-atan2(local.y,sqrt(local.x*local.x+local.z*local.z)),atan2(local.x,local.z))
		var command:=Vector2(signf(angles.x)*sqrt(minf(absf(angles.x)*2.0,1.0)),signf(angles.y)*sqrt(minf(absf(angles.y)*2.0,1.0)))
		var desired:=1.0 if offset.length()>6000 else 0.0
		while absf(float(app.session.snapshot().input_throttle)-desired)>.05:
			if not app.session.action("throttle_up" if desired>0 else "throttle_down"):check(false,app.session.error);return false
		var gun: Dictionary=state.encounter.secondaries.guns[0]
		var bomb: Dictionary=gun.bomb
		if offset.length()<7000 and angles.length()<.7 and not target.systems_disabled and (bomb.shot.get("phase")=="flying" or (gun.ammunition>0 and bomb.elapsed_ms>bomb.weapon.interval_ms)):
			if not app.session.action("missiles"):check(false,app.session.error);return false
		now_us+=100000
		if not app.session.step(now_us,command,offset.length()<24000 and angles.length()<.2):check(false,app.session.error);return false
		if app.session.flight_owner().death_active():check(false,"The rescue return pilot died fighting the surviving attacker");return false
		if tick%100==0:print("Rescue return combat: ",tick," distance ",int(offset.length())," enemy hull ",target.vitals.hull," player hull ",state.player.vitals.hull," rounds ",gun.ammunition)
		if tick%20==0:await process_frame
	check(false,"The rescue return pilot never defeated the surviving attacker")
	return false

func fly_onward() -> void:
	var before: Dictionary=app.session.station_owner().snapshot()
	check(before.campaign_cursor==23 and before.loadout.station_id in [55,35,10],"Use an earned Kappa, Aquila or Deep Science coordinate checkpoint")
	if failures:return
	if before.loadout.station_id==55:
		if not retain_chapter_save("kappa23-coordinates-departure"):return
		if not await visit_gate(7,35) or not await release_application_flight():return
		check(not app.session.snapshot().dialogue.visible and app.session.snapshot().campaign_cursor==23,"The intermediate system consumed the selected Deep Science conversation")
		if failures or not await follow_gate_course(6,10):return
	elif before.loadout.station_id==35:
		if not await visit_gate(6,10):return
	if before.loadout.station_id!=10:
		var briefing: Dictionary=definitions.mido_travel.kappa_return.arrival_briefing
		for tick in 140:
			if app.session.snapshot().dialogue.visible:break
			if not application_step():return
		for event in briefing.events:
			var state: Dictionary=app.session.snapshot()
			check(state.campaign_cursor==23 and state.location.station_id==10 and state.dialogue.visible and state.dialogue.text_id==int(event.text_id) and state.dialogue.voice_event_id==int(event.voice_event_id),"Deep Science arrival lost its selected original briefing")
			if failures:return
			await capture_free_application("kappa-arrival-%d"%int(event.text_id))
			if not app.session.navigate("next"):check(false,app.session.error);return
		if not await dock_application():return
	var landed: Dictionary=app.session.station_owner().snapshot()
	check(landed.campaign_cursor==23 and landed.loadout.station_id==10 and landed.contracts.credits==before.contracts.credits,"Arrival granted the return payment before station acknowledgement")
	if failures or not await acknowledge_station_chapter(23):return
	if not retain_chapter_save("kappa24-sahi-pending"):return
	var final: Dictionary=app.session.station_owner().snapshot()
	check(final.contracts.credits==before.contracts.credits+20000 and final.campaign_cursor==24 and final.mission.station_id==48,"The actual return lost its original payment or pending Sahi objective")
	if failures:return
	await verify_deep_science_services(final)
	print("Actual Kappa23 gate route11->7->6, original arrival/station acknowledgements, paid20000 and retained24 save")

func verify_deep_science_services(earned: Dictionary) -> void:
	var contacts: Array=earned.contracts.population.contacts
	check(contacts.size() in [4,5] and contacts[0].get("source_contact_id")==int(definitions.persistent_contacts.supported_contact_ids[0]) and contacts[0].get("generated")==false,"Deep Science lost its original first lounge contact")
	if failures:return
	if not app.contract_action("open",-1):check(false,app.status.text);return
	var contact: Dictionary=contacts[0]
	app.lounge_panel.select_contact(int(contact.contact_id))
	check(app.lounge_panel.visible and app.lounge_panel._name.text==contact.name and app.lounge_panel._portrait.texture!=null,"The authored lounge contact lost its original name or portrait")
	check(not app.lounge_panel.snapshot().accept_visible,"An unsupported blueprint service exposed a purchase action")
	app.lounge_panel.confirm()
	check(app.session.station_owner().snapshot().contracts.credits==earned.contracts.credits,"The guarded authored service changed the wallet")
	await capture_free_application("deep-science-lounge")
	if not app.contract_action("close",-1):check(false,app.status.text);return
	if not app.equipment_action("open"):check(false,app.status.text);return
	check(app.equipment_panel.visible and app.session.snapshot().hangar_open,"Deep Science's actual hangar did not open")
	await capture_free_application("deep-science-hangar")
	if not app.equipment_action("close"):check(false,app.status.text);return
	var after: Dictionary=app.session.station_owner().snapshot()
	for field in ["credits","mission","passengers","progress"]:
		check(after.contracts[field]==earned.contracts[field],"Browsing Deep Science services changed retained "+field)
	check(after.mission==earned.mission and after.cargo==earned.cargo and after.loadout==earned.loadout,"Deep Science services changed the story or ship")
	if not app.load_station(now_us):check(false,app._save_notice.text);return
	check(app.session.station_owner().snapshot()==after,"Deep Science service-exit autosave changed the paid continuation")

func acknowledge_station_chapter(cursor: int) -> bool:
	var before: Dictionary=app.session.station_owner().snapshot()
	var rules: Dictionary=load("res://src/content/free_campaign_definitions.gd").dialogue_rules(definitions,cursor,before.mission,true)
	if rules.is_empty():check(false,"Missing original station chapter");return false
	app.session.rebase_time(now_us)
	for tick in 65:
		if app.session.snapshot().dialogue.visible:break
		now_us+=100000
		if not app.session.step(now_us):check(false,app.session.error);return false
	for event in rules.events:
		var current: Dictionary=app.session.snapshot()
		check(current.campaign_cursor==cursor and current.dialogue.visible and current.dialogue.text_id==int(event.text_id) and current.dialogue.voice_event_id==int(event.voice_event_id),"The station chapter lost original text, voice or acknowledgement order")
		check(current.contracts.credits==before.contracts.credits and current.loadout==before.loadout and current.cargo==before.cargo,"An intermediate station line changed payment, cargo or equipment")
		var speech: Dictionary=app.session.audio.snapshot()
		var voiced: bool=int(event.voice_event_id)>=0
		var correct_voice: bool=not speech.history.is_empty() and speech.history.back().source_id==int(event.voice_event_id) if voiced else app.session.audio._player==null
		check(speech.line==current.dialogue.index and correct_voice,"The station chapter changed its original voice or silent instruction: "+str({"text":event.text_id,"voice":event.voice_event_id,"line":speech.line,"history":speech.history}))
		if failures:return false
		if event==rules.events[0] or event==rules.events[-1]:await capture_free_application("campaign-station-%d"%int(event.text_id))
		resume_application_focus()
		app.station_navigation("next")
	var after: Dictionary=app.session.station_owner().snapshot()
	var equal=load("res://src/content/opening_escape_definitions.gd")
	check(after.campaign_cursor==int(rules.next_cursor) and equal.equal_value(after.mission,rules.next_mission) and after.contracts.credits==before.contracts.credits+int(rules.reward_credits),"The station acknowledgement changed its original mission or payment: "+str({"cursor":after.campaign_cursor,"mission":after.mission,"expected_mission":rules.next_mission,"credits":after.contracts.credits,"expected_credits":before.contracts.credits+int(rules.reward_credits),"phase":after.phase,"session_error":app.session.error,"status":app.status.text}))
	check(after.contracts.mission==retained_job and after.contracts.passengers==3,"The station chapter lost accepted passengers")
	return failures==0
