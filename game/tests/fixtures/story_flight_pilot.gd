extends RefCounted
## Shared native-test control pilot for the authored Void fighters and cargo.

static func recover_void_cargo(frame: RefCounted,scene: Node3D,advance_flight: Callable,capture_frame: Callable,check: Callable,process_frame: Signal,collect:=true) -> RefCounted:
	var equipment: Dictionary=frame.snapshot().get("tractor",{})
	if collect and (equipment.get("equipment_id",-1)<0 or equipment.get("scanner_id",-1)<0):
		check.call(false,"Shipwreck recovery needs both an installed tractor and scanner")
		return null
	var target_id:=-1;var preceding: Variant=null;var beam_captured:=false
	for tick in 3000:
		var state: Dictionary=frame.snapshot()
		if collect and state.encounter.combat.get("recovery",{}).get("accepted_quantity",0)>=3:
			await capture_frame.call(scene,frame,"sahi-cargo-collected")
			return frame
		var actors: Array=state.encounter.combat.actors
		var living: Array=actors.filter(func(actor):return actor.actor_kind==9 and actor.vitals.hull>0)
		if not collect and living.is_empty():
			await capture_frame.call(scene,frame,"void-fighters-defeated")
			return frame
		var recovering:=living.is_empty()
		if target_id<0 or (not recovering and actors[target_id].vitals.hull<=0) or (recovering and state.encounter.controller.destruction[target_id].cargo.entries.is_empty()):
			var candidates: Array=living if not recovering else actors.filter(func(actor):return actor.actor_kind==9 and not state.encounter.controller.destruction[actor.actor_id].cargo.entries.is_empty())
			candidates.sort_custom(func(a,b):return a.position.distance_squared_to(state.player_pose.origin)<b.position.distance_squared_to(state.player_pose.origin))
			if candidates.is_empty():check.call(false,"Sahi generated no remaining recoverable Void cargo");return null
			target_id=candidates[0].actor_id;preceding=null
		var target: Dictionary=actors[target_id]
		var offset: Vector3=target.position-state.player_pose.origin
		if recovering:
			var wreck: Dictionary=state.encounter.controller.destruction[target_id]
			offset=wreck.cargo.pose.origin-state.player_pose.origin
		var aim:=offset
		if not recovering and preceding!=null:
			var speed: float=state.encounter.primaries.guns[0].projectiles.weapon.speed_units_per_millisecond
			aim+=(target.position-preceding)/100.0*minf(offset.length()/speed,2000.0)
		preceding=target.position
		var local: Vector3=state.player_pose.basis.inverse()*aim
		var angles:=Vector2(-atan2(local.y,sqrt(local.x*local.x+local.z*local.z)),atan2(local.x,local.z))
		var commands:=Vector2(signf(angles.x)*sqrt(minf(absf(angles.x)*2.0,1.0)),signf(angles.y)*sqrt(minf(absf(angles.y)*2.0,1.0)))
		var throttle:=1.0 if offset.length()>(2500.0 if recovering else 6000.0) else 0.0
		var next: RefCounted=advance_flight.call(frame,100,commands,throttle,not recovering and offset.length()<22000 and angles.length()<.15)
		if next==null:check.call(false,frame.error);return null
		frame=next
		if frame.death_active():check.call(false,"Sahi recovery pilot died during the native battle");return null
		if not beam_captured and frame.snapshot().tractor_frame.get("phase")=="pulling":
			await capture_frame.call(scene,frame,"sahi-tractor-beam");beam_captured=true
		if tick%200==0:print("Sahi pilot tick ",tick," target ",target_id," distance ",int(offset.length())," target hull ",target.vitals.hull," player hull ",state.player.vitals.hull," cargo ",state.cargo_used)
		if tick%20==0:await process_frame
	check.call(false,"Native pilot did not finish its Void combat/recovery objective")
	return null

static func enter_sahi_portal(frame: RefCounted,scene: Node3D,advance_flight: Callable,capture_frame: Callable,check: Callable,process_frame: Signal) -> RefCounted:
	var observed_phase:=-1;var held: Dictionary=frame.snapshot().cargo
	for tick in 1200:
		var state: Dictionary=frame.snapshot();var stage: Dictionary=state.sahi_stage
		if frame.sahi_arrival_required():
			check.call(state.cargo==held and state.player.vitals.hull>0,"Sahi portal lost recovered cargo or accepted a dead player")
			check.call(observed_phase==2 and state.boundary=="sahi_arrival_transition_required","Sahi did not complete its actual portal stages")
			await capture_frame.call(scene,frame,"sahi-portal-entry")
			print("Sahi portal entered at ",state.world_phase_elapsed_ms,"ms with ",state.cargo_used," cargo units")
			return frame
		if stage.phase!=observed_phase:
			observed_phase=stage.phase
			print("Sahi cinematic phase ",stage.phase," at ",state.world_phase_elapsed_ms,"ms")
			if stage.phase>0:await capture_frame.call(scene,frame,"sahi-portal-stage-"+str(stage.phase))
			if stage.phase==1:
				check.call(not state.player.damage_allowed and not stage.hud_visible and stage.input_blocked,"Sahi portal view did not disable damage and controls")
				check.call(frame._encounter._weapons._training.target_memberships.all(func(ids):return ids.is_empty()),"Sahi view retained NPC weapon targets")
		var commands:=Vector2.ZERO
		if stage.phase==2:
			var local: Vector3=state.player_pose.basis.inverse()*(state.sahi_portal.position-state.player_pose.origin)
			var angles:=Vector2(-atan2(local.y,sqrt(local.x*local.x+local.z*local.z)),atan2(local.x,local.z))
			commands=Vector2(signf(angles.x)*sqrt(minf(absf(angles.x)*2.0,1.0)),signf(angles.y)*sqrt(minf(absf(angles.y)*2.0,1.0)))
		var next: RefCounted=advance_flight.call(frame,100,commands,1.0)
		if next==null:check.call(false,frame.error);return null
		frame=next
		if tick%20==0:await process_frame
	check.call(false,"Sahi flight did not enter its generated portal")
	return null
