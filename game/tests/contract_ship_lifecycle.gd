extends "res://tests/contract_ship_combat.gd"
## Accepted offers and generated ships are real native owners. Player placements,
## direct lethal damage and deliberate overlapping shots are component fixtures.
## No contract payout, story completion or application flight is claimed here.
const LifeRules=preload("res://src/content/contract_ship_lifecycle_definitions.gd")
const LifeControl=preload("res://src/simulation/combat_training_control.gd")
const LifeResources=preload("res://src/content/npc_destruction_resources.gd")
const LifePlayer=preload("res://src/simulation/opening_player_state.gd")
const LifeReputation=preload("res://src/simulation/faction_reputation.gd")
const LifePrimary=preload("res://src/simulation/primary_weapons.gd")
const LifeMounts=preload("res://src/content/weapon_mounts.gd")
var _life_populations:=0
var _life_contacts:=0
var _life_library: RefCounted

func after_encounter_population(bindings: RefCounted,cat: RefCounted,owner: RefCounted,vector: Dictionary,equipment: RefCounted,contracts: RefCounted) -> void:
	super.after_encounter_population(bindings,cat,owner,vector,equipment,contracts)
	if int(vector.kind) not in [4,12]:return
	var controller:=LifeControl.new();var player:=LifePlayer.new();var resources:=LifeResources.new()
	if not LifeRules.available(bindings):
		check(not controller.configure_contract(bindings,cat,owner,equipment),"An earlier pack enabled contract lifecycle")
		return
	if _life_library==null:
		_life_library=Library.new()
		if not _life_library.open(OS.get_cmdline_user_args()[0]):check(false,_life_library.error);return
	var before: Dictionary=owner.snapshot();var inventory: Dictionary=equipment.snapshot()
	if not controller.configure_contract(bindings,cat,owner,equipment) or not player.configure_contract(bindings,cat,equipment,owner):check(false,controller.error+player.error);return
	var target:=player_fixture(bindings,before.actors[0].body_pose.origin+Vector3(0,0,20000))
	check(controller.advance(16,target).is_empty(),"Unprepared contract destruction allowed a live actor pass")
	if not resources.configure_contract(_life_library,bindings,owner) or not controller.set_destruction(bindings,resources):check(false,resources.error+controller.error);return
	check(not controller.set_destruction(bindings,resources),"Contract destruction reset its retained owners")
	check(controller.fork_for_frame().snapshot()==controller.snapshot(),"A detached contract controller changed its encounter")
	after_lifecycle_prepared(bindings,contracts,controller)
	if int(vector.kind)==12 and int(vector.seed)==0:verify_initial_rival_death(bindings,controller,target)
	# Proximity is reached by positioning the fixture player; actor activation,
	# target selection and physical movement still run through the shared pass.
	for id in before.actors.size():
		target=player_fixture(bindings,controller.combat_owner().snapshot().actors[id].pose.origin+Vector3(0,0,20000))
		for _frame in 2:
			if controller.advance(16,target).is_empty():check(false,controller.error);return
	var active: Dictionary=controller.snapshot()
	check(active.combat.actors.all(func(actor):return actor.active and actor.actor_mode==1),"Contract ships did not release through their native activity gates")
	check(active.combat.actors.all(func(actor):return actor.hostile==(actor.actor_kind==8)),"Source hostility was lost during flight")
	var weapons:=ShipWeapons.new()
	if not weapons.configure_contract(bindings,cat,owner):check(false,weapons.error);return
	var result:=controller.evaluate(controller.combat_owner(),weapons,16,target,controller.snapshot().random_state)
	if result.is_empty():check(false,controller.error);return
	controller=result.controller;weapons=result.weapons
	verify_primary_contact(bindings,cat,player,controller,target)
	if int(vector.kind)==12:verify_contact_order(bindings,controller,player,weapons)
	var challenge: bool=int(vector.kind)==12
	var begin:=1 if challenge else 0
	var credited: int=2 if challenge else before.actors.size()
	if challenge and int(vector.seed)%2==1:credited=1
	var combat: RefCounted=controller.combat_owner()
	if not combat.begin_contact_pass(controller.snapshot().random_state,true):check(false,combat.error);return
	for id in range(begin,before.actors.size()):
		var hit: Dictionary=combat.normal_hit(id,combat.snapshot().actors[id].vitals.hull,id-begin>=credited)
		check(not hit.is_empty() and hit.destroyed_now,"Fixture lethal hit failed")
	check(not controller.defeat_status().satisfied,"Lethal hull prematurely completed the contract")
	var start: Dictionary=controller.advance(0,target,combat)
	if start.is_empty():check(false,controller.error);return
	var totals: Dictionary=controller.snapshot().accounting.counter_deltas
	check(totals.hostile_deaths==before.actors.size()-begin and totals.world_player_kills==credited and totals.player_kills==credited and totals.pirate_kills==credited,"Contract deaths lost player/pirate credit")
	check(totals.world_other_kills==before.actors.size()-begin-credited and totals.nonhostile_remaining==0,"Rival/NPC kill attribution changed")
	check(not controller.defeat_status().satisfied and not controller.defeat_status().failed,"Tumbling ships prematurely resolved a contract")
	var expected_rep: Dictionary=before.contract_encounter.context.reputation.duplicate(true)
	expected_rep.axes[1]=maxi(-100,expected_rep.axes[1]-credited)
	check(controller.combat_owner().current_reputation()==expected_rep,"Player pirate hits changed the wrong reputation axis or included rival kills")
	for _frame in 25:
		if controller.advance(150,target).is_empty():check(false,controller.error);return
	var status:=controller.defeat_status()
	check(status.defeated==status.required and status.satisfied==(not challenge or credited==2) and status.failed==(challenge and credited==1),"Contract objective did not use destroyed mode and strict player majority")
	check(controller.snapshot().accounting.counter_deltas==totals,"Repeated death frames duplicated kill accounting")
	for id in range(begin,before.actors.size()):
		var life: Dictionary=controller.destruction_owner(id).snapshot()
		check(life.cargo.entries==before.actors[id].cargo and life.cargo.model_id==16993,"Explosion lost the generated pirate cargo or original container")
	after_lifecycle_outcome(bindings,contracts,controller,target,equipment)
	if int(vector.seed)==0:
		for _frame in 410:
			if controller.advance(150,target).is_empty():check(false,controller.error);return
		check(controller.snapshot().combat.actors.slice(begin).all(func(actor):return not actor.active and actor.actor_mode==4),"Contract cargo did not retire after the shared cleanup interval")
		check(controller.snapshot().accounting.counter_deltas==totals,"Retirement duplicated rewards or deaths")
	check(owner.snapshot()==before and equipment.snapshot()==inventory,"Combat changed retained construction, cargo or station equipment")
	_life_populations+=1

