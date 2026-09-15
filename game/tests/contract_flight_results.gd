extends "res://tests/contract_ship_lifecycle.gd"
## Uses retained accepted contacts and real ship/death owners from the shared
## fixture. Direct lethal hits and player placements are component inputs.
const ResultRules=preload("res://src/content/contract_flight_result_definitions.gd")
var _result_session: RefCounted
var _result_successes:=0
var _result_failures:=0
var _consecutive_results:=false

func after_contract_intro(bindings: RefCounted,cat: RefCounted,library: RefCounted,station: RefCounted) -> void:
	var original: RefCounted=station.fork()
	super.after_contract_intro(bindings,cat,library,station)
	if ResultRules.available(bindings):verify_consecutive_results(bindings,cat,library,original)

func verify_consecutive_results(bindings: RefCounted,cat: RefCounted,library: RefCounted,station: RefCounted) -> void:
	if not station.open_contracts(bindings,cat):check(false,station.error);return
	var session: RefCounted=station._contracts.fork()
	var equipment: RefCounted=station.equipment_owner()
	var initial: Dictionary=session.snapshot()
	var credits:=int(initial.credits)
	# The offer choices and local arrivals are explicit fixtures. Each job
	# still constructs, destroys and settles its own accepted population.
	for id in 4:
		var career: Dictionary=session.snapshot()
		var offer:=Offer.new()
		var context:={"campaign_cursor":13,"station_id":79,"rank":career.rank,"reputation":career.reputation,"client_faction":3}
		var choices:={"kind_index":3,"difficulty_index":id%2,"destination_station_id":75,"cargo_description_index":0}
		if not offer.configure(bindings,cat,context,choices) or not session.register_offer(id,offer):check(false,offer.error+session.error);return
		equipment=session.accept(id,equipment)
		if equipment==null:check(false,session.error);return
		var accepted: Dictionary=session.snapshot()
		var arrival:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":13,"from_station_id":79,"station_id":75,"system_id":15,"source_state":2,"world_type":3,"audio_selector":1}
		if not equipment.relocate_local_arrival(bindings,cat,arrival):check(false,equipment.error);return
		var construction:=NPCConstruction.new();var random:=Random.new();random.seed_from(id)
		if not construction.configure_contract(bindings,cat,equipment,session,Vector3.ZERO,Vector3.ZERO) or construction.generate(random.snapshot()).is_empty():check(false,construction.error);return
		var controller:=LifeControl.new();var resources:=LifeResources.new()
		if not controller.configure_contract(bindings,cat,construction,equipment) or not resources.configure_contract(library,bindings,construction) or not controller.set_destruction(bindings,resources) or not session.bind_flight(controller):check(false,controller.error+resources.error+session.error);return
		var target:={}
		for actor_id in construction.snapshot().actors.size():
			target=player_fixture(bindings,controller.combat_owner().snapshot().actors[actor_id].pose.origin+Vector3(0,0,20000))
			for _frame in 2:
				if controller.advance(16,target).is_empty():check(false,controller.error);return
		var combat: RefCounted=controller.combat_owner()
		if not combat.begin_contact_pass(controller.snapshot().random_state,true):check(false,combat.error);return
		for actor in combat.snapshot().actors:
			if combat.normal_hit(actor.actor_id,actor.vitals.hull,false).is_empty():check(false,combat.error);return
		if controller.advance(0,target,combat).is_empty():check(false,controller.error);return
		if not advance_result_to(controller,target,5001):return
		var result: Dictionary=session.evaluate_flight(controller)
		if result.is_empty():check(false,session.error);return
		check(result.opened and result.session.snapshot().completed_side_missions==id+1,"A consecutive earned contract lost its success count")
		session=result.session;controller=result.controller
		check(session.snapshot().credits==credits,"A consecutive contract paid before acknowledgement")
		result=session.acknowledge_flight_result(controller,id+1)
		if result.is_empty():check(false,session.error);return
		session=result.session;controller=result.controller
		credits+=int(accepted.mission.reward)+int(accepted.mission.bonus)
		check(session.snapshot().credits==credits and session.snapshot().result_serial==id+1,"A consecutive contract lost its wallet or result serial")
		var finished: RefCounted=session.finish_flight(controller)
		if finished==null:check(false,session.error);return
		session=finished
		arrival.from_station_id=75;arrival.station_id=79
		if not equipment.relocate_local_arrival(bindings,cat,arrival):check(false,equipment.error);return
	var completed: Dictionary=session.snapshot()
	check(completed.completed_side_missions==4 and completed.progress.other_score==initial.progress.other_score+8 and completed.campaign_cursor==13,"Four actual results changed the story cursor or lost success score")
	check(completed.offers.size()==4 and completed.offers.values().all(func(row):return row.consumed),"Repeated jobs restored an earlier consumed contact")
	check(station.snapshot().mission.kind==150 and station.snapshot().completed_side_missions==0,"A component fixture fabricated the later campaign unlock")
	_consecutive_results=true

