extends "res://tests/contract_flight_results.gd"
## Actual accepted/generated debris with explicit lethal hits and clock inputs.
## Independent drop traces cover the native world RNG; no playable unlock claim.
const JunkRules=preload("res://src/content/contract_junk_definitions.gd")
const JunkEmitter=preload("res://src/simulation/damage_particle_emitter.gd")
var _junk_vectors:={}
var _junk_populations:=0
var _junk_drops:=0
var _junk_empty:=0
var _junk_deadlines:=false

func after_encounter_population(bindings: RefCounted,cat: RefCounted,owner: RefCounted,vector: Dictionary,equipment: RefCounted,contracts: RefCounted) -> void:
	super.after_encounter_population(bindings,cat,owner,vector,equipment,contracts)
	if int(vector.kind)!=7:return
	var controller:=LifeControl.new();var player:=LifePlayer.new();var resources:=LifeResources.new()
	if not JunkRules.available(bindings):
		check(not controller.configure_contract(bindings,cat,owner,equipment),"An earlier pack enabled Junk lifecycle")
		return
	if _junk_vectors.is_empty():
		var file:=FileAccess.open(OS.get_environment("GOF2_CONTRACT_JUNK_VECTORS"),FileAccess.READ)
		if file==null or file.get_length()>1024*1024:check(false,"Supply the independent Junk vectors");return
		var value: Variant=JSON.parse_string(file.get_as_text())
		if not value is Dictionary or not value.get("populations") is Array or value.populations.size()!=20 or not value.get("boundaries") is Array or value.boundaries.size()!=3:check(false,"Junk vectors are incomplete");return
		_junk_vectors=value
	if _life_library==null:
		_life_library=Library.new()
		if not _life_library.open(OS.get_cmdline_user_args()[0]):check(false,_life_library.error);return
	if not controller.configure_contract(bindings,cat,owner,equipment) or not player.configure_contract(bindings,cat,equipment,owner):check(false,controller.error+player.error);return
	var target:=player_fixture(bindings,Vector3.ZERO)
	check(controller.advance(1,target).is_empty(),"Unprepared Junk destruction allowed an actor update")
	if not resources.configure_contract(_life_library,bindings,owner) or not controller.set_destruction(bindings,resources):check(false,resources.error+controller.error);return
	var before: Dictionary=controller.snapshot()
	check(before.combat.actors.size() in [17,19] and before.combat.actors.all(func(actor):return actor.vitals.hull==1 and actor.half_extent==1000 and actor.actor_mode==0 and actor.active and actor.hostile),"Junk borrowed a ship hull, activity state or collision bounds")
	check(before.flight.all(func(value):return value.is_empty()) and before.guidance.all(func(value):return value.is_empty()),"Stationary Junk borrowed ship movement or guidance")
	var weapons:=ShipWeapons.new()
	if not weapons.configure_contract(bindings,cat,owner):check(false,weapons.error);return
	check(weapons.snapshot().actors.all(func(actor):return actor.projectiles.is_empty() and actor.definition.unarmed),"Junk received ship guns")
	var contact: Dictionary=weapons.evaluate_combat_training_update(player,Transform3D.IDENTITY,controller.combat_owner(),false,16)
	check(not contact.is_empty() and contact.player.snapshot()==player.snapshot() and contact.actors.is_empty(),"Unarmed Junk altered player pools or produced contacts")
	var stepped:=controller.evaluate(controller.combat_owner(),weapons,16,target,before.random_state)
	if stepped.is_empty():check(false,controller.error);return
	check(stepped.controller.snapshot().combat.actors==before.combat.actors and stepped.random_state==before.random_state,"Living debris moved or consumed random values")
	check(stepped.actors.all(func(actor):return actor.movement.is_empty() and actor.firing.is_empty()),"A Junk frame emitted movement or firing events")
	verify_primary_contact(bindings,cat,player,controller,target)
	var matching: Array=_junk_vectors.populations.filter(func(row):return int(row.seed)==int(vector.seed) and int(row.difficulty)==int(vector.difficulty) and float(row.game)==float(vector.game) and int(row.faction)==int(vector.faction))
	if matching.size()!=1:check(false,"Junk population lacks a unique independent trace");return
	var expected: Dictionary=matching[0]
	check(int(expected.initial_state)==before.random_state.state,"Junk drop fixture lost the actual constructor RNG")
	var session: RefCounted=contracts.fork()
	if not session.bind_flight(controller):check(false,session.error);return
	var combat: RefCounted=controller.combat_owner()
	if not combat.begin_contact_pass(before.random_state,true):check(false,combat.error);return
	for id in before.combat.actors.size():
		var hit: Dictionary=combat.normal_hit(id,1,id%2==1)
		if hit.is_empty():check(false,combat.error);return
		check(hit.destroyed_now and combat.snapshot().actors[id].actor_mode==0,"A lethal hit skipped the debris update")
	check(combat.current_reputation()==contracts.snapshot().reputation and combat.snapshot().reputation.events.is_empty(),"Debris damage changed faction standing")
	check(combat.contact_random_state()==before.random_state and not controller.defeat_status().satisfied,"Debris damage consumed a provocation draw or completed early")
	var result: Dictionary=controller.advance(0,target,combat)
	if result.is_empty():check(false,controller.error);return
	var destroyed: Dictionary=controller.snapshot()
	var count: int=before.combat.actors.size()
	check(result.death_events.size()==count and destroyed.defeat_status.satisfied,"Junk did not resolve every debris in its lethal update")
	check(destroyed.combat.actors.all(func(actor):return actor.actor_mode==4 and not actor.model_draw_enabled),"Junk used a ship tumble phase or retained its model")
	for id in count:
		var event: Dictionary=result.death_events[id]
		var life: Dictionary=event.state
		var quantity:=int(expected.drops[id].quantity)
		var entries:=[] if quantity==0 else [{"item_id":99,"quantity":quantity}]
		check(life.actor_id==id and life.cargo.entries==entries and event.random_state.state==int(expected.drops[id].random_state),"Junk drop or quantity differs from the independent stream")
		check(life.cargo.model_id==16990 and life.active==(quantity>0) and life.cargo.model_exists==(quantity>0) and event.clear_selected_target==(quantity==0),"Junk cargo lost its Midorian container or target/activity behavior")
		check(life.pose==before.combat.actors[id].body_pose and life.cargo.pose==life.pose and life.cargo.rotation_radians==Vector3.ZERO,"Junk cargo changed the stationary source pose")
		check(event.sound_events==[22] and event.bursts==[{"preset_id":21,"member_index":0,"count":1,"size_override":-1,"position":life.pose.origin}],"Junk lost its original death sound or manual burst")
		if quantity>0:_junk_drops+=1
		else:_junk_empty+=1
	var totals: Dictionary=destroyed.accounting.counter_deltas
	check(totals.debris_destroyed==count and totals.hostile_remaining==-count,"Junk lost its distinct destruction counter")
	for key in ["hostile_deaths","world_player_kills","world_other_kills","player_kills","pirate_kills","nonhostile_remaining"]:check(totals[key]==0,"Debris incorrectly changed "+key)
	check(destroyed.random_state.state==int(expected.random_state),"Junk introduced an extra world RNG draw")
	var repeated: Dictionary=controller.advance(16,target)
	check(not repeated.is_empty() and repeated.death_events.is_empty() and controller.snapshot().accounting==destroyed.accounting and repeated.random_state==destroyed.random_state,"Repeated debris update replayed destruction")
	if not advance_result_to(controller,target,5001):return
	result=session.evaluate_flight(controller)
	if result.is_empty():check(false,session.error);return
	check(result.opened and result.session.snapshot().completed_side_missions==contracts.snapshot().completed_side_missions+1,"Destroyed debris did not earn its contract result")
	verify_junk_settlement(contracts,result,true,count)
	if not _junk_deadlines:
		verify_drop_boundaries(owner,bindings,cat,resources)
		verify_deadlines(bindings,cat,owner,equipment,contracts,resources,target)
		verify_burst(bindings)
		_junk_deadlines=true
	check(owner.snapshot().random_state==before.random_state,"Junk updates changed the retained constructor")
	_junk_populations+=1

