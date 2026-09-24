extends "res://tests/combat_training_flight.gd"
## Uses the native training encounter, docking and station reload. Existing
## combat/docking fixtures disclose direct damage and close placement; this
## verifies the following conversation and preparation, not a full journey.
const LocalTrip=preload("res://src/simulation/local_travel.gd")
const LocalCache=preload("res://src/simulation/flight_player_cache.gd")
const LocalControl=preload("res://src/simulation/combat_training_control.gd")
const LocalDestruction=preload("res://src/content/npc_destruction_resources.gd")
var local_departure_verified:=false
var local_packet:={}
var local_equipment: RefCounted

func run():
	var args:=training_arguments()
	check(args.size() in [3,4],"Expected explicit Mac content, bindings, visuals and optional captures")
	if args.size() in [3,4]:verify(args.slice(0,3))
	check(local_departure_verified,"The native training return did not reach local departure verification")
	if is_instance_valid(training_scene):training_scene.free()
	if is_instance_valid(training_sound):training_sound.free()
	if failures==0 and not local_packet.is_empty():await verify_local_session(args)
	if is_instance_valid(host):host.free()
	print("Mido station departure: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)

func after_training_reload(cat: RefCounted, station: RefCounted):
	if bindings.mido_travel.is_empty():
		check(not station.begin_local_conversation(bindings,cat,lib),"Earlier bindings invented the local conversation")
		local_departure_verified=true;return
	var before: Dictionary=station.snapshot()
	check(before.progress.get("reputation")=={"axes":[30,-6],"override":-1},"Earned training return lost the six actual player lethal hits")
	var prepared: RefCounted=station.fork()
	check(prepared.begin_local_conversation(bindings,cat,lib),prepared.error)
	if not prepared.snapshot().get("local_conversation",false):return
	check(station.snapshot()==before and prepared.snapshot().equipment==before.equipment,"Conversation preparation applied the future equipment exchange")
	for i in 11:
		var line: Dictionary=prepared.snapshot()
		check(line.campaign_cursor==9 and line.dialogue.text_id==int(bindings.mido_travel.conversations[0].events[i].text_id) and line.equipment==before.equipment,"A local line advanced progress or exchanged equipment early")
		check(prepared.prepare_departure(bindings,cat).is_empty(),"Local conversation launched before final acknowledgement")
		if i==1:
			check(prepared.previous() and prepared.snapshot().dialogue.text_id==int(bindings.mido_travel.conversations[0].events[0].text_id),"Local dialogue lost previous-line navigation")
			check(prepared.acknowledge() and prepared.snapshot().dialogue.text_id==int(bindings.mido_travel.conversations[0].events[1].text_id),"Local dialogue lost explicit next-line navigation")
		check(prepared.acknowledge(),prepared.error)
	var ready: Dictionary=prepared.snapshot()
	check(ready.phase=="local_departure_required" and ready.campaign_cursor==10 and ready.acknowledged and ready.local_conversation_acknowledged,"The completed local conversation did not select departure")
	check(ready.mission=={"kind":11,"station_id":79,"reward":0,"bonus":0,"source_parameter":0} and ready.reward_credits==0,"Local conversation changed its Kernstal visit or granted a reward")
	check(ready.progress.rank_score==before.progress.rank_score+1 and ready.progress.player_kills==before.progress.player_kills and ready.progress.pirate_kills==before.progress.pirate_kills,"Local conversation changed kill credit or counted its cursor twice")
	check(ready.progress.reputation==before.progress.reputation,"Dialogue or drill exchange changed retained faction reputation")
	check(ready.loadout.equipment_ids==[22,86,81,55] and ready.cargo==before.cargo and ready.equipment.credit_delta==before.equipment.credit_delta,"Local exchange discarded cargo, credits or unrelated equipment")
	check(LocalCache.matches(ready.player_cache,ready.loadout,10) and ready.player_cache.values==before.player_cache.values,"Station exchange changed retained arrival pools")
	check(not prepared.acknowledge() and not prepared.begin_local_conversation(bindings,cat,lib) and prepared.snapshot()==ready,"The local exchange or conversation could be applied twice")
	var packet: Dictionary=prepared.prepare_departure(bindings,cat)
	check(not packet.is_empty(),prepared.error)
	if packet.is_empty():return
	check(packet.size()==18 and packet.confirmation_required and packet.confirmation_text_id==386,"Local departure lost the ordinary launch confirmation")
	check(packet.progress==ready.progress and packet.mission==ready.mission and packet.equipment==ready.equipment and packet.cargo==ready.cargo,"Local departure changed the acknowledged station state")
	check(packet.player.vitals.hull==95 and packet.player.vitals.armor==40 and packet.player.vitals.shield==0 and packet.player.gamma==100,"Local departure omitted its ordinary pool reset")
	var equipment: RefCounted=prepared.equipment_owner()
	local_packet=packet.duplicate(true);local_equipment=prepared.equipment_owner()
	var bodies:=PreparedBodies.new();var effects:=PreparedEffects.new()
	if not bodies.configure(lib,bindings) or not effects.configure(lib,bindings):check(false,bodies.error+effects.error);return
	var construction:=PreparedTraining.new()
	check(construction.prepare(bindings,cat,packet,1789100000,1789100000,true,bodies,effects,equipment),construction.error)
	var world: Dictionary=construction.snapshot()
	if world.is_empty():return
	check(world.campaign_cursor==10 and world.world_type==3 and world.location.station_id==78 and world.player_pose.origin==Vector3(10,10,10000),"Local departure changed the ordinary world or player placement")
	check(world.scenery.world_initialization.npc_construction.actors.size()==1 and world.scenery.world_initialization.npc_construction.actors[0].hull_catalogue_id==19,"Local departure reused the training encounter or the empty arrival cast")
	check(construction.equipment_owner().snapshot()==ready.equipment and prepared.snapshot()==ready and station.snapshot()==before,"Detached local construction mutated an accepted station")
	var traffic:=LocalControl.new();var death:=LocalDestruction.new()
	var population: RefCounted=construction.scenery_owner().world_initialization_owner()
	check(traffic.configure_local_traffic(bindings,cat,population,int(packet.progress.rank),0.5,construction.equipment_owner(),packet.progress.reputation),traffic.error)
	check(death.configure_local_traffic(lib,bindings) and traffic.set_destruction(bindings,death),death.error+traffic.error)
	if traffic.snapshot().is_empty():return
	check(traffic.combat_owner().current_reputation()==packet.progress.reputation,"Traffic replaced the actual station career reputation")
	var target:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"ship_id":int(world.player.ship_id),
		"pose":world.player_pose,"active":world.player.active,"hull":int(world.player.vitals.hull),
		"special_flight":false,"targeting_blocked":false,"alternate_position":null}
	var flight:=traffic.advance(0,target)
	check(not flight.is_empty(),traffic.error)
	check(not flight.is_empty() and flight.firing_requests.is_empty() and not flight.combat.actors[0].hostile,"Retained reputation made fresh local traffic attack the player")
	var altered: Dictionary=packet.duplicate(true);altered.mission.station_id=78
	check(not construction.prepare(bindings,cat,altered,1789100000,1789100000,true,bodies,effects,equipment) and construction.snapshot()==world,"A changed destination replaced the prepared departure")
	altered=packet.duplicate(true);altered.progress.rank_score+=1
	check(not construction.prepare(bindings,cat,altered,1789100000,1789100000,true,bodies,effects,equipment) and construction.snapshot()==world,"Unearned rank replaced the prepared departure")
	var trip:=LocalTrip.new()
	check(trip.configure(bindings,cat,construction.equipment_owner(),10,packet.mission),trip.error)
	verify_local_encounter(cat,construction)
	verify_local_frame(cat,construction)
	var four:=PreparedTraining.new()
	check(four.prepare(bindings,cat,packet,1789100000,1,true,bodies,effects,equipment),four.error)
	if not four.snapshot().is_empty():
		check(four.snapshot().scenery.world_initialization.npc_construction.actors.size()==4,"Local encounter fixture did not exercise the four-ship fallback")
		verify_local_encounter(cat,four)
		verify_local_frame(cat,four)
	local_departure_verified=true