func verify_initial_rival_death(bindings: RefCounted,original: RefCounted,target: Dictionary) -> void:
	var controller: RefCounted=original.fork_for_frame();var combat: RefCounted=controller.combat_owner()
	var random: Dictionary=controller.snapshot().random_state
	check(combat.snapshot().actors[0].actor_mode==0,"Rival fixture no longer exercises initial-mode destruction")
	if not combat.begin_contact_pass(random,true):check(false,combat.error);return
	var hit: Dictionary=combat.normal_hit(0,9999999,false)
	if hit.is_empty():check(false,combat.error);return
	check(hit.destroyed_now and hit.reactions.is_empty() and combat.contact_random_state()==random,"An active contract emitted ordinary traffic warning radio or consumed its draw")
	var reaction: Dictionary=combat.snapshot().provocation
	check(reaction.forced_hostile==[true,false,false,false] and reaction.warning_issued and reaction.response_issued and reaction.station_response_flag,"Rival damage changed unrelated factions or missed the source once flags")
	if controller.advance(0,target,combat).is_empty():check(false,controller.error);return
	var state: Dictionary=controller.snapshot()
	check(not state.combat.actors[0].hostile and state.combat.actors[0].friendly and state.combat.actors[0].actor_mode==3,"Forced hostility overrode the authored rival friendship")
	check(state.accounting.counter_deltas.nonhostile_remaining==-1 and state.accounting.counter_deltas.player_kills==0 and state.accounting.counter_deltas.world_player_kills==0,"A nonhostile rival counted as a player objective kill")
	check(state.combat.reputation.events[0].change==5 and state.combat.reputation.events[0].axis==1,"Midorian rival lethal reputation was lost")
	check(not controller.defeat_status().satisfied and not controller.defeat_status().failed,"Destroying the rival substituted for the pirate objective")