func verify_junk_settlement(original: RefCounted,operation: Dictionary,success: bool,debris_count: int) -> void:
	var session: RefCounted=operation.session;var controller: RefCounted=operation.controller
	var prior: Dictionary=original.snapshot();var pending: Dictionary=session.snapshot();var frozen: Dictionary=controller.snapshot()
	check(pending.pending_result.completed==success and pending.pending_result.failed==not success,"Junk result confused completion and failure")
	check(pending.credits==prior.credits and pending.progress.player_kills==prior.progress.player_kills and pending.progress.pirate_kills==prior.progress.pirate_kills,"Junk result paid early or granted ship kills")
	check(pending.progress.debris_destroyed==prior.progress.debris_destroyed+debris_count and pending.progress.other_score==prior.progress.other_score+(2 if success else 0),"Junk result lost debris progress or granted failure score")
	var expected: Dictionary=prior.reputation.duplicate(true)
	if success:expected.axes[1]=maxi(-100,expected.axes[1]-5)
	check(pending.reputation==expected,"Junk result standing used ship kill changes or rewarded failure")
	check(controller.advance(1,{}).is_empty() and controller.snapshot()==frozen,"Junk result failed to freeze its flight")
	var repeat: Dictionary=session.evaluate_flight(controller)
	check(not repeat.is_empty() and not repeat.opened and repeat.session.snapshot()==pending,"Repeated Junk polling changed its count or standing")
	check(session.acknowledge_flight_result(controller,pending.pending_result.serial+1).is_empty(),"Wrong serial acknowledged a Junk result")
	var closed: Dictionary=session.acknowledge_flight_result(controller,pending.pending_result.serial)
	if closed.is_empty():check(false,session.error);return
	var settled: Dictionary=closed.session.snapshot()
	var payment:=int(prior.mission.reward)+int(prior.mission.bonus) if success else 0
	check(settled.credits==prior.credits+payment and settled.last_result.credit_delta==payment,"Junk acknowledgement used a Challenge penalty or incorrect reward")
	check(settled.mission.is_empty() and settled.offers[prior.active_offer_id].consumed and settled.campaign_cursor==13,"Junk acknowledgement restored the offer or advanced the separate story")
	check(settled.progress==pending.progress and settled.completed_side_missions==prior.completed_side_missions+(1 if success else 0),"Junk acknowledgement duplicated career changes")
	check(closed.controller.snapshot().combat.actors==frozen.combat.actors and closed.controller.snapshot().destruction==frozen.destruction and closed.controller.snapshot().random_state==frozen.random_state,"Junk acknowledgement discarded debris/cargo or RNG")
	check(closed.controller.defeat_status().is_empty() and closed.clear_player_control and closed.clear_world_path,"Junk acknowledgement retained its objective")
	check(closed.session.acknowledge_flight_result(closed.controller,pending.pending_result.serial).is_empty(),"Junk paid twice")
	var finished: RefCounted=closed.session.finish_flight(closed.controller)
	check(finished!=null and finished.snapshot().progress==settled.progress and not finished.snapshot().has("flight"),"Junk arrival release lost its retained career")