func verify_local_session(args: PackedStringArray):
	root.size=Vector2i(1280,720)
	host=Host.new();root.add_child(host);host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.set_context(lib,bindings,visuals);host.set_process(false)
	for i in 3:await process_frame
	for field_seed in [1789100000,1]:
		var session:=TrainingSession.new();host.viewport.add_child(session);host.session=session;now_us=0
		if not session.configure(lib,bindings,visuals,local_packet,true,0,1789100000,field_seed,false,local_equipment):check(false,session.error);return
		check(session.activate(),session.error);host.present_session()
		var initial: Dictionary=session.snapshot()
		check(initial.campaign_cursor==10 and initial.progress==local_packet.progress and initial.cargo==local_packet.cargo,"Local presentation changed the earned departure")
		check(session.scene.encounter.actors.size()==(1 if field_seed==1789100000 else 4),"Local scene omitted generated ships")
		check(session.scene.geometry.player.engine_glow!=null and session.scene.geometry.player.engine_glow.get_meta("source_resource_id")==17900,"Local player omitted Betty's original nozzle-glow mesh")
		for id in initial.encounter.combat.actors.size():
			var actor: Dictionary=initial.encounter.combat.actors[id];var nodes: Dictionary=session.scene.encounter.actors[id]
			check(nodes.ship_id==actor.hull_catalogue_id and nodes.engine.get_meta("source_resource_id")==18000+actor.hull_catalogue_id,"Local scene attached another hull or engine")
		check(session.flight_audio.snapshot().history.is_empty() and not session.can_control() and not session.scene.radio.visible,"Prepared local flight started speech or controls early")
		for i in 71:
			if not training_app_step():return
		check(session.can_control() and session.flight_hud_visible() and not session.snapshot().dialogue.visible,"Local session failed to release flight without a modal")
		check(not host.touch_overlay.visible and not host._flight_actions.visible and not host._pause_button.visible,"Desktop local flight exposed touch action buttons")
		check(session.briefing_audio.snapshot().history.is_empty() and session.objective_audio.snapshot().history.is_empty(),"Local visit played another mission's speech")
		key_down(KEY_UP)
		for i in 3:
			if not training_app_step():return
		key_up(KEY_UP)
		check(session.snapshot().player_pose!=initial.player_pose and session.snapshot().angular_units.x<0,"Local keyboard steering did not reach native flight")
		key_down(KEY_SPACE)
		if not training_app_step():return
		key_up(KEY_SPACE)
		check(session.snapshot().encounter.primary_fire.weapons[0].result.fired and session.snapshot().mining_approach.phase=="idle","Local fire started mining or failed to launch its primary")
		check(session.flight_audio.snapshot().history.any(func(event):return event.get("item_id")==22 and event.action=="start_spatial"),"Local primary omitted its source firing cue")
		# Disclosed direct damage isolates warning/response presentation. Native
		# primary contacts and their shared random stream are checked separately.
		if not local_session_hit(30):return
		var warning: Dictionary=session.snapshot().radio
		check(warning.message.kind=="warning" and not warning.visible,"Local warning skipped its source display delay")
		for i in 20:
			if not training_app_step():return
		check(not session.scene.radio.visible and session.flight_audio.snapshot().voice_displayed==[false,false],"Local voice started before strict text display")
		var world: RefCounted=session.flight_owner();var next: RefCounted=world.evaluate(1)
		if next==null:check(false,world.error);return
		var held: Dictionary=session.snapshot();var sound: Dictionary=session.flight_audio.snapshot()
		var events: Array=next._radio_events.duplicate(true)
		next._radio_events[0].voice_event_id=-1
		check(not session._commit(next,false) and session.snapshot()==held and session.flight_audio.snapshot()==sound,"Rejected local recording changed gameplay or audio history")
		next._radio_events=events
		var portrait: Dictionary=next._radio._portrait.duplicate(true)
		next._radio._portrait.parts[0]=99
		check(not session._commit(next,false) and session.snapshot()==held and session.flight_audio.snapshot()==sound,"Rejected local portrait committed gameplay or started speech")
		next._radio._portrait=portrait
		now_us+=1000
		if not session._commit(next,false,int(now_us/1000)):check(false,session.error);return
		check(session.rebase_time(now_us),session.error);host.present_session()
		var radio: Dictionary=session.snapshot().radio;var selected_voice: int=radio.message.voice_event_id
		check(session.scene.radio.visible and session.scene.radio._body.text==radio.text and session.scene.radio._portrait.texture!=null,"Local panel omitted selected text or original portrait")
		check(session.scene.radio._name.text==bindings.resolve_speaker_name(21,lib),"Local radio used another speaker's name")
		check(session.flight_audio.snapshot().voice_displayed==[true,false] and session.flight_audio.snapshot().active.get(selected_voice,{}).get("voice",false),"Local text display omitted its source voice")
		var texture: Texture2D=session.scene.radio._portrait.texture
		var rng: Dictionary=session.snapshot().random_state
		check(session.present_current() and session.scene.radio._portrait.texture==texture and session.snapshot().random_state==rng,"Presenting a local message regenerated its portrait or consumed simulation RNG")
		var audio_before: Dictionary=session.flight_audio.snapshot()
		var repeat: Dictionary=session.flight_audio.prepare_full_hold(session.flight_owner())
		session.flight_audio.commit_frame(repeat)
		check(repeat.get("repeat",false) and session.flight_audio.snapshot()==audio_before,"Repeated presentation replayed a local voice")
		key(KEY_ESCAPE);held=session.snapshot()
		check(session.is_paused() and session.flight_audio.snapshot().active[selected_voice].paused,"Local pause did not stop its radio voice")
		if not training_app_step():return
		check(session.snapshot()==held,"Paused local session advanced the radio or world")
		key(KEY_ESCAPE);check(not session.is_paused(),session.error);host.present_session()
		if args.size()==4:
			await capture(args[3],"local-warning-"+str(initial.encounter.combat.actors.size()))
			if field_seed==1789100000:await capture_phone(args[3],"local-warning-phone")
		if not local_session_hit(29):return
		check(session.snapshot().radio.message==radio.message and session.snapshot().radio.pending.kind=="response" and session.scene.radio._portrait.texture==texture,"Faction response replaced the active warning or portrait")
		var response_visible:=false
		for i in 240:
			if not training_app_step():return
			var current: Dictionary=session.snapshot().radio
			if current.visible and current.message.kind=="response":response_visible=true;break
		check(response_visible and session.flight_audio.snapshot().voice_displayed==[true,true],"Pending faction response never reached its panel and recording")
		check(session.snapshot().campaign_cursor==10 and session.snapshot().mission==local_packet.mission and session.snapshot().cargo==local_packet.cargo and not session.snapshot().combat_objective_satisfied,"Traffic presentation completed the visit or changed its cargo")
		# The shared Microgun loop remains explicitly unsupported. Its original
		# loop mode and stop ownership need integration before audible support.
		check(session.flight_audio.snapshot().unsupported=={66:"This sound requires native scheduling or parameter automation"},"Local flight changed the known Microgun diagnostic: "+str(session.flight_audio.snapshot().unsupported))
		if args.size()==4:await capture(args[3],"local-response-"+str(initial.encounter.combat.actors.size()))
		host.session=null;session.free()
	if failures==0:await verify_local_manual_travel_audio()
	if failures==0:await verify_local_session_journey(args)