func after_lifecycle_prepared(bindings: RefCounted,contracts: RefCounted,controller: RefCounted) -> void:
	_result_session=contracts.fork()
	if not ResultRules.available(bindings):
		check(not _result_session.bind_flight(controller),"An earlier pack enabled flight settlement")
		_result_session=null
		return
	if not _result_session.bind_flight(controller):check(false,_result_session.error);_result_session=null;return
	check(not _result_session.bind_flight(controller),"A bound flight replaced its own ledger")
	check(_result_session.finish_flight(controller)==null,"An unsettled flight released its ledger")
	var before: Dictionary=_result_session.snapshot()
	var result: Dictionary=_result_session.evaluate_flight(controller)
	check(not result.is_empty() and not result.opened,"An empty encounter awarded a result")
	check(_result_session.snapshot()==before,"Detached result polling changed the retained session")

func after_lifecycle_outcome(bindings: RefCounted,contracts: RefCounted,original: RefCounted,target: Dictionary,equipment: RefCounted) -> void:
	if _result_session==null:return
	var session: RefCounted=_result_session.fork()
	var controller: RefCounted=original.fork_for_frame()
	var before: Dictionary=session.snapshot();var initial: Dictionary=original.snapshot()
	var success: bool=original.defeat_status().satisfied
	var totals: Dictionary=initial.accounting.counter_deltas
	var kind:=int(before.mission.kind)
	check(controller.snapshot().contract_result.elapsed_ms<5000,"The fixture no longer covers immediate Challenge failure")
	var stale: RefCounted=controller.fork_for_frame()
	var read: Dictionary=session.evaluate_flight(controller,true)
	if read.is_empty():check(false,session.error);return
	check(read.opened==not success,"Controller failure incorrectly waited for the success clock or idle radio")
	check(session.snapshot()==before and controller.snapshot()==initial,"Result polling partially changed retained owners")
	session=read.session;controller=read.controller
	check(session.snapshot().progress.player_kills==before.progress.player_kills+totals.player_kills and session.snapshot().progress.pirate_kills==before.progress.pirate_kills+totals.pirate_kills,"The result lost actual kill credit")
	if success:
		check(session.snapshot().completed_side_missions==before.completed_side_missions and session.snapshot().progress.other_score==before.progress.other_score,"Early result polling counted an unacknowledgeable success")
		if not advance_result_to(controller,target,5000):return
		read=session.evaluate_flight(controller)
		if read.is_empty():check(false,session.error);return
		check(not read.opened,"Success opened at 5000ms equality")
		session=read.session;controller=read.controller
		if controller.advance(1,target).is_empty():check(false,controller.error);return
		read=session.evaluate_flight(controller,true)
		if read.is_empty():check(false,session.error);return
		check(not read.opened and read.controller.snapshot().contract_result.clock_ms==0,"Radio did not defer success and reset its periodic poll")
		session=read.session;controller=read.controller
		read=session.evaluate_flight(controller,false)
		check(not read.is_empty() and not read.opened,"Radio completion skipped the next source polling interval")
		if not advance_result_to(controller,target,10001):return
		read=session.evaluate_flight(controller)
		if read.is_empty():check(false,session.error);return
		check(not read.opened,"The recurring timer released one millisecond early")
		session=read.session;controller=read.controller
		if controller.advance(1,target).is_empty():check(false,controller.error);return
		read=session.evaluate_flight(controller)
		if read.is_empty():check(false,session.error);return
		check(read.opened,"The actual exploded pirates did not open their earned result")
		session=read.session;controller=read.controller
	var pending: Dictionary=session.snapshot();var frozen: Dictionary=controller.snapshot()
	check(pending.pending_result.completed==success and pending.pending_result.failed==not success and pending.pending_result.mode==(1 if success else 2),"Result confused failed and completed missions")
	check(pending.completed_side_missions==before.completed_side_missions+(1 if success else 0) and pending.progress.other_score==before.progress.other_score+(2 if success else 0),"Flight completion counted at the wrong phase or rewarded failure")
	check(pending.credits==before.credits and pending.campaign_cursor==13 and pending.mission==before.mission,"Opening a result paid or changed the story/side slot early")
	if not success:
		# Explicit funded-wallet fixture supplements the real zero-credit loss.
		var funded: RefCounted=session.fork()
		funded._state.credits=int(before.mission.reward)+725
		var debit: Dictionary=funded.acknowledge_flight_result(controller,pending.pending_result.serial)
		check(not debit.is_empty() and debit.session.snapshot().credits==725,"A funded Challenge loss did not subtract the base stake")
	var standing: Dictionary=initial.combat.current_reputation.duplicate(true)
	if success and kind==4:standing.axes[1]=maxi(-100,standing.axes[1]-5)
	check(pending.reputation==standing and frozen.combat.current_reputation==standing,"Result bonus missed the client faction or applied to Challenge")
	check(controller.advance(1,target).is_empty() and controller.snapshot()==frozen,"A modal result allowed flight motion")
	check(session.acknowledge_delivery_result(equipment)==null and not session.poll_station(equipment),"A flight result leaked into station delivery settlement")
	check(session.acknowledge_flight_result(controller,pending.pending_result.serial+1).is_empty(),"Wrong acknowledgement serial paid a flight result")
	check(session.acknowledge_flight_result(stale,pending.pending_result.serial).is_empty(),"An old flight paid the current result")
	var repeat: Dictionary=session.evaluate_flight(controller)
	check(not repeat.is_empty() and not repeat.opened and repeat.session.snapshot()==pending and repeat.controller.snapshot()==frozen,"Repeated result polling duplicated count, reputation or payment")
	read=session.acknowledge_flight_result(controller,pending.pending_result.serial)
	if read.is_empty():check(false,session.error);return
	check(session.snapshot()==pending and controller.snapshot()==frozen,"Detached acknowledgement changed the pending owners")
	session=read.session;controller=read.controller
	var settled: Dictionary=session.snapshot();var flight: Dictionary=controller.snapshot()
	var delta:=int(before.mission.reward)+int(before.mission.bonus) if success else -int(before.mission.reward)
	check(settled.credits==maxi(0,int(before.credits)+delta) and settled.last_result.credit_delta==delta,"Acknowledgement used the wrong success payment or base Challenge penalty")
	check(settled.mission.is_empty() and settled.active_offer_id==-1 and settled.pending_result.is_empty() and settled.offers[before.active_offer_id].consumed,"Acknowledgement lost the consumed contact or retained an active side slot")
	check(settled.last_result.notification_sound_id==(36 if success else -1) and not settled.last_result.acknowledgement_required,"Acknowledgement lost the original earned-credit notification")
	check(settled.completed_side_missions==pending.completed_side_missions and settled.progress==pending.progress,"Acknowledgement repeated career rewards")
	check(flight.combat.actors==frozen.combat.actors and flight.destruction==frozen.destruction and flight.random_state==frozen.random_state and flight.flight==frozen.flight and flight.guidance==frozen.guidance,"Closing the result reset ships, cargo, motion, guidance or RNG")
	check(flight.defeat_status.is_empty() and flight.combat.provocation.active_mission_kind==-1 and read.clear_player_control and read.clear_world_path,"Acknowledgement retained an objective or active mission reaction gate")
	check(session.acknowledge_flight_result(controller,pending.pending_result.serial).is_empty(),"The settled flight paid twice")
	check(session.evaluate_flight(stale).is_empty(),"A settled career accepted an earlier combat history")
	if kind==12:
		var combat: RefCounted=controller.combat_owner()
		if not combat.begin_contact_pass(flight.random_state,true):check(false,combat.error);return
		var hit: Dictionary=combat.normal_hit(0,9999999,false)
		if hit.is_empty():check(false,combat.error);return
		check(hit.destroyed_now and hit.reactions.size()==2,"Closing the result did not restore ordinary warning/response radio")
		if controller.advance(0,target,combat,combat.contact_random_state()).is_empty():check(false,controller.error);return
		standing.axes[1]=mini(100,standing.axes[1]+5)
		check(controller.combat_owner().current_reputation()==standing,"A later lethal hit replayed reputation before the result checkpoint")
	else:
		if controller.advance(16,target).is_empty():check(false,controller.error);return
	read=session.evaluate_flight(controller,true)
	if read.is_empty():check(false,session.error);return
	check(not read.opened and read.session.snapshot().credits==settled.credits and read.session.snapshot().completed_side_missions==settled.completed_side_missions,"Continuing flight repeated the settled result")
	session=read.session;controller=read.controller
	var released: RefCounted=session.finish_flight(controller)
	check(released!=null and not released.snapshot().has("flight") and released.snapshot().progress==session.snapshot().progress,"Releasing the flight lost its last combat progress")
	check(original.snapshot()==initial and contracts.snapshot().credits==before.credits,"Result component mutated its retained source fixture")
	if success:_result_successes+=1
	else:_result_failures+=1

