extends "res://tests/secondary_flight.gd"
## One native field supplies weapons, NPC flags, target order, radio, rescue and
## result observations. The equipment input remains a detached component case;
## this test creates no earned campaign departure, career, save or reward.
const Route=preload("res://src/simulation/npc_route.gd")
const Visit=preload("res://src/simulation/campaign_visit.gd")
const Outcome=preload("res://src/content/kappa_outcome_definitions.gd")
const Campaign=preload("res://src/content/free_campaign_definitions.gd")
var _radio_text_ids: Array=[]

func _initialize() -> void:call_deferred("run_encounter")

func run_encounter() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected one content/binding/visual triple")
	if args.size()==3:verify_encounter(args[0],args[1])
	await process_frame
	print("Kappa encounter/radio/result: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func verify_encounter(content: String,pack: String) -> void:
	var lib:=Library.new();var bindings:=Bindings.new();var cat:=Catalogues.new()
	if not lib.open(content) or not bindings.open(pack,lib.manifest) or not cat.open(lib) or not lib.select_language("gb"):check(false,lib.error+bindings.error+cat.error);return
	_radio_text_ids=bindings.mido_travel.kappa_rescue.radio_events.map(func(row):return int(row.text_id))
	var built:=construction(bindings,cat,0.5)
	if built==null:return
	var initial:=equipped(bindings,cat,[{"item_id":41,"slot":0,"quantity":2}])
	var views:=detached_views(bindings,cat,lib,initial,built.snapshot().random_state)
	if views.is_empty():return
	var live:=prepare_kappa_composition(bindings,cat,lib,views.equipment,built.snapshot().kappa_context)
	if live.is_empty():return
	live.route=Route.new();live.rescue=Rescue.new();live.radio=Radio.new()
	var resources:=RadioResources.new()
	if not live.route.configure_kappa_player(bindings) or not live.rescue.configure(bindings) or not resources.prepare(lib,bindings,null,21) or not live.radio.configure(bindings,lib,resources.line_counts,21):check(false,live.route.error+live.rescue.error+resources.error+live.radio.error);return
	live.player.set_permissions(true,true)
	live.pose=Transform3D(Basis.IDENTITY,live.route.snapshot().waypoints[0])
	var untouched: Dictionary=live.encounter.snapshot()
	verify_context_guards(live,bindings)
	check(radio_at(live,0).is_empty(),"Dormant native ships triggered radio")
	if not mission_pass(live):return
	check(live.rescue.poll_outcome(true).is_empty() and live.encounter.snapshot()==untouched,"Initial observations changed combat or failed dormant ships")
	if not world_pass(live,0):return
	check(live.route.advance(live.pose.origin).index==1,"Native player route did not reach the first authored point")
	var targets: Dictionary=live.encounter.kappa_radio_context(live.route)
	check(not targets.player_targets[0].active and targets.player_targets.slice(1).all(func(row):return row.active),"Native proximity activation lost the first escort group")
	verify_provocation(live)
	check(radio_at(live,0)==[{"kind":"started","event":0}],"Actual active escorts did not start the original scout line")
	var now:=finish_radio(live,0,0,resources.line_counts)
	check(radio_at(live,now)==[{"kind":"started","event":1}],"The native scout reply lost its dependency")
	now=finish_radio(live,1,now,resources.line_counts)
	check(radio_at(live,now)==[{"kind":"started","event":2}],"The real player route did not trigger the escort line")
	var before: Dictionary=live.encounter.snapshot();var prior: Dictionary=live.rescue.snapshot()
	var proposed: RefCounted=live.encounter.observe_kappa_rescue(live.rescue,live.radio)
	check(proposed!=null and proposed.snapshot().force_hostile_actor_ids==[1,2,3] and live.encounter.snapshot()==before and live.rescue.snapshot()==prior,"An early result observation applied the later escort cue")
	var candidate: Dictionary=live.encounter.evaluate_kappa_sequence(live.rescue,live.radio)
	if candidate.is_empty():check(false,live.encounter.error);return
	check(live.encounter.snapshot()==before and live.rescue.snapshot()==prior,"Prospective choreography mutated retained owners")
	live.merge(candidate,true)
	var activated: Dictionary=live.encounter.snapshot()
	check(live.rescue.snapshot().phase==1 and activated.combat.actors.slice(1).all(func(row):return row.script_hostile and row.hostile and not row.friendly),"The radio cue did not reach all three actual escorts")
	check(activated.controller.accounting==before.controller.accounting and activated.controller.flight==before.controller.flight and activated.controller.guidance==before.controller.guidance,"Escort activation reset accounting or NPC motion")
	if not mission_pass(live) or not world_pass(live,0):return
	check(live.rescue.snapshot().force_hostile_actor_ids.is_empty() and live.encounter.combat_snapshot().actors.slice(1).all(func(row):return row.script_hostile),"A later actor pass lost or repeated persistent escort hostility")
	now=finish_radio(live,2,now,resources.line_counts)
	check(radio_at(live,now).is_empty(),"An inactive kidnapper spoke from another waypoint")
	live.pose=Transform3D(Basis.IDENTITY,live.encounter.combat_snapshot().actors[0].position-Vector3(0,0,400))
	if not world_pass(live,0):return
	check(radio_at(live,now)==[{"kind":"started","event":3}],"Native kidnapper activation did not trigger its original line")
	now=finish_radio(live,3,now,resources.line_counts)
	if not weapon_pass(live,1):return
	live.encounter=live.encounter.select_secondary(41)
	if live.encounter==null:check(false,"Cannot select the native installed EMP");return
	var ordinary: Dictionary=live.encounter.combat_snapshot().actors[0].vitals
	for i in 2:
		var operation: Dictionary=live.encounter.evaluate_secondary_fire(live.player,live.equipment,live.pose,true,true,live.random_state,false)
		if operation.is_empty():check(false,live.encounter.error);return
		live.merge(operation,true)
	var hit: Dictionary=live.encounter.combat_snapshot().actors[0]
	check(hit.systems.disabled and not hit.systems_disabled and hit.vitals==ordinary,"The real EMP changed ordinary pools or projected the NPC stun early")
	check(radio_at(live,now).is_empty(),"Radio read the systems pool before the NPC projected its flag")
	if not mission_pass(live):return
	check(live.rescue.poll_outcome(true).is_empty(),"An EMP hit completed the rescue before the radio")
	if not world_pass(live,0):return
	var failure_branch:=live.duplicate();failure_branch.radio=live.radio.fork_for_frame();failure_branch.rescue=live.rescue.fork()
	check(radio_at(live,now)==[{"kind":"started","event":4}],"The actual NPC disable flag did not trigger the final line")
	if not mission_pass(live):return
	check(live.rescue.poll_outcome(true).is_empty(),"Starting the final radio counted as finishing it")
	now=finish_radio(live,4,now,resources.line_counts)
	if not result_observation(live):return
	check(live.rescue.poll_outcome(true)=="completed" and live.rescue.poll_outcome(false).is_empty(),"Completed native radio ignored the eligibility gate")
	check(live.encounter.snapshot().secondaries.guns[0].ammunition==1 and live.encounter.combat_snapshot().actors[0].vitals==ordinary,"Rescue observation spent ammunition or damaged the target")
	if Outcome.available(bindings):verify_result(live,bindings,lib,false)
	verify_retirement(failure_branch,bindings,lib)
	for cursor in [20,21,22,23,24]:check(Campaign.supported(bindings.mido_travel,cursor)==Campaign.chapter_available(bindings.mido_travel),"Detached rescue integration bypassed the connected chapter capability")

func verify_context_guards(live: Dictionary,bindings: RefCounted) -> void:
	var before: Dictionary=live.encounter.snapshot();var route: Dictionary=live.route.snapshot()
	var observed: RefCounted=live.encounter.observe_kappa_rescue(live.rescue,live.radio)
	if observed==null:check(false,live.encounter.error);return
	check(not live.rescue.matches_flight(live.encounter._control) and observed.matches_flight(live.encounter._control) and observed.fork().matches_flight(live.encounter._control.fork_for_frame()),"Native observation lost the retained flight identity or bound its input")
	var unrelated: RefCounted=live.encounter._control.fork_for_frame();unrelated._flight_identity=RefCounted.new()
	check(not observed.bind_flight(unrelated) and not observed.matches_flight(unrelated) and observed.matches_flight(live.encounter._control),"An observation changed to another flight with the same content identity")
	var other_encounter: RefCounted=live.encounter.fork_for_frame();other_encounter._control=unrelated
	check(other_encounter.observe_kappa_rescue(observed,live.radio)==null and live.encounter.snapshot()==before,"A foreign flight consumed an already bound rescue observation")
	var unearned: RefCounted=load("res://src/simulation/contract_session.gd").new()
	check(unearned.campaign_flight_context(bindings,Outcome.VALUES.mission).is_empty() and not live.encounter.bind_campaign_session(unearned,bindings,Outcome.VALUES.mission) and live.encounter.snapshot()==before,"Detached combat manufactured its own earned campaign career")
	var context: Dictionary=live.encounter.kappa_radio_context(live.route)
	check(context.player_targets.map(func(row):return row.actor_id)==[0,1,2,3] and context.route_index==0,"Radio did not retain the native player target prefix")
	context.player_targets[0].active=true;context.player_targets.reverse()
	check(live.encounter.snapshot()==before and live.route.snapshot()==route,"Changing an observation changed a retained owner")
	var npc:=Route.new();check(npc.configure_kappa_generated(bindings,0),npc.error)
	var foreign: RefCounted=live.route.fork_for_frame();foreign._identity.binding_id="foreign"
	for invalid in [null,RefCounted.new(),npc,foreign]:
		check(live.encounter.kappa_radio_context(invalid).is_empty() and live.encounter.snapshot()==before,"A foreign or NPC route changed the radio target observation")
	var wrong: RefCounted=live.encounter.fork_for_frame();wrong._inventory=live.encounter._inventory.fork_for_frame();wrong._inventory._state.npc_ids.reverse()
	check(wrong.kappa_radio_context(live.route).is_empty(),"Radio silently sorted a changed player target order")
	var other: RefCounted=live.rescue.fork();other._state.binding_id="foreign"
	for invalid in [null,RefCounted.new(),other]:
		check(live.encounter.evaluate_kappa_sequence(invalid,live.radio).is_empty() and live.encounter.snapshot()==before,"Invalid rescue partially changed combat")
	check(live.encounter.evaluate_kappa_sequence(live.rescue,Radio.new()).is_empty(),"Unconfigured radio changed the rescue")
	check(live.encounter.snapshot()==before and live.rescue.snapshot().phase==0,"Rejected observations mutated accepted owners")

func verify_provocation(source: Dictionary) -> void:
	var live:=source.duplicate();live.rescue=source.rescue.fork();live.radio=source.radio.fork_for_frame()
	var held: Dictionary=source.encounter.snapshot()
	live.pose=Transform3D(Basis.IDENTITY,live.encounter.combat_snapshot().actors[1].position-Vector3(0,0,400))
	var original: Dictionary=live.encounter.combat_snapshot().actors[1].vitals
	# A light hit only warns. Keep actual contacts and NPC projections until
	# the original accumulated-damage retaliation threshold is crossed.
	for i in 400:
		if not primary_fire(live) or not weapon_pass(live,16) or not world_pass(live,0):return
		if live.encounter.combat_snapshot().actors[1].hostile:break
	var struck: Dictionary=live.encounter.combat_snapshot().actors[1]
	check(struck.vitals!=original and struck.vitals.hull>0 and struck.hostile,"Real primary contacts failed to provoke a surviving escort")
	# The next early contact precedes choreography and the later NPC pass.
	# Its newer pools must replace the controller's preceding combat view.
	for i in 100:
		if not primary_fire(live) or not weapon_pass(live,16):return
		if live.encounter.combat_snapshot().actors[1].vitals!=struck.vitals:break
	var before: Dictionary=live.encounter.snapshot();var random: Dictionary=live.random_state.duplicate(true)
	check(before.controller.combat.actors[1].vitals!=before.combat.actors[1].vitals,"Cue retention case did not include a contact since the last NPC pass")
	if not mission_pass(live):return
	var after: Dictionary=live.encounter.snapshot()
	check(live.rescue.snapshot().phase==0 and live.rescue.snapshot().force_hostile_actor_ids==[1,2,3],"Actual escort provocation skipped the radio phase or lost the group cue")
	check(after.combat.actors.map(func(row):return row.vitals)==before.combat.actors.map(func(row):return row.vitals) and after.combat.reputation==before.combat.reputation,"Choreography restored damaged hull or lost earned hit history")
	check(after.controller.accounting==before.controller.accounting and after.controller.flight==before.controller.flight and live.random_state==random,"Provocation cues advanced motion, accounting or randomness")
	check(source.encounter.snapshot()==held and not source.radio.snapshot().started.any(func(flag):return flag),"A rejected alternative contact branch mutated the accepted encounter")

func verify_retirement(live: Dictionary,bindings: RefCounted,lib: RefCounted) -> void:
	for i in 600:
		if not primary_fire(live) or not weapon_pass(live,150):return
		if live.encounter.combat_snapshot().actors[0].vitals.hull<=0:break
	check(live.encounter.combat_snapshot().actors[0].vitals.hull<=0,"Real primary contacts did not destroy the disabled kidnapper")
	if not mission_pass(live):return
	check(live.rescue.poll_outcome(false).is_empty(),"Zero hull failed the rescue before native retirement")
	if not world_pass(live,0) or not mission_pass(live):return
	check(live.encounter.combat_snapshot().actors[0].actor_mode==3 and live.rescue.poll_outcome(false).is_empty(),"Breakup was mistaken for the retired failure state")
	for i in 134:
		if not world_pass(live,150):return
		if live.encounter.combat_snapshot().actors[0].actor_mode==4:break
	if not result_observation(live):return
	check(live.encounter.combat_snapshot().actors[0].actor_mode==4 and live.rescue.poll_outcome(false)=="failed","Native retirement did not fail independently of completion polling")
	var accounting: Dictionary=live.encounter.snapshot().controller.accounting
	check(accounting.events.size()==1,"Native failure lost or duplicated the target's combat accounting")
	if Outcome.available(bindings):verify_result(live,bindings,lib,true)
	if not world_pass(live,150) or not mission_pass(live):return
	check(live.encounter.snapshot().controller.accounting==accounting,"A retained failure counted the target twice")

func verify_result(live: Dictionary,bindings: RefCounted,lib: RefCounted,failed: bool) -> void:
	var visit:=Visit.new()
	if not visit.configure_result(bindings,lib,21,Outcome.VALUES.mission):check(false,visit.error);return
	check(visit.poll_result(live.rescue,false) and visit.snapshot().dialogue.visible==failed,"Live result ignored completion eligibility or gated failure")
	check(visit.poll_result(live.rescue,true) and visit.snapshot().dialogue.visible and visit.transition().is_empty(),"The result advanced without acknowledgement")
	check(visit.matches_result_observation(live.rescue),"The result did not retain the actual encounter observation")
	check(visit.navigate("next"),visit.error)
	var receipt:=visit.transition()
	if failed:check(receipt.get("outcome")=="failed" and receipt.get("source_state")==1 and not receipt.has("campaign_cursor") and receipt.get("reward_credits")==0,"Failure acknowledgement advanced the story or paid a reward")
	else:check(receipt.get("outcome")=="completed" and receipt.get("campaign_cursor")==22 and receipt.get("mission",{}).get("station_id")==55 and receipt.get("reward_credits")==0,"Success lost the original return receipt")

func radio_at(live: Dictionary,at: int) -> Array:
	var context: Dictionary=live.encounter.kappa_radio_context(live.route)
	if context.is_empty():check(false,live.encounter.error);return []
	var events: Array=live.radio.step_kappa_rescue(at,context)
	check(live.radio.error.is_empty(),live.radio.error)
	return events

func finish_radio(live: Dictionary,event: int,at: int,counts: Array) -> int:
	check(radio_at(live,at+2001)==[{"kind":"display","event":event,"text_id":_radio_text_ids[event]}],"Native radio displayed another line")
	var end:=at+3500+2000*int(counts[event])+1
	check(radio_at(live,end)==[{"kind":"finished","event":event}],"Native radio did not finish its original line")
	return end

func mission_pass(live: Dictionary) -> bool:
	var operation: Dictionary=live.encounter.evaluate_kappa_sequence(live.rescue,live.radio)
	if operation.is_empty():check(false,live.encounter.error);return false
	live.merge(operation,true)
	return true

func result_observation(live: Dictionary) -> bool:
	var encounter: Dictionary=live.encounter.snapshot();var prior: Dictionary=live.rescue.snapshot()
	var observed: RefCounted=live.encounter.observe_kappa_rescue(live.rescue,live.radio)
	if observed==null:check(false,live.encounter.error);return false
	check(live.encounter.snapshot()==encounter and live.rescue.snapshot()==prior,"Early result polling committed later choreography")
	live.rescue=observed
	return true

func world_pass(live: Dictionary,milliseconds: int) -> bool:
	var operation: Dictionary=live.encounter.evaluate_world(live.player,live.pose,milliseconds,live.random_state)
	if operation.is_empty():check(false,live.encounter.error);return false
	live.merge(operation,true)
	return true

func weapon_pass(live: Dictionary,milliseconds: int) -> bool:
	var operation: Dictionary=live.encounter.evaluate_weapons(live.player,live.pose,milliseconds,live.scenery,live.random_state,false,false)
	if operation.is_empty():check(false,live.encounter.error);return false
	live.merge(operation,true)
	return true

func primary_fire(live: Dictionary) -> bool:
	var operation: Dictionary=live.encounter.evaluate_primary_fire(live.player,live.pose,true,true,live.random_state)
	if operation.is_empty():check(false,live.encounter.error);return false
	live.merge(operation,true)
	return true