func travel_audio_history(session: Node) -> Array:
	return session.flight_audio.snapshot().history.filter(func(event):return event.has("travel_serial"))

func verify_local_manual_travel_audio():
	# Branch from the earned station packet and use ordinary guidance to aim at
	# Kernstal. Cancel at the scanner threshold, then acquire and jump manually.
	var session:=TrainingSession.new();host.viewport.add_child(session);host.session=session;now_us=0
	if not session.configure(lib,bindings,visuals,local_packet,true,0,1789100000,1789100000,false,local_equipment):check(false,session.error);return
	check(session.activate(),session.error);host.present_session()
	for i in 71:
		if not training_app_step():return
	check(session.select_planet(79),session.error)
	for i in 400:
		var travel: Dictionary=session.snapshot().local_travel
		if travel.acquisition_ms>=travel.acquisition_duration_ms:break
		if not training_app_step():return
	var aimed: Dictionary=session.snapshot().local_travel
	check(aimed.phase=="flight" and aimed.candidate_station_id==79 and aimed.acquisition_ms==aimed.acquisition_duration_ms and travel_audio_history(session).is_empty(),"Manual audio branch did not reach the strict acquisition threshold")
	if aimed.phase!="flight" or aimed.candidate_station_id!=79:return
	check(session.action("autopilot"),session.error)
	key_down(KEY_SPACE)
	if not training_app_step():return
	key_up(KEY_SPACE)
	var acquired: Dictionary=session.snapshot();var audio_before: Dictionary=session.flight_audio.snapshot()
	var acquisition: Array=travel_audio_history(session)
	check(acquired.local_travel.phase=="flight" and acquired.local_travel.acquired_station_id==79 and acquisition.size()==1 and acquisition[0].source_id==26 and acquisition[0].travel_serial==1,"Manual acquisition omitted or prematurely followed its target-lock sound")
	check(acquired.encounter.primary_fire.weapons[0].result.fired and audio_before.history.any(func(event):return event.get("item_id")==22 and event.action=="start_spatial"),"Manual jump branch did not retain an actual primary firing cue")
	if acquired.local_travel.acquired_station_id!=79:return
	var world: RefCounted=session.flight_owner();var candidate: RefCounted=world.launch_planet()
	if candidate==null:check(false,world.error);return
	# Every rejected preparation must retain clocks, random state and sound
	# ownership, so the exact same native launch can be retried afterwards.
	for changes in [
		{"event_serial":4}, {"event_serial":0}, {"events":[]},
		{"events":[{"kind":"sound","source_id":66}]},
		{"events":[{"kind":"sound","source_id":5},{"kind":"sound","source_id":26}]},
		{"events":[{"kind":"sound","source_id":26}]},
		{"launch_ms":1}, {"destination_station_id":78}, {"acquired_station_id":-1}]:
		var invalid: RefCounted=candidate.fork_for_frame()
		for field in changes:invalid._local_travel._state[field]=changes[field]
		check(session.flight_audio.prepare_full_hold(invalid).is_empty() and session.flight_audio.snapshot()==audio_before and session.snapshot()==acquired,"Malformed travel batch changed accepted audio or gameplay: "+str(changes))
	var foreign: RefCounted=candidate.fork_for_frame();foreign._local_travel._identity.binding_id="foreign"
	check(session.flight_audio.prepare_full_hold(foreign).is_empty() and session.flight_audio.snapshot()==audio_before,"Foreign travel audio replaced its accepted owner")
	var missing: RefCounted=candidate.fork_for_frame();missing._local_travel=null
	check(session.flight_audio.prepare_full_hold(missing).is_empty() and session.flight_audio.snapshot()==audio_before,"A detached travel owner kept its sounds")
	var clip: Dictionary=session.flight_audio._resources._clips[5]
	session.flight_audio._resources._clips[5]={}
	check(not session._commit(candidate,false) and session.snapshot()==acquired and session.flight_audio.snapshot()==audio_before,"Failed launch clip staging committed travel or previous frame sounds")
	session.flight_audio._resources._clips[5]=clip
	check(session.set_pause("user",true,now_us),session.error)
	var paused_sound: Dictionary=session.flight_audio.snapshot()
	check(not session.action("jump") and session.snapshot()==acquired and session.flight_audio.snapshot()==paused_sound,"Paused manual jump changed its world or sound")
	check(session.set_pause("user",false,now_us),session.error)
	var prepared: Dictionary=session.flight_audio.prepare_full_hold(candidate)
	check(not prepared.is_empty() and session.snapshot()==acquired and session.flight_audio.snapshot()==audio_before,"Preparing manual launch changed playback or native state")
	if prepared.is_empty():check(false,session.flight_audio.error);return
	check(prepared.operations.size()==1 and prepared.operations[0].source_id==5 and prepared.operations[0].travel_serial==2,"Manual launch replayed the preceding primary, scanner, radio or destruction operations")
	check(session.action("jump"),session.error)
	var launched: Dictionary=session.snapshot();var audio_after: Dictionary=session.flight_audio.snapshot()
	var sounds: Array=travel_audio_history(session)
	check(launched.local_travel.phase=="launch" and launched.flight_audio.serial==acquired.flight_audio.serial and launched.encounter.elapsed_ms==acquired.encounter.elapsed_ms and launched.random_state==acquired.random_state,"Manual launch advanced an ordinary flight tick")
	check(launched.camera_shot.mode=="fixed_eye" and launched.camera_shot.eye==acquired.camera_view.eye and launched.camera_view==acquired.camera_view and not launched.scenery_collision_enabled,"Manual launch moved its camera immediately or retained ordinary collision permission")
	for i in launched.encounter.primaries.guns.size():
		var gun: Dictionary=launched.encounter.primaries.guns[i]
		check(gun.projectiles.elapsed_ms==0 and not gun.projectiles.time_ready and gun.projectiles.slots==acquired.encounter.primaries.guns[i].projectiles.slots,"Manual departure reset a live projectile instead of only the primary interval")
	check(sounds.size()==2 and sounds[0].source_id==26 and sounds[1].source_id==5 and sounds[1].travel_serial==2 and sounds[1].destination_station_id==79,"Manual launch lost its separate ordered sound batch")
	check(audio_after.history.size()==audio_before.history.size()+1 and not audio_after.unsupported.has(5) and not audio_after.unsupported.has(26),"Manual launch repeated a previous sound or marked supported clips unavailable")
	session.flight_audio.commit_frame(prepared)
	var repeated: Dictionary=session.flight_audio.prepare_full_hold(session.flight_owner());session.flight_audio.commit_frame(repeated)
	check(repeated.get("repeat",false) and session.flight_audio.snapshot()==audio_after,"A repeated or stale manual launch replayed its sound")
	for i in 3:
		if not training_app_step():return
		var current: Dictionary=session.snapshot()
		check(current.camera_view.mode=="fixed_eye" and current.camera_view.eye==acquired.camera_view.eye and current.camera_view.look==current.player_pose.origin and not current.scenery_collision_enabled,"Manual launch resumed follow movement instead of watching the departing ship")
	check(travel_audio_history(session)==sounds,"Later launch ticks repeated manual travel sounds")
	host.session=null;session.free()

