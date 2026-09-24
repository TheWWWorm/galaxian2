extends RefCounted
## Real-input flight pilot shared by selected tests and the earned application.
## Callbacks adopt each frame/navigation action in the caller's own session.

static func steering_toward(pose: Transform3D,point: Vector3) -> Vector2:
	var local: Vector3=pose.basis.inverse()*(point-pose.origin)
	var angles:=Vector2(-atan2(local.y,sqrt(local.x*local.x+local.z*local.z)),atan2(local.x,local.z))
	return Vector2(signf(angles.x)*sqrt(minf(absf(angles.x)*2.0,1.0)),signf(angles.y)*sqrt(minf(absf(angles.y)*2.0,1.0)))

static func enter_portal(frame: RefCounted,advance_flight: Callable,capture_frame: Callable,check: Callable,process_frame: Signal) -> RefCounted:
	var first: Dictionary=frame.snapshot()
	var cursor: int=int(first.campaign_cursor)
	if cursor not in [28,30]:check.call(false,"Expedition portal pilot requires Dima28 or acknowledged Void30");return null
	var initial_portal: Vector3=first.void_portal.position
	var radio_times:=[-1,-1,-1];var early_radio:=false;var released:=false;var relocated:=false
	var previous_radio_ms: int=int(first.world_phase_elapsed_ms)
	var previous_radio_started: bool=bool(first.radio.started[0])
	var first_radio_crossed_due:=false
	var closest:=INF
	for tick in 6000:
		var state: Dictionary=frame.snapshot()
		if frame.void_return_required():
			check.call(state.player.vitals.hull>0 and state.boundary=="void_return_transition_required" and state.campaign_cursor==cursor,"Expedition portal admitted the wrong or dead world")
			if cursor==28:
				check.call(released and not early_radio and first_radio_crossed_due,"Dima portal bypassed input release or source20s radio (observed starts "+str(radio_times)+", previous "+str(previous_radio_ms)+"ms, contact "+str(state.world_phase_elapsed_ms)+"ms)")
				check.call(state.radio.started==[true,true,true] and radio_times[1]>=radio_times[0] and radio_times[2]>=radio_times[1],"Dima portal lost its dependent radio rows (observed starts "+str(radio_times)+")")
				if state.world_phase_elapsed_ms>63000:check.call(relocated,"Dima portal did not recur before late contact")
				check.call(not state.dialogue.visible and state.dialogue.count==0 and state.progress==first.progress and state.cargo==first.cargo and state.equipment==first.equipment,"Dima portal fabricated a result or changed retained state")
			await capture_frame.call(null,frame,"dima-portal-contact" if cursor==28 else "void29-portal-contact")
			print("Expedition portal contact cursor ",cursor," at ",state.world_phase_elapsed_ms,"ms; distance ",int(state.player_pose.origin.distance_to(state.void_portal.position)),"; hull ",state.player.vitals.hull)
			return frame
		if frame.death_active() or state.player.vitals.hull<=0:
			check.call(false,"Expedition portal pilot died at tick "+str(tick)+" distance "+str(int(state.player_pose.origin.distance_to(state.void_portal.position))))
			return null
		var distance: float=state.player_pose.origin.distance_to(state.void_portal.position)
		closest=minf(closest,distance)
		if cursor==28:
			if state.void_portal.position!=initial_portal and not relocated:
				relocated=true
				check.call(state.void_portal.visible and state.void_portal.elapsed_ms<0,"Dima portal relocated without reopening")
				await capture_frame.call(null,frame,"dima-portal-reopened")
			if state.entry_released and not released:
				released=true
				check.call(state.player.damage_allowed and not state.dialogue.visible,"Dima pilot controls were not released")
				await capture_frame.call(null,frame,"dima-flight-release")
			for event in 3:
				if state.radio.started[event] and radio_times[event]<0:radio_times[event]=int(state.world_phase_elapsed_ms)
			if state.radio.started[0] and not previous_radio_started:
				first_radio_crossed_due=previous_radio_ms<20000 and int(state.world_phase_elapsed_ms)>=20000
				check.call(first_radio_crossed_due,"Dima first radio missed its source20s due frame (previous "+str(previous_radio_ms)+"ms unstarted, current "+str(state.world_phase_elapsed_ms)+"ms started)")
				print("Dima first radio due frame ",previous_radio_ms,"ms -> ",state.world_phase_elapsed_ms,"ms")
			if state.world_phase_elapsed_ms<20000 and state.radio.started[0]:early_radio=true
			previous_radio_ms=int(state.world_phase_elapsed_ms)
			previous_radio_started=bool(state.radio.started[0])
		if tick%200==0:print("Expedition portal tick ",tick," cursor ",cursor," distance ",int(distance)," closest ",int(closest)," hull ",state.player.vitals.hull)
		var throttle:=clampf(distance/14000.0,0.1,1.0) if cursor==28 else 0.0 if distance<1500.0 else 1.0
		var next: RefCounted=advance_flight.call(frame,100,steering_toward(state.player_pose,state.void_portal.position),throttle,false)
		if next==null:check.call(false,"Expedition portal frame "+str(tick)+": "+frame.error);return null
		frame=next
		if tick%20==0:await process_frame
	check.call(false,"Expedition pilot did not contact its native portal; closest "+str(int(closest)))
	return null

