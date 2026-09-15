extends "res://tests/contract_encounters.gd"
## Actual retained contracts construct these ship owners. Player placement and
## individual motion/projectile inputs below are disclosed component fixtures.
const ShipRules=preload("res://src/content/contract_ship_combat_definitions.gd")
const ShipBody=preload("res://src/simulation/opening_combat_actor.gd")
const ShipGuidance=preload("res://src/simulation/opening_npc_guidance.gd")
const ShipWeapons=preload("res://src/simulation/opening_npc_weapons.gd")
const ShipMotion=preload("res://src/simulation/npc_flight.gd")
var _ship_vectors:=[]
var _ship_populations:=0
var _ship_matrix_checked:=false

func _initialize() -> void:
	var args:=OS.get_cmdline_user_args()
	check(args.size()==3,"Expected explicit Mac content, bindings and visuals")
	if args.size()==3:
		var lib:=Library.new();var bindings:=Bindings.new()
		if not lib.open(args[0]) or not bindings.open(args[1],lib.manifest):check(false,lib.error+bindings.error)
		elif Terms.ship_combat_parameters(bindings.early_contracts):
			_vectors=read_vectors("GOF2_CONTRACT_VECTORS",140)
			_ship_vectors=read_vectors("GOF2_CONTRACT_SHIP_VECTORS",210)
			if not _vectors.is_empty() and not _ship_vectors.is_empty():verify(args)
			check(_ship_populations==30 and _ship_matrix_checked,"The accepted ship populations or independent weapon matrix were not exercised")
			finish_ship_checks(bindings)
		else:
			check(not ShipBody.new().configure_contract(bindings,null,null,0),"An earlier pack enabled contract ship bodies")
			check(not ShipWeapons.new().configure_contract(bindings,null,null),"An earlier pack enabled contract ship weapons")
			check(not ShipGuidance.new().configure_contract(bindings,null,null,0),"An earlier pack enabled contract ship guidance")
	print("Contract ship setup: %d checks; %d failures; %d accepted populations"%[checks,failures,_ship_populations])
	quit(1 if failures else 0)

func read_vectors(variable: String,count: int) -> Array:
	var file:=FileAccess.open(OS.get_environment(variable),FileAccess.READ)
	if file==null or file.get_length()>4*1024*1024:check(false,"Supply independent vectors through "+variable);return []
	var data: Variant=JSON.parse_string(file.get_as_text())
	if not data is Array or data.size()!=count:check(false,"Incomplete independent vector set: "+variable);return []
	return data

func after_encounter_population(bindings: RefCounted,cat: RefCounted,owner: RefCounted,vector: Dictionary,equipment: RefCounted,contracts: RefCounted) -> void:
	var before: Dictionary=owner.snapshot()
	if not _ship_matrix_checked:
		for expected in _ship_vectors:
			var row:=ShipRules.weapon_for(bindings.early_contracts.ship_combat,int(expected.rank),float(expected.game),int(expected.faction),int(expected.faction)!=8)
			check_weapon(row,expected)
		var changed: Dictionary=bindings.early_contracts.ship_combat.duplicate(true)
		changed.weapons.rival_speed=16.0
		check(not ShipRules.parameters(changed) and ShipRules.weapon_for(changed,1,0.5,3,true).is_empty(),"Changed rival weapon tuning was accepted")
		_ship_matrix_checked=true
	var weapons:=ShipWeapons.new()
	var data:=ShipRules.population(bindings,before)
	if int(vector.kind) not in [4,12]:
		var junk: bool=int(vector.kind)==7 and preload("res://src/content/contract_junk_definitions.gd").available(bindings)
		check(data.is_empty(),"An unarmed world borrowed ship combat declarations")
		if junk:
			check(weapons.configure_contract(bindings,cat,owner) and weapons.snapshot().actors.all(func(actor):return actor.projectiles.is_empty()),"Junk acquired ordinary ship weapons")
		else:check(not weapons.configure_contract(bindings,cat,owner) and not ShipBody.new().configure_contract(bindings,cat,owner,0),"An earlier or empty world enabled debris combat")
		check(not ShipGuidance.new().configure_contract(bindings,cat,owner,0),"Debris or an empty world borrowed ship controls")
		return
	if data.is_empty():check(false,"Unsupported contract ship population");return
	if not weapons.configure_contract(bindings,cat,owner):check(false,"Contract weapons: "+weapons.error);return
	if int(vector.kind)==12:check(data.target_memberships==[[-1,1,2,3],[0,-1],[-1,0],[0,-1]],"Challenge target order lost its alternating player position")
	else:check(data.target_memberships.all(func(ids):return ids==[-1]),"Pirates targeted their own faction")
	var bodies:=[];var controls:=[];var motions:=[]
	for id in before.actors.size():
		var body:=ShipBody.new();var control:=ShipGuidance.new();var motion:=ShipMotion.new()
		if not body.configure_contract(bindings,cat,owner,id) or not control.configure_contract(bindings,cat,owner,id) or not motion.configure(bindings,before.actors[id].body_pose):check(false,body.error+control.error+motion.error);return
		bodies.append(body);controls.append(control);motions.append(motion)
		var state: Dictionary=body.snapshot()
		var expected: Dictionary=_ship_vectors.filter(func(row):return int(row.rank)==data.rank and float(row.game)==data.difficulty and int(row.faction)==state.actor_kind)[0]
		var rival: bool=before.actors[id].population_group=="rival"
		check(state.factory_hull==int(expected.factory_hull) and state.vitals.hull==(9999999 if rival else int(expected.factory_hull)),"Contract body lost rank-scaled hull or its rival override")
		check(state.campaign_cursor==13 and state.station_id==before.station_id and state.pose==before.actors[id].statistics_pose,"Contract body changed its actual location or source pose")
		check(state.active==rival and state.actor_mode==(0 if rival else 5) and state.friendly==rival and not state.hostile,"Contract body activated or changed allegiance too early")
		check(control.snapshot().previous_hull==state.factory_hull and control.snapshot().maximum_hull==state.max_hull,"Guidance lost the pre-override hull sample")
		var gun: RefCounted=weapons._guns[id]
		check_weapon(weapons.snapshot().actors[id].definition,expected)
		check(weapons.snapshot().actors[id].audio.source_id==int(expected.audio),"Contract weapon sound disagrees with its faction")
		check(not gun.fire(Vector3.ZERO,Vector3.BACK,true).fired,"An NPC fired at interval equality")
		check(not gun.advance(1).is_empty() and gun.fire(Vector3.ZERO,Vector3.BACK,true).fired,"The source interval did not release its projectile")
		check(not gun.advance(10).is_empty(),gun.error)
		var slot: Dictionary=gun.snapshot().slots.filter(func(value):return value!=null)[0]
		check(slot.position==Vector3(0,0,float(expected.speed)*10),"Faction projectile used the wrong source speed")
		var detached: RefCounted=control.fork_for_frame()
		check(detached.snapshot()==control.snapshot(),"Detached contract guidance lost its source state")
	for id in bodies.size():
		var initial: Dictionary=bodies[id].snapshot()
		var player:=player_fixture(bindings,initial.pose.origin+Vector3(0,0,20000))
		var random: Dictionary=before.random_state.duplicate(true)
		for _frame in 2:
			var step:=drive_ship(bodies,controls,motions,id,player,random,16)
			if step.is_empty():return
			random=step.random_state
		check(bodies[id].snapshot().active and bodies[id].snapshot().actor_mode==1,"The source initialization/proximity trigger did not release this ship")
		check(bodies[id].snapshot().friendly==(id==0 and int(vector.kind)==12),"A challenge rival lost its forced friendship")
	if int(vector.kind)==12 and int(vector.seed)==0:verify_rival_boost(bindings,bodies,controls,motions,before.random_state)
	check(owner.snapshot()==before,"Ship setup or detached motion mutated the retained construction")
	_ship_populations+=1