func verify_local_session_journey(args: PackedStringArray, existing: Node=null):
	# A fresh branch of the actual earned departure verifies accepted rendering
	# and session controls without the damage placements used by the radio tests.
	var session: Node=existing
	if session==null:
		session=TrainingSession.new();host.viewport.add_child(session);host.session=session;now_us=0
		if not session.configure(lib,bindings,visuals,local_packet,true,0,1789100000,1789100000,false,local_equipment):check(false,session.error);return
		check(session.activate(),session.error)
	host.present_session()
	check(not session.select_planet(79),"Local session accepted planet selection before entry release")
	check(not host.open_map(now_us) and not host.map_panel.visible,"Local map bypassed the entry cinematic")
	for i in 71:
		if not training_app_step():return
	var before: Dictionary=session.snapshot()
	check(not session.select_planet(75) and session.snapshot()==before,"Unsupported planet selection changed the accepted session")
	if not await verify_local_map_interface(args,session):return
	host.present_session()
	check(session.snapshot().station_autopilot.target_kind=="planet" and session.snapshot().input_throttle==1.0,"Local session did not activate planet guidance")
	for i in 400:
		if session.snapshot().local_travel.phase!="flight":break
		if not training_app_step():return
		var state: Dictionary=session.snapshot()
		for row in session.scene.planets.selection.planets:
			var target: Dictionary=state.local_travel.targeting.markers.filter(func(value):return value.station_id==row.station_id)[0]
			check(row.pose.origin==target.position,"Rendered and acquired planet positions disagree")
	var launching: Dictionary=session.snapshot()
	check(launching.local_travel.phase=="launch" and not session.can_control(),"Rendered local guidance failed to launch or retained manual controls")
	if launching.local_travel.phase!="launch":return
	check(launching.camera_shot.mode=="fixed_eye" and launching.camera_shot.eye==launching.camera_view.eye and launching.camera_view.mode=="follow" and not launching.scenery_collision_enabled,"Automatic launch failed to retain the eye from its preceding camera pass")
	var travel_sounds: Array=travel_audio_history(session)
	check(travel_sounds.size()==2 and travel_sounds[0].source_id==26 and travel_sounds[1].source_id==5 and travel_sounds[0].travel_serial==1 and travel_sounds[1].travel_serial==1,"Automatic departure lost the source target-lock/launch sound order")
	check(travel_sounds.all(func(event):return event.destination_station_id==79 and event.action=="start") and not session.flight_audio.snapshot().unsupported.has(5) and not session.flight_audio.snapshot().unsupported.has(26),"Automatic travel used another destination or unsupported sound")
	var accepted_sound: Dictionary=session.flight_audio.snapshot()
	var repeat: Dictionary=session.flight_audio.prepare_full_hold(session.flight_owner());session.flight_audio.commit_frame(repeat)
	check(repeat.get("repeat",false) and session.flight_audio.snapshot()==accepted_sound,"Repeated automatic departure replayed its sounds")
	check(not session.action("throttle_down") and not session.action("autopilot") and not session.select_planet(79) and session.snapshot()==launching,"Departure accepted a session action")
	check(session.set_pause("user",true,now_us),session.error)
	if not training_app_step():return
	check(session.snapshot()==launching,"Paused rendered departure advanced")
	check(travel_audio_history(session)==travel_sounds,"Paused automatic departure replayed its sounds")
	check(session.set_pause("user",false,now_us),session.error)
	host.present_session()
	if args.size()==4:await capture(args[3],"kernstal-launch")
	for i in 30:
		if not training_app_step():return
		var current: Dictionary=session.snapshot()
		check(current.camera_view.eye==launching.camera_view.eye and current.camera_view.look==current.player_pose.origin and session.scene.camera.global_position==launching.camera_view.eye,"Rendered departure camera moved with the ship or stopped looking at it")
		check(session.scene.geometry.player.engine_glow.visible==current.ship_detail.selections.player.visible and session.scene.geometry.player.engine_glow.global_transform.is_equal_approx(session.scene.geometry.player.global_transform),"Jump glow lost the moving player's visual pose or detail visibility")
		if args.size()==4 and i==14:await capture(args[3],"kernstal-launch-midpoint")
	check(session.status=="running" and session.snapshot().local_travel.launch_ms==3000,"Rendered departure transitioned at equality")
	if not training_app_step():return
	var arrived: Dictionary=session.snapshot()
	check(session.status=="local_arrival_transition_required" and session.flight_owner().prepare_local_arrival().station_id==79,"Rendered flight did not hand off the destination")
	check(arrived.campaign_cursor==10 and arrived.progress==before.progress and arrived.cargo==before.cargo and arrived.equipment==before.equipment,"Rendered departure changed campaign or equipment ownership")
	if not training_app_step():return
	check(session.snapshot()==arrived,"Pending destination kept advancing the old session")
	check(travel_audio_history(session)==travel_sounds,"Automatic departure ticks replayed travel sounds")
	await verify_local_session_arrival(args,session)