func advance_result_to(controller: RefCounted,target: Dictionary,elapsed: int) -> bool:
	while controller.snapshot().contract_result.elapsed_ms<elapsed:
		var step:=mini(150,elapsed-int(controller.snapshot().contract_result.elapsed_ms))
		if controller.advance(step,target).is_empty():check(false,controller.error);return false
	return true

func finish_ship_checks(bindings: RefCounted) -> void:
	super.finish_ship_checks(bindings)
	if ResultRules.available(bindings):
		check(_consecutive_results,"Four consecutive earned results did not retain one career")
		check(_result_successes+_result_failures==30 and _result_successes>0 and _result_failures>0,"Accepted flight results did not exercise both earned and failed contracts")
		var history:=LifeReputation.new()
		if history.configure(bindings,13,[3,8,8,8],0.5):
			var actor:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"actor_id":1,"actor_kind":8,"vitals":{"hull":0},"nonplayer_kill":false}
			check(history.record_lethal(actor),history.error)
			actor.actor_id=0;actor.actor_kind=3
			check(history.record_lethal(actor),history.error)
			check(history.apply_to({"axes":[0,-95],"override":-1},1).axes==[0,-90],"A result checkpoint replayed an earlier pirate hit")
			check(history.apply_to({"axes":[0,0],"override":-1},3).is_empty(),"An invalid reputation checkpoint was accepted")
	print("Contract flight results: %d successes; %d failures"%[_result_successes,_result_failures])