static func complete_probe(frame: RefCounted,advance_flight: Callable,capture_frame: Callable,check: Callable,process_frame: Signal,navigate: Callable,on_phase2: Callable=Callable()) -> RefCounted:
	var initial: Dictionary=frame.snapshot()
	if initial.campaign_cursor!=29 or not initial.has("void_probe_stage") or not initial.has("void_station_targeting"):
		check.call(false,"Probe pilot requires the live selected Void29 frame")
		return null
	var station: Dictionary=frame.void_environment_owner().object_state(0)
	if station.get("kind")!="station" or not station.get("pose") is Transform3D:
		check.call(false,"Probe pilot lacks its live mother ship in environment slot0")
		return null
	var previous_phase:=-1;var sound_starts:=0;var phase2_observed:=false;var briefing_seen:=false;var strict_boundary_seen:=false
	var flank: Vector3=station.pose.origin+Vector3(200000,160000,250000)
	for tick in 2400:
		var state: Dictionary=frame.snapshot();var stage: Dictionary=state.void_probe_stage
		for cue in stage.frame.cues:
			if cue.kind=="sound_start" and cue.event_id==14:sound_starts+=1
		if stage.phase!=previous_phase:
			previous_phase=stage.phase
			print("Live probe phase ",stage.phase," at world ",state.world_phase_elapsed_ms,"ms, stage ",stage.stage_elapsed_ms,"ms, hull ",state.player.vitals.hull)
			if stage.phase==1:
				var lock: Dictionary=state.void_station_targeting
				check.call(lock.scanner_id==81 and lock.mother_ship_locked and lock.elapsed_ms>lock.duration_ms and lock.duration_ms==4000,"Probe phase1 bypassed the installed scanner81 lock")
				check.call(not stage.hud_visible and not stage.damage_enabled and stage.input_blocked and stage.scripted_camera and state.void_probe.visible,"Probe phase1 lost its scripted camera, model or safety gates")
				check.call(stage.frame.cues.any(func(cue):return cue.kind=="camera_eye") and stage.frame.cues.any(func(cue):return cue.kind=="sound_start" and cue.event_id==14),"Probe phase1 missed its one-shot camera/sound14 cues")
				await capture_frame.call(null,frame,"void29-probe-live-phase1")
			elif stage.phase==2:
				phase2_observed=true
				check.call(stage.stage_elapsed_ms==0 and state.radio.finished[1] and not stage.input_blocked and stage.damage_enabled and stage.hud_visible and not state.void_probe.visible,"Probe phase2 did not reset its source clock and restore flight")
				check.call(stage.frame.cues.any(func(cue):return cue.kind=="probe_despawn") and stage.frame.cues.any(func(cue):return cue.kind=="camera_scripted" and not cue.enabled),"Probe phase2 missed its one-shot despawn/camera restoration")
				if on_phase2.is_valid():on_phase2.call(frame)
				await capture_frame.call(null,frame,"void29-probe-live-phase2")
		if state.dialogue.visible:
			if state.mining_objective.phase=="return_instructions":
				check.call(briefing_seen and phase2_observed and sound_starts==1 and strict_boundary_seen and stage.stage_elapsed_ms>180000 and state.mining_objective.mission_completed and state.player.vitals.hull>0,"Probe result bypassed its briefing, one-shot cues, strict phase2 timer or living player")
				check.call(state.dialogue.count==1 and state.dialogue.voice_event_id==326 and state.dialogue.text_id in [1943,1929],"Probe result selected another source text or voice")
				await capture_frame.call(null,frame,"void29-probe-live-result")
				print("Live probe result at world ",state.world_phase_elapsed_ms,"ms, phase2 ",stage.stage_elapsed_ms,"ms, hull ",state.player.vitals.hull)
				return frame
			check.call(not briefing_seen and state.dialogue.count==1 and state.dialogue.voice_event_id==176 and state.dialogue.text_id in [1936,1922],"Probe briefing changed its source line or opened twice")
			if briefing_seen:return null
			briefing_seen=true
			var acknowledged: RefCounted=navigate.call(frame,"next")
			if acknowledged==null:check.call(false,"Probe briefing acknowledgement failed");return null
			frame=acknowledged
			continue
		if frame.death_active() or state.player.vitals.hull<=0:
			check.call(false,"Probe pilot died at world "+str(state.world_phase_elapsed_ms)+"ms, phase "+str(stage.phase))
			return null
		if stage.phase==2 and stage.stage_elapsed_ms==180000:
			strict_boundary_seen=true
			check.call(state.mining_objective.phase=="collecting" and not state.mining_objective.mission_completed,"Probe result opened at the inclusive180s boundary")
		if tick%200==0:print("Live probe tick ",tick," phase ",stage.phase," stage ",stage.stage_elapsed_ms," hull ",state.player.vitals.hull)
		var destination: Vector3=station.pose.origin
		var throttle:=1.0
		if stage.phase==1:throttle=0.0
		elif stage.phase==2:
			destination=state.player_pose.origin+Vector3(0,0,1000000) if stage.stage_elapsed_ms<60000 else flank
			throttle=0.0 if state.player_pose.origin.distance_to(destination)<1500.0 else 1.0
		var next: RefCounted=advance_flight.call(frame,100,steering_toward(state.player_pose,destination),throttle,false)
		if next==null:check.call(false,"Probe flight frame "+str(tick)+": "+frame.error);return null
		frame=next
		if tick%20==0:await process_frame
	check.call(false,"Live probe pilot did not reach its original result")
	return null