func verify_local_map_interface(args: PackedStringArray, session: Node):
	var before: Dictionary=session.snapshot()
	key_down(KEY_SPACE);check(choose_keyboard_flight_action(KEY_E,"map"),"E action menu did not open the map")
	check(session.map_open() and session.map_active() and host.map_panel.visible and not session.can_control(),"Keyboard map failed to take flight input")
	check(session.flight_audio.snapshot().paused and not host._controls.snapshot().held.fire,"Map retained held fire or unpaused flight sound")
	if not session.map_open():return false
	if not training_app_step():return false
	check(session.snapshot()==before,"Map time advanced movement, cargo, combat, scanning or mission state")
	key(KEY_SPACE);key(KEY_BRACKETRIGHT)
	check(not host._controls.snapshot().held.fire and session.snapshot()==before,"Map forwarded flight actions")
	host.map_panel.select_station(78);host.map_panel.request_confirmation()
	check(host.map_panel.snapshot().diagnostic==lib.strings[408] and not host.map_panel.snapshot().confirmation_visible,"Map allowed travel to the current station")
	host.map_panel.select_station(75);host.map_panel.request_confirmation()
	check(not host.map_panel.snapshot().confirmation_visible and session.snapshot()==before,"Map created an unsupported destination")
	host.map_panel.select_station(79);host.map_panel.request_confirmation()
	var pending: Dictionary=host.map_panel.snapshot()
	check(pending.confirmation_visible and pending.selected_station_id==79 and session.snapshot()==before,"Map selection changed flight before confirmation")
	check(not host.confirm_map_planet(75,now_us) and not session.confirm_map_planet(75,now_us) and not session.confirm_map_planet(79,-1) and session.snapshot()==before and session.map_active(),"Rejected map course committed or resumed the flight")
	if args.size()==4:await capture(args[3],"local-map-flight-desktop")
	host.set_user_paused(true);host.present_session()
	check(not session.map_active() and not host.confirm_map_planet(79,now_us),"User pause allowed a pending map course")
	key(KEY_ESCAPE);session.rebase_time(now_us)
	check(session.map_active() and host.map_panel.snapshot()==pending,"Keyboard resume closed the map or changed its pending selection")
	for reason in ["focus","hidden"]:
		check(session.set_pause(reason,true,now_us),session.error);host.refresh_render_mode()
		key(KEY_ENTER)
		check(host.map_panel.snapshot()==pending and session.snapshot()==before and not host.confirm_map_planet(79,now_us),"External pause changed a pending map course: "+reason)
		check(session.set_pause(reason,false,now_us),session.error);host.refresh_render_mode()
	check(host.map_panel.error.is_empty() and host.map_panel._status.text.contains(pending.labels.question),"Resuming the map replaced its pending question with an inactive-input diagnostic")
	if args.size()==4:await capture_phone(args[3],"local-map-flight-phone")
	check(not host._flight_actions.visible and not host.touch_overlay.active,"Map exposed active touch flight controls")
	key(KEY_ESCAPE)
	check(session.map_open() and not host.map_panel.snapshot().confirmation_visible and session.snapshot()==before,"Cancel confirmation advanced flight or discarded the map")
	key(KEY_ESCAPE);session.rebase_time(now_us)
	check(not session.map_open() and session.can_control() and not host.map_panel.visible and session.snapshot()==before,"Closing the map changed its retained flight")
	button(JOY_BUTTON_LEFT_SHOULDER)
	check(session.map_active(),"Controller shortcut did not open the local map")
	for i in 5:button(JOY_BUTTON_DPAD_DOWN)
	check(host.map_panel.snapshot().selected_station_id==79,"Controller navigation did not reach Kernstal")
	button(JOY_BUTTON_A)
	check(session.map_open() and host.map_panel.snapshot().confirmation_visible and session.snapshot()==before,"Controller course bypassed confirmation")
	button(JOY_BUTTON_A);session.rebase_time(now_us)
	check(not session.map_open() and not host.map_panel.visible and session.can_control(),"Confirmed course retained modal input")
	check(session.snapshot().station_autopilot.target_kind=="planet" and session.snapshot().station_autopilot.station_id==79,"Confirmed course failed to use native planet guidance")
	check(session.snapshot().campaign_cursor==10 and session.snapshot().cargo==before.cargo and session.snapshot().progress==before.progress and session.snapshot().player_pose==before.player_pose,"Confirming the map teleported, rewarded or changed the career")
	return failures==0

func verify_local_session_arrival(args: PackedStringArray, departing: Node):
	var source: RefCounted=departing.flight_owner()
	var retained: Dictionary=departing.snapshot()
	var textures: Dictionary=visuals.textures;visuals.textures={}
	# Exercise the application's normal transition dispatch, including the
	# local-arrival boundary in its process loop, before retrying failed loading.
	host._process(0)
	check(host._transition_failed and host.session==departing and departing.snapshot()==retained,"Failed automatic destination replaced the accepted departure")
	visuals.textures=textures
	check(host._transition_failed and departing.is_paused(),"Failed destination did not retain a paused retryable flight")
	if not host.retry_transition():check(false,host.status.text);return
	var arrival: Node=host.session;arrival.rebase_time(now_us)
	var prepared: Dictionary=arrival.snapshot()
	check(prepared.location.station_id==79 and prepared.actors.is_empty() and arrival.scene.encounter.actors.is_empty(),"Kernstal reused departure geometry or actors")
	check(prepared.progress==retained.progress and prepared.cargo==retained.cargo and prepared.equipment.prices==retained.equipment.prices,"Destination preparation lost earned state")
	check(not prepared.entry_released and not arrival.can_control(),"Prepared destination started active")
	check(not is_instance_valid(departing) and not host._transition_failed and not arrival.is_paused(),"Accepted destination retained the old world or transition pause")
	host.present_session()
	if args.size()==4:await capture(args[3],"kernstal-entry")
	check(arrival.set_pause("user",true,now_us),arrival.error)
	if not training_app_step():return
	check(arrival.snapshot()==prepared,"Paused arrival advanced its entry")
	check(arrival.set_pause("user",false,now_us),arrival.error)
	for i in 71:
		if not training_app_step():return
	check(arrival.can_control() and arrival.snapshot().entry_released and not arrival.scene.radio.visible,"Destination failed to release ordinary input")
	check(arrival.snapshot().camera_view.mode=="follow" and arrival.snapshot().scenery_collision_enabled,"Destination retained the previous world's departure camera or collision permission")
	check(arrival.scene.geometry.player.engine_glow!=null and arrival.scene.geometry.player.engine_glow.get_meta("source_resource_id")==17900,"Fresh Kernstal entry lost the player's original glow")
	# The empty destination rejects the preceding world's weapon. Its death
	# lifecycle then uses an explicit exhausted-hull fixture, without a shooter.
	verify_local_game_over(arrival.flight_owner(),source.snapshot().encounter.weapons.actors[0].projectiles.weapon)
	check(arrival.snapshot().progress==retained.progress and arrival.snapshot().cargo==retained.cargo,"Destination entry completed the mission or changed cargo")
	if args.size()==4:await capture(args[3],"kernstal-flight")
	check(arrival.action("autopilot"),arrival.error)
	for i in 600:
		if arrival.status=="station_transition_required":break
		if not training_app_step():return
	check(arrival.status=="station_transition_required","Native guidance never reached Kernstal docking")
	if arrival.status!="station_transition_required":return
	var docked: Dictionary=arrival.snapshot()
	check(docked.location.station_id==79 and docked.progress==retained.progress and docked.station_response_flags=={78:false,79:false},"Docking lost the pending mission or station history")
	if not host.enter_station(now_us,42):check(false,host.status.text);return
	var station: Node=host.session;station.rebase_time(now_us)
	check(station.station_name=="Kernstal" and station.snapshot().campaign_cursor==10,"Destination station reused another location")
	for i in 10:
		if not training_app_step():return
	check(station.snapshot().conversation_started and station.snapshot().dialogue.text_id==int(bindings.mido_travel.conversations[1].events[0].text_id),"Kernstal's delayed conversation did not start")
	if args.size()==4:
		await capture(args[3],"kernstal-station")
		await capture_phone(args[3],"kernstal-station-phone")
	for event in bindings.mido_travel.conversations[1].events:
		check(station.snapshot().dialogue.text_id==int(event.text_id) and station.audio.snapshot().history.back().source_id==int(event.voice_event_id),"Kernstal dialogue and voice diverged")
		check(station.snapshot().campaign_cursor==10 and station.snapshot().cargo==docked.cargo,"A station line completed early or cleared the hold")
		key(KEY_ENTER)
	var finished: Dictionary=station.snapshot()
	check(finished.campaign_cursor==11 and finished.local_visit_acknowledged and finished.mission.station_id==76,"Kernstal did not select the source next objective")
	check(finished.cargo==docked.cargo and finished.equipment==docked.equipment and finished.reward_credits==0,"Kernstal granted an unsupported reward or changed equipment")
	if bindings.mido_travel.get("continuation",{}).is_empty():check(not host.request_departure(),"The unimplemented next local flight was exposed")
	else:check(host._launch_button.visible,"The next supported visit lost its launch action")
	# The host retains the accepted station for a continuing application journey.
	# The caller's normal reset/free owns cleanup after inspecting that state.