func verify_drop_boundaries(owner: RefCounted,bindings: RefCounted,cat: RefCounted,resources: RefCounted) -> void:
	for vector in _junk_vectors.boundaries:
		# An explicit stream at the debris update boundary isolates inclusive9,
		# excluded10 and quantities1/10 without changing the accepted mission.
		var life: RefCounted=preload("res://src/simulation/debris_destruction.gd").new()
		if not life.configure(bindings,resources,owner,0):check(false,life.error);return
		var actor:=preload("res://src/simulation/opening_combat_actor.gd").new()
		if not actor.configure_contract(bindings,cat,owner,0) or not actor.enable_contract_combat(bindings):check(false,actor.error);return
		if actor.normal_hit(1,false).is_empty():check(false,actor.error);return
		var result: Dictionary=life.advance(0,{"state":int(vector.initial_state)},actor.snapshot())
		if result.is_empty() or not actor.apply_debris_destruction(life):check(false,life.error+actor.error);return
		check(result.random_state.state==int(vector.random_state) and result.state.active==(int(vector.quantity)>0),"Exact drop eligibility boundary changed")
		if int(vector.quantity)>0:check(result.state.cargo.entries==[{"item_id":99,"quantity":int(vector.quantity)}],"Exact cargo quantity boundary changed")
		var cargo: Dictionary=life.snapshot().cargo
		for frame in 410:
			result=life.advance(150,result.random_state,actor.snapshot())
			if result.is_empty():check(false,life.error);return
		check(life.snapshot().active==(int(vector.quantity)>0) and life.snapshot().cargo==cargo and result.random_state.state==int(vector.random_state),"Junk acquired ship cargo drift, rotation or 60-second cleanup")
		check(not result.started and result.sound_events.is_empty() and result.bursts.is_empty(),"Retained cargo replayed its death effects")