func verify_primary_contact(bindings: RefCounted,cat: RefCounted,player: RefCounted,controller: RefCounted,target: Dictionary) -> void:
	var mounts:=LifeMounts.new();var primary:=LifePrimary.new()
	if not mounts.open(_life_library,cat) or not primary.configure(bindings,cat,mounts,player.loadout()):check(false,mounts.error+primary.error);return
	var combat: RefCounted=controller.combat_owner()
	if not combat.begin_contact_pass(controller.snapshot().random_state,true):check(false,combat.error);return
	var id: int=combat.snapshot().actors.size()-1
	var pose: Transform3D=combat.snapshot().actors[id].pose
	# Place the actual muzzle at the target and retain its resolved item damage.
	var row: Dictionary=primary._guns[0]
	var offset: Vector3=row.mount.position+Vector3(0,0,100)
	pose.origin-=pose.basis*offset
	if row.projectiles.advance(1).is_empty():check(false,row.projectiles.error);return
	var fired: Dictionary=primary.fire(pose,true,controller.snapshot().random_state)
	if fired.is_empty():check(false,primary.error);return
	var previous: int=combat.snapshot().actors[id].vitals.hull
	var result: Dictionary=primary.evaluate_npc_update(combat,[id],0)
	if result.is_empty():check(false,primary.error);return
	check(result.combat.snapshot().actors[id].vitals.hull<previous,"The equipped primary could not hit a contract pirate")
	check(controller.snapshot().combat.actors[id].vitals.hull==previous,"Detached primary contacts changed the accepted combat owner")

func verify_contact_order(bindings: RefCounted,controller: RefCounted,player: RefCounted,weapons: RefCounted) -> void:
	# Overlap the player with the rival. Odd pirates visit the player last;
	# even pirates visit the rival last. All guns retain collision geometry.
	for id in [1,2]:
		var guns: RefCounted=weapons.fork_for_frame();var combat: RefCounted=controller.combat_owner()
		var pose: Transform3D=combat.snapshot().actors[0].pose
		if not combat.begin_contact_pass(controller.snapshot().random_state,true):check(false,combat.error);return
		var gun: RefCounted=guns._guns[id]
		if gun.advance(600).is_empty() or not gun.fire(pose.origin,Vector3.BACK,true).get("fired",false):check(false,gun.error);return
		var previous: int=combat.snapshot().actors[0].vitals.hull
		var hit: Dictionary=guns.evaluate_combat_training_update(player,pose,combat,false,0)
		if hit.is_empty():check(false,guns.error);return
		var event: Dictionary=hit.actors[id]
		check(event.contacts.size()==1 and event.npc_contacts.size()==1,"A marked shot lost its overlapping player/rival contact")
		check(event.last_contact_actor==(null if id==1 else {"group":"npc","index":0}),"Challenge contact order lost the player's alternating list position")
		check(hit.combat.snapshot().actors[0].vitals.hull<previous and hit.player.snapshot().vitals!=player.snapshot().vitals,"Contract weapon contact did not apply both real damage paths")
		_life_contacts+=1

func finish_ship_checks(bindings: RefCounted) -> void:
	if LifeRules.available(bindings):
		check(_life_populations==30 and _life_contacts==20,"Contract lifecycle populations or ordered overlap contacts were not all exercised")
		for kind in [0,1,2,3]:
			var history:=LifeReputation.new()
			if not history.configure(bindings,13,[kind,8,8,8],0.5):check(false,history.error);continue
			var actor:={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"actor_id":0,"actor_kind":kind,"vitals":{"hull":0},"nonplayer_kill":false}
			check(history.record_lethal(actor),history.error)
			var event: Dictionary=history.snapshot().events[0]
			check(event.axis==(0 if kind<2 else 1) and event.change==[-5,5,-5,5][kind],"A major faction lethal hit changed the wrong reputation axis")
			var restored:=LifeReputation.new()
			check(restored.restore(bindings,history.snapshot()) and restored.snapshot()==history.snapshot(),"Contract reputation failed to retain its native event history")
	print("Contract lifecycle: %d populations; %d ordered contact passes"%[_life_populations,_life_contacts])

func after_lifecycle_prepared(_bindings: RefCounted,_contracts: RefCounted,_controller: RefCounted) -> void:pass

func after_lifecycle_outcome(_bindings: RefCounted,_contracts: RefCounted,_controller: RefCounted,_target: Dictionary,_equipment: RefCounted) -> void:pass