func local_session_hit(damage: int) -> bool:
	var world: RefCounted=host.session.flight_owner()
	if not world._encounter._combat.begin_contact_pass(world.snapshot().random_state,true) or world._encounter._combat.normal_hit(0,damage).is_empty():check(false,world._encounter._combat.error);return false
	world._random=world._encounter._combat.contact_random_state()
	var next: RefCounted=world.evaluate(0)
	if next==null:check(false,world.error);return false
	if not host.session._commit(next,false):check(false,host.session.error);return false
	host.present_session();return true

func verify_local_encounter(cat: RefCounted, construction: RefCounted) -> void:
	var encounter:=PreparedEncounter.new()
	check(encounter.configure_local_traffic(bindings,cat,lib,construction,0.5),encounter.error)
	if encounter.snapshot().is_empty():return
	var player: RefCounted=construction.player_owner();var scenery: RefCounted=construction.scenery_owner()
	var entry: Dictionary=construction.snapshot();var random: Dictionary=entry.random_state
	var initial: Dictionary=encounter.snapshot()
	check(initial.campaign_cursor==10 and initial.combat.current_reputation==entry.departure.progress.reputation,"Shared encounter lost actual local progress")
	check(initial.projectile_visuals.models.size()==initial.combat.actors.size()+1 and initial.impact_visuals.weapons.size()==initial.combat.actors.size()+1,"Local weapon models omitted a generated ship")
	for model in initial.projectile_visuals.models:
		check(model.model_id==(6798 if model.key=="player:0" else 6802),"Shared local projectile has the wrong original resource")
	for model in initial.impact_visuals.weapons:check(model.model_id==14606,"Shared local impact has the wrong original resource")
	check(encounter.evaluate_weapons(player,entry.player_pose,0,scenery).is_empty() and encounter.snapshot()==initial,"Missing local stream partially committed a weapon frame")
	check(encounter.evaluate_weapons(player,entry.player_pose,0,scenery,{"state":-1}).is_empty() and encounter.snapshot()==initial,"Invalid local stream partially committed a weapon frame")
	for i in 14:
		var warm: Dictionary=encounter.evaluate_weapons(player,entry.player_pose,150,scenery,random)
		if warm.is_empty():check(false,encounter.error);return
		encounter=warm.encounter;player=warm.player;scenery=warm.scenery;random=warm.random_state
	# Deliberate fixture placement and pre-damage isolate an actual primary hit
	# at the warning threshold, after its spread draws and before the NPC pass.
	check(encounter._combat.begin_contact_pass(random,true),encounter._combat.error)
	check(not encounter._combat.normal_hit(0,29).is_empty(),encounter._combat.error)
	check(not encounter.snapshot().combat.provocation.warning_issued,"Actual rank-2 fixture crossed the warning threshold before the shot")
	var pose:=Transform3D(Basis.IDENTITY,Vector3(1000000,0,0))
	var fire: Dictionary=encounter.evaluate_primary_fire(player,pose,true,true,random)
	if fire.is_empty():check(false,encounter.error);return
	encounter=fire.encounter;random=fire.random_state
	var shot: Vector3=encounter.snapshot().primaries.guns[0].projectiles.slots[0].position
	check(encounter.snapshot().primaries.guns[0].projectiles.slots[0].get("up")==Vector3.UP,"Local primary lost its captured firing orientation")
	for id in initial.combat.actors.size():check(encounter._combat.set_pose(id,Transform3D(Basis.IDENTITY,shot+Vector3(id*100000,0,0))),encounter._combat.error)
	var retained: Dictionary=encounter.snapshot();var field: Dictionary=scenery.snapshot()
	var hit: Dictionary=encounter.evaluate_weapons(player,pose,0,scenery,random,true)
	if hit.is_empty():check(false,encounter.error);return
	check(encounter.snapshot()==retained and scenery.snapshot()==field,"Prospective encounter contacts mutated accepted owners")
	var generator:=preload("res://src/simulation/seeded_random.gd").new();generator.restore(random);generator.next_int(3)
	check(hit.random_state==generator.snapshot() and hit.encounter.snapshot().combat.provocation.warning_issued,"Shared encounter lost the warning draw after the firing spread")
	check(hit.encounter.snapshot().combat.actors[0].vitals.hull<retained.combat.actors[0].vitals.hull and not hit.encounter.snapshot().combat.actors[0].hostile,"Weapon contact omitted damage or refreshed hostility before the NPC pass")
	for actor in initial.combat.actors:check(hit.encounter._combat.set_pose(actor.actor_id,actor.pose,actor.body_pose),hit.encounter._combat.error)
	var advanced: Dictionary=hit.encounter.evaluate_world(hit.player,pose,0,hit.random_state)
	if advanced.is_empty():check(false,hit.encounter.error);return
	check(advanced.encounter.snapshot().combat.actors[0].hostile==hit.encounter.snapshot().combat.provocation.forced_hostile[0] and advanced.encounter.snapshot().controller.defeat_status.is_empty(),"Local encounter lost deferred hostility or invented campaign completion")
	check(construction.snapshot()==entry,"Live encounter mutated its prepared departure")