func verify_deadlines(bindings: RefCounted,cat: RefCounted,owner: RefCounted,equipment: RefCounted,contracts: RefCounted,resources: RefCounted,target: Dictionary) -> void:
	for variant in ["equality","success","radio","partial"]:
		var controller:=LifeControl.new();var session: RefCounted=contracts.fork()
		if not controller.configure_contract(bindings,cat,owner,equipment) or not controller.set_destruction(bindings,resources) or not session.bind_flight(controller):check(false,controller.error+session.error);return
		var destroyed:=0
		if variant!="equality":
			var combat: RefCounted=controller.combat_owner()
			destroyed=1 if variant=="partial" else combat.snapshot().actors.size()
			for id in destroyed:
				if combat.normal_hit(id,1,false).is_empty():check(false,combat.error);return
			if controller.advance(0,target,combat).is_empty():check(false,controller.error);return
		if not advance_result_to(controller,target,121000):return
		var operation: Dictionary
		if variant=="equality":
			operation=session.evaluate_flight(controller)
			if operation.is_empty():check(false,session.error);return
			check(not operation.opened and operation.controller.snapshot().contract_result.clock_ms==0,"The deadline fired at equality")
			session=operation.session;controller=operation.controller
			if not advance_result_to(controller,target,126000):return
			operation=session.evaluate_flight(controller)
			check(not operation.is_empty() and not operation.opened,"Expired Junk bypassed the periodic poll threshold")
		if controller.advance(1,target).is_empty():check(false,controller.error);return
		operation=session.evaluate_flight(controller,variant=="radio")
		if operation.is_empty():check(false,session.error);return
		check(operation.opened,"Eligible deadline or success did not open its result")
		verify_junk_settlement(contracts,operation,variant=="success",destroyed)
		if variant!="success":check(operation.controller.snapshot().contract_result.clock_ms==0,"Junk failure did not reset the periodic clock")

func verify_burst(bindings: RefCounted) -> void:
	var emitter:=JunkEmitter.new()
	if not emitter.configure_junk(bindings,17):check(false,emitter.error);return
	var before: Dictionary=emitter.snapshot()
	check(before.preset.preset_id==21 and before.preset.material_id==20099 and before.preset.size==1600 and before.preset.size_jitter==200 and before.preset.lifetime_ms==1000,"Junk burst lost its original inherited preset")
	if emitter.emit_once(Vector3(10,20,30)).has("error"):check(false,emitter.error);return
	var state: Dictionary=emitter.snapshot()
	check(state.cursor==1 and state.slots[0].position==Vector3(10,20,30) and state.slots[0].velocity==Vector3.ZERO and state.slots[0].appearance.size>=1600 and state.slots[0].appearance.size<1800,"Junk manual sprite changed its placement, velocity or size")
	check(state.slots.slice(1)==before.slots.slice(1) and state.remainder_ms==before.remainder_ms and state.baseline==before.baseline,"Junk manual sprite changed another slot or emitter clock")
	for _frame in 10:
		if emitter.advance(Transform3D.IDENTITY,100,100).has("error"):check(false,emitter.error);return
	check(emitter.snapshot().slots[0].appearance.age_ms==1000,"Junk sprite expired at lifetime equality")
	if emitter.advance(Transform3D.IDENTITY,1,10).has("error"):check(false,emitter.error);return
	check(emitter.snapshot().slots[0].appearance.age_ms==-1,"Junk sprite did not expire after its original lifetime")

func finish_ship_checks(bindings: RefCounted) -> void:
	super.finish_ship_checks(bindings)
	if JunkRules.available(bindings):
		check(_junk_populations==20 and _junk_deadlines,"Junk did not cover every accepted early population and deadline branch")
		check(_junk_drops>0 and _junk_empty>0,"Junk did not exercise both cargo outcomes")
	print("Junk contracts: %d populations; %d cargo drops; %d empty debris"%[_junk_populations,_junk_drops,_junk_empty])