func check_weapon(row: Dictionary,expected: Dictionary) -> void:
	check(not row.is_empty(),"Missing source faction weapon")
	if row.is_empty():return
	check(row.item_id==int(expected.item) and row.kind==int(expected.kind) and row.model_resource_id==int(expected.model),"Faction selected the wrong original weapon or projectile")
	check(row.damage==int(expected.damage) and row.speed_units_per_millisecond==float(expected.speed),"Rank/difficulty or rival weapon boost differs from its independent vector")
	check(row.interval_ms==int(expected.interval_ms) and row.projectile_capacity==int(expected.capacity) and row.lifetime_ms==int(expected.lifetime_ms),"Ordinary weapon timing or capacity changed")

func player_fixture(bindings: RefCounted,position: Vector3) -> Dictionary:
	return {"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"pose":Transform3D(Basis.IDENTITY,position),
		"ship_id":0,"active":true,"hull":95,"special_flight":false,"targeting_blocked":false,"alternate_position":null}

func drive_ship(bodies: Array,controls: Array,motions: Array,id: int,player: Dictionary,random: Dictionary,delta_ms: int) -> Dictionary:
	if not bodies[id].refresh_hostility():check(false,bodies[id].error);return {}
	var state: Dictionary=bodies[id].snapshot()
	var decision: Dictionary=controls[id].update(delta_ms,state,motions[id].snapshot().root_pose,player,random,bodies.map(func(body):return body.snapshot()))
	if decision.is_empty() or not bodies[id].apply_contract_guidance(decision):check(false,controls[id].error+bodies[id].error);return {}
	var pose: Dictionary=motions[id].snapshot()
	if decision.steering_enabled or decision.travel_enabled:
		pose=motions[id].advance(delta_ms,decision.direction,decision.speed,decision.steering_enabled,decision.travel_enabled)
	if pose.is_empty() or not bodies[id].set_pose(pose.pose,pose.root_pose):check(false,motions[id].error+bodies[id].error);return {}
	return decision

func verify_rival_boost(bindings: RefCounted,bodies: Array,controls: Array,motions: Array,random_state: Dictionary) -> void:
	var random:=random_state.duplicate(true)
	var player:=player_fixture(bindings,Vector3(900000,900000,900000))
	for _frame in 210:
		var decision:=drive_ship(bodies,controls,motions,0,player,random,50)
		if decision.is_empty():return
		random=decision.random_state
	var state: Dictionary=controls[0].snapshot()
	check(state.speed==2.0 and not state.boost_active and state.boost_elapsed_ms>10000,"The rival consumed or activated a disabled speed boost")
	check(state.previous_hull==bodies[0].snapshot().factory_hull,"Disabled rival boosting changed the constructor hull sample")

func finish_ship_checks(_bindings: RefCounted) -> void:
	pass