func verify_local_frame(cat: RefCounted, construction: RefCounted) -> void:
	var frame:=PreparedFrame.new()
	check(frame.configure(bindings,cat,lib,construction,"D",1.0),frame.error)
	if frame.snapshot().is_empty():return
	var initial: Dictionary=frame.snapshot();var entry: Dictionary=construction.snapshot()
	check(initial.campaign_cursor==10 and initial.cargo==entry.departure.cargo and initial.progress==entry.departure.progress,"Local frame lost the earned mission, cargo or career")
	check(initial.encounter.combat.actors.size()==entry.scenery.world_initialization.npc_construction.actors.size() and initial.npc_scanner.duration_ms==4000,"Local frame lost generated traffic or the installed scanner")
	check(not initial.player.damage_allowed and not initial.dialogue.visible and not initial.entry_released,"Local frame released controls before its entry")
	check(frame.evaluate(150,Vector2.ONE,0.0,true).snapshot()==initial,"Paused local flight advanced its retained owners")
	check(frame.start_mining()==null and frame.start_station_autopilot()==null and frame.snapshot()==initial,"Entry accepted an early flight action")
	for i in 46:
		var next: RefCounted=frame.evaluate(150,Vector2.ZERO,1.0,false,Vector2i.ZERO,Vector2.ZERO,true)
		if next==null:check(false,frame.error);return
		frame=next
	var before_release: RefCounted=frame.evaluate(100)
	if before_release==null:check(false,frame.error);return
	frame=before_release
	check(not frame.snapshot().entry_released and frame.snapshot().entry_elapsed_ms==7000 and frame.snapshot().encounter.primary_fire.is_empty(),"Local entry timing or primary-input gate changed")
	var released: RefCounted=frame.evaluate(1)
	if released==null:check(false,frame.error);return
	frame=released
	check(frame.snapshot().entry_released and frame.snapshot().player.damage_allowed and frame.snapshot().phase=="flight" and not frame.snapshot().dialogue.visible,"Local flight omitted ordinary release or invented a briefing")
	for i in 35:
		var next: RefCounted=frame.evaluate(150)
		if next==null:check(false,frame.error);return
		frame=next
	var flying: Dictionary=frame.snapshot()
	check(flying.progress==initial.progress and flying.mission==initial.mission and flying.cargo==initial.cargo,"Ordinary local flight changed earned state")
	check(not flying.dialogue.visible and not flying.combat_objective_satisfied and not flying.cargo_objective_satisfied and frame.prepare_station().is_empty(),"Local flight completed the visit from mining or combat rules")
	check(flying.actors[0].pose!=initial.actors[0].pose and flying.player_pose!=initial.player_pose,"Local frame failed to advance native player and traffic motion")
	check(not flying.npc_scanner.markers.is_empty() and flying.npc_scanner.visible,"Released local flight omitted ordinary NPC acquisition")
	verify_local_targeting(frame)
	verify_local_journey(frame)
	# Direct fixture damage checks retained radio and lethal accounting through
	# the complete frame. Real projectile contacts are checked above.
	check(frame._encounter._combat.begin_contact_pass(flying.random_state,true),frame._encounter._combat.error)
	check(not frame._encounter._combat.normal_hit(0,30).is_empty(),frame._encounter._combat.error)
	frame._random=frame._encounter._combat.contact_random_state()
	var radio_pass: RefCounted=frame.evaluate(0)
	if radio_pass==null:check(false,frame.error);return
	frame=radio_pass
	check(frame.snapshot().radio.message.kind=="warning" and frame.snapshot().radio_events.size()==1 and frame.snapshot().radio_events[0].kind=="started","Local frame did not activate its deferred warning radio")
	var talking: Dictionary=frame.snapshot()
	check(frame.evaluate(150,Vector2.ZERO,1.0,true).snapshot()==talking,"Paused local flight advanced timed radio")
	for i in 14:
		var next: RefCounted=frame.evaluate(150)
		if next==null:check(false,frame.error);return
		frame=next
	check(frame.snapshot().radio.visible and frame.snapshot().player_pose!=talking.player_pose and not frame.dialogue_visible(),"Timed local radio paused flight or became an acknowledged modal")
	check(frame._encounter._combat.begin_contact_pass(frame.snapshot().random_state,true),frame._encounter._combat.error)
	check(not frame._encounter._combat.normal_hit(0,999).is_empty(),frame._encounter._combat.error)
	frame._random=frame._encounter._combat.contact_random_state()
	var lethal: RefCounted=frame.evaluate(0)
	if lethal==null:check(false,frame.error);return
	frame=lethal
	check(frame.snapshot().progress.reputation.axes==[30,-1] and frame.snapshot().progress.pirate_kills==initial.progress.pirate_kills,"Local flight lost lethal reputation or invented a pirate kill")
	check(frame.snapshot().encounter.combat.provocation.station_response_flag and frame.snapshot().campaign_cursor==10 and not frame.snapshot().combat_objective_satisfied,"Faction response completed the visit or lost its station consequence")
	if initial.actors.size()==1:verify_local_game_over(frame)
	check(construction.snapshot()==entry,"The local frame mutated station departure construction")

func verify_local_targeting(frame: RefCounted) -> void:
	var retained: Dictionary=frame.snapshot()
	var travel: RefCounted=frame.local_travel_owner()
	check(travel!=null and travel.snapshot().targeting.markers.size()==5,"Local flight omitted its original Mido planet list")
	if travel==null:return
	var origin: Vector3=travel.target_position(79)-retained.camera_view.pose.origin
	# Deliberate camera/reticle samples isolate the original integer window.
	# The destination position and order still come from the actual layout.
	var camera:=Transform3D(Basis.looking_at(origin,Vector3.UP),Vector3(1200,250,9000))
	for viewport in [Vector2i(1280,720),Vector2i(801,451)]:
		var aim: Dictionary=retained.player_aim.duplicate(true)
		aim.viewport_size=viewport;aim.point=Vector3(viewport.x>>1,viewport.y>>1,-1)
		check(travel.sample_frame(camera,aim,0,-1,true),travel.error)
		var sample: Dictionary=travel.snapshot().targeting
		var row: Dictionary=sample.markers.filter(func(value):return value.station_id==79)[0]
		check(travel.snapshot().candidate_station_id==79 and row.in_view and row.in_scan_window,"Facing Kernstal did not start acquisition")
		check(row.position.distance_to(origin+camera.origin)<.01,"Planet acquisition used a fixed world position")
		var width: int=viewport.x/18
		check(sample.window_high-sample.window_low==Vector2i(width,width),"Planet window used the wider asteroid radius")
		for edge in 4:
			var edge_aim:=aim.duplicate(true)
			edge_aim.point=Vector3(row.pixels.x,row.pixels.y,-1)
			var axis:=edge/2
			edge_aim.point[axis]=float(row.pixels[axis]+(width>>1)-(width if edge%2 else 0))
			check(travel.sample_frame(camera,edge_aim,150,-1,true),travel.error)
			check(travel.snapshot().candidate_station_id==-1 and travel.snapshot().acquisition_ms==0,"A planet exactly on an integer window edge acquired")
			edge_aim.point[axis]+=1 if edge%2 else -1
			check(travel.sample_frame(camera,edge_aim,150,-1,true),travel.error)
			check(travel.snapshot().candidate_station_id==79 and travel.snapshot().acquisition_ms==150,"A planet one pixel inside its window was rejected")
		check(travel.sample_frame(camera,aim,150,-1,true,true) and travel.snapshot().acquisition_ms==0,"Selected mining geometry failed to suppress planet acquisition")
		check(travel.sample_frame(camera,aim,150,-1,true),travel.error)
		check(travel.sample_frame(camera,aim,150,-1,false) and travel.snapshot().acquisition_ms==150,"Hidden planet HUD advanced or reset acquisition")
		var before: Dictionary=travel.snapshot();var wrong:=aim.duplicate(true);wrong.binding_id="another-pack"
		check(not travel.sample_frame(camera,wrong,150,-1,true) and travel.snapshot()==before,"Rejected planet projection mutated acquisition")
		check(travel.sample_frame(Transform3D(camera.basis.rotated(Vector3.UP,PI),camera.origin),aim,150,-1,true),travel.error)
		check(travel.snapshot().candidate_station_id==-1 and travel.snapshot().acquisition_ms==0,"A rear planet retained its acquisition")
	check(frame.snapshot()==retained,"Detached projection checks mutated the live flight")