static func pre_ack_portal_contact(frame: RefCounted,advance_flight: Callable,check: Callable,process_frame: Signal) -> RefCounted:
	for tick in 600:
		var state: Dictionary=frame.snapshot()
		if state.campaign_cursor!=29 or state.void_probe_stage.phase!=2 or state.dialogue.visible or state.player.vitals.hull<=0:
			check.call(false,"Pre-Next contact branch lost its live unfinished Void29 flight")
			return null
		var distance: float=state.player_pose.origin.distance_to(state.void_portal.position)
		if distance<999.0:
			check.call(not frame.void_return_required() and not state.void_portal_contact.portal_entered and not state.void_portal_contact.contact.is_empty(),"Selected29 portal admitted physical contact before final Next")
			print("Live pre-Next portal contact at world ",state.world_phase_elapsed_ms,"ms, distance ",int(distance)," hull ",state.player.vitals.hull)
			return frame
		var next: RefCounted=advance_flight.call(frame,100,steering_toward(state.player_pose,state.void_portal.position),1.0,false)
		if next==null:check.call(false,"Pre-Next portal frame "+str(tick)+": "+frame.error);return null
		frame=next
		if tick%20==0:await process_frame
	check.call(false,"Live selected29 branch did not reach the portal before its first closure")
	return null