func verify_local_journey(frame: RefCounted) -> void:
	var retained: Dictionary=frame.snapshot()
	for id in [-1,75,76,77,78,80]:
		check(frame.select_planet(id)==null and frame.snapshot()==retained,"Unsupported map selection changed the live flight")
	check(frame.select_planet(79,true)==null and frame.snapshot()==retained,"Paused planet selection started travel")
	var next: RefCounted=frame.select_planet(79)
	if next==null:check(false,frame.error);return
	var selected: Dictionary=next.snapshot()
	check(selected.station_autopilot.active and selected.station_autopilot.target_kind=="planet" and selected.station_autopilot.station_id==79,"Planet selection did not share the player autopilot")
	check(selected.station_autopilot.history==retained.station_autopilot.history and selected.player_pose==retained.player_pose,"Selecting a planet reset bank history or teleported the ship")
	var cancelled: RefCounted=next.cancel_station_autopilot()
	check(cancelled!=null and not cancelled.snapshot().station_autopilot.active and cancelled.snapshot().player_pose==selected.player_pose,"Cancelling planet guidance changed player placement")
	check(next.evaluate(150,Vector2.ONE,0.0,true).snapshot()==selected,"Paused planet guidance advanced its flight")
	var guided: RefCounted=next.evaluate(100)
	if guided==null:check(false,next.error);return
	check(guided.snapshot().station_autopilot.target_position==next.local_travel_owner().target_position(79),"Guidance did not sample the preceding rendered planet position")
	next=guided
	for i in 400:
		if next.local_departing():break
		var advanced: RefCounted=next.evaluate(100)
		if advanced==null:check(false,next.error);return
		next=advanced
	var launch: Dictionary=next.snapshot()
	check(launch.local_travel.phase=="launch" and launch.local_travel.destination_station_id==79,"Native guidance never aligned and acquired Kernstal")
	if launch.local_travel.phase!="launch":return
	check(launch.local_travel.launch_ms==0 and launch.local_travel.events==[{"kind":"sound","source_id":26},{"kind":"sound","source_id":5}],"Acquisition started motion early or lost its ordered source cues")
	check(launch.camera_shot.mode=="fixed_eye" and launch.camera_shot.eye==launch.camera_view.eye and launch.camera_view.mode=="follow" and not launch.scenery_collision_enabled,"Acquisition failed to select the fixed-eye shot after its current camera pass")
	check(launch.encounter.primaries.guns.all(func(gun):return gun.projectiles.elapsed_ms==0 and not gun.projectiles.time_ready),"Automatic departure retained a ready primary instead of resetting its firing interval")
	check(next.select_planet(79)==null and next.start_station_autopilot()==null and next.cancel_station_autopilot()==null and next.start_mining()==null and next.launch_planet()==null,"Launch accepted ordinary player actions")
	check(next.evaluate(150,Vector2.ONE,0.0,true).snapshot()==launch,"Paused departure advanced movement or its clock")
	if retained.actors.size()==1:verify_local_game_over(next)
	for i in 20:
		var before: Dictionary=next.snapshot()
		var advanced: RefCounted=next.evaluate(150,Vector2.ONE,0.0,false,Vector2i.ZERO,Vector2.ZERO,true)
		if advanced==null:check(false,next.error);return
		next=advanced
		var current: Dictionary=next.snapshot()
		check(current.player_pose.basis==launch.player_pose.basis and absf(current.player_pose.origin.distance_to(before.player_pose.origin)-1200.0)<.1,"Departure ignored source speed or accepted steering/throttle")
		check(current.camera_view.mode=="fixed_eye" and current.camera_view.eye==launch.camera_view.eye and current.camera_view.look==current.player_pose.origin and not current.scenery_collision_enabled,"Departure re-enabled ordinary follow or collision instead of retaining its camera eye")
		check(current.encounter.primaries.guns.all(func(gun):return gun.projectiles.elapsed_ms==(i+1)*150),"Departure reset primary timers more than once or stopped their ordinary updates")
		check(current.encounter.primary_fire.is_empty() and current.local_travel.launch_ms==(i+1)*150,"Departure accepted primary input or advanced the wrong clock")
		check(current.npc_scanner.visible and not current.local_travel.targeting.visible,"Planet launch suppressed unrelated NPC HUD work or retained planet acquisition")
	check(next.snapshot().local_travel.phase=="launch" and next.prepare_local_arrival().is_empty(),"Departure transitioned at exactly 3000 milliseconds")
	var ready: RefCounted=next.evaluate(1)
	if ready==null:check(false,next.error);return
	var arrival: Dictionary=ready.snapshot();var packet: Dictionary=ready.prepare_local_arrival()
	check(arrival.boundary=="local_arrival_transition_required" and packet.station_id==79 and packet.from_station_id==78 and packet.campaign_cursor==10,"Completed launch lost its actual destination or advanced the campaign")
	check(arrival.location.station_id==78 and arrival.progress==retained.progress and arrival.cargo==retained.cargo and arrival.equipment==retained.equipment,"Preparing a destination granted progress or replaced retained inventory")
	check(ready.evaluate(150,Vector2.ONE).snapshot()==arrival and ready.prepare_station().is_empty(),"Pending local arrival advanced the old world or docked at Var Hastra")
	check(frame.snapshot()==retained,"Detached travel changed the accepted flight before commit")

func verify_local_game_over(frame: RefCounted, damage_weapon: Dictionary={}) -> void:
	var before: Dictionary=frame.snapshot()
	var branch: RefCounted=frame.fork_for_frame()
	var weapon: Dictionary=before.encounter.weapons.actors[0].projectiles.weapon if damage_weapon.is_empty() else damage_weapon
	var hits:=0
	if before.actors.is_empty():
		var intact: Dictionary=branch._player.snapshot()
		check(branch._player.weapon_hit(weapon,true,true,false).is_empty() and branch._player.snapshot()==intact,"The destination accepted a departed NPC's weapon")
		# Deliberate pool fixture isolates destruction from unimplemented
		# environmental damage. It earns no cargo, kills or mission progress.
		branch._player._state.vitals.hull=0
	while branch._player.snapshot().vitals.hull>0 and hits<100:
		if branch._player.weapon_hit(weapon,true,true,false).is_empty():check(false,branch._player.error);return
		check(true,branch._player.error);hits+=1
	check(branch._player.snapshot().vitals.hull==0,"Local damage fixture did not exhaust the equipped player")
	var dead: RefCounted=branch.evaluate(0)
	if dead==null:check(false,branch.error);return
	branch=dead
	var started: Dictionary=branch.snapshot()
	check(started.player_destruction.departure_cursor==before.campaign_cursor and started.player_destruction.phase=="tumble" and not started.player.active and not started.camera_follow_enabled,"Local lethal contact did not enter ordinary player destruction")
	check(branch.evaluate(150,Vector2.ZERO,1.0,true).snapshot()==started and branch.request_game_over_exit()==null,"Paused or premature local game-over input advanced the transition")
	for i in 160:
		if branch.game_over_waiting():break
		var next: RefCounted=branch.evaluate(150)
		if next==null:check(false,branch.error);return
		branch=next
	check(branch.game_over_waiting() and branch.snapshot().player_destruction.phase=="game_over","Local destruction failed to finish its fade")
	check(branch.prepare_local_arrival().is_empty(),"Player destruction completed a pending local arrival")
	if before.actors.is_empty():check(branch.snapshot().actors.is_empty() and branch.snapshot().cargo==before.cargo and branch.snapshot().progress==before.progress,"Player death changed the empty population or earned state")
	var exited: RefCounted=branch.request_game_over_exit()
	check(exited!=null,branch.error)
	if exited!=null:check(exited.prepare_game_over().campaign_cursor==before.campaign_cursor and exited.snapshot().boundary=="game_over_transition_required","Local game over changed campaign progress")
	check(frame.snapshot()==before,"The local death branch mutated the surviving flight")
