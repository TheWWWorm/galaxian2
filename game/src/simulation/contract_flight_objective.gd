extends RefCounted
## The flight keeps the story requirement and retained side mission separate.
## Shared contract settlement owns career changes and acknowledged payment.
const Construction=preload("res://src/simulation/first_flight_construction.gd")
const Encounter=preload("res://src/simulation/full_hold_encounter.gd")
const World=preload("res://src/content/contract_world_definitions.gd")
const FreeFlight=preload("res://src/content/free_flight_definitions.gd")
const Visit=preload("res://src/simulation/campaign_visit.gd")
var error:=""
var _state:={}
var _contracts: RefCounted
var _field_identity: RefCounted
var _visit: RefCounted
var _bindings: RefCounted

func configure(bindings: RefCounted,construction: RefCounted,encounter: RefCounted,library: RefCounted=null) -> bool:
	error=""
	if not World.available(bindings) or not construction is Construction or not encounter is Encounter:return reject("Contract objectives require the prepared ordinary flight")
	var entry: Dictionary=construction.snapshot()
	var contracts: RefCounted=construction.contract_owner()
	if contracts==null or not (World.ordinary_entry(bindings,entry) or FreeFlight.ordinary_entry(bindings,entry)) or not encounter.bind_contract_session(contracts,bindings):return reject(encounter.error)
	var visit: RefCounted
	if FreeFlight.Campaign.active_visit(bindings.mido_travel,entry.departure.get("free_context",{})):
		visit=Visit.new()
		if not visit.configure(bindings,library,entry.campaign_cursor,entry.departure.mission):return reject(visit.error)
	_state={"base_content_id":entry.base_content_id,"binding_id":entry.binding_id,"campaign_cursor":entry.campaign_cursor,
		"phase":"collecting","mission":entry.departure.mission.duplicate(true),"required_cargo":0,
		"cargo_objective_satisfied":false,"cargo_objective_acknowledged":false,"station_return_required":false,
		"combat_objective_satisfied":false,"combat_objective_acknowledged":false,"mining_completed":false,
		"reward_credits":0,"dialogue":{"visible":false,"index":0,"count":0,"previous_available":false}}
	_contracts=contracts;_field_identity=construction.scenery_owner().presentation_identity()
	_visit=visit;_bindings=bindings
	return true

func poll_visit(world_ms: int,hud_ms: int,blocked: bool) -> bool:
	error=""
	if _visit==null:return true
	return true if _visit.poll(_contracts.snapshot().station_id,world_ms,hud_ms,false,blocked) else reject(_visit.error)

func navigate(action: String,encounter: RefCounted) -> bool:
	error=""
	if _visit==null or not encounter is Encounter:return reject("No campaign conversation awaits acknowledgement")
	var visit: RefCounted=_visit.fork()
	if not visit.navigate(action):return reject(visit.error)
	if not visit.transition().is_empty():
		var contracts: RefCounted=encounter.acknowledge_campaign_visit(_bindings,_contracts,visit)
		if contracts==null:return reject(encounter.error)
		_contracts=contracts;_state.campaign_cursor=visit.transition().campaign_cursor
		_state.mission=visit.transition().mission
	_visit=visit
	return true

func poll_contract(cargo: RefCounted,scenery: RefCounted,encounter: RefCounted,alive: bool,radio_active: bool,periodic_due: bool) -> bool:
	error=""
	if _contracts==null or not encounter is Encounter or cargo.field_identity()!=_field_identity or scenery.presentation_identity()!=_field_identity or not cargo.matches_mined_field(scenery.snapshot()):return reject("The contract objective lost its actual flight field and cargo")
	var result: Dictionary=encounter.evaluate_contract_session(_contracts,radio_active,alive,periodic_due)
	if result.is_empty():return reject(encounter.error)
	_contracts=result.session
	return true

func observe_combat(encounter: RefCounted) -> bool:
	error=""
	if _contracts==null or not encounter is Encounter:return reject("Retain the current contract encounter before recording combat")
	var result: Dictionary=encounter.evaluate_contract_session(_contracts,false,false)
	if result.is_empty():return reject(encounter.error)
	_contracts=result.session
	return true

func acknowledge(encounter: RefCounted,serial: int) -> Dictionary:
	error=""
	if _contracts==null or not encounter is Encounter:reject("No contract result awaits acknowledgement");return {}
	var result: Dictionary=encounter.acknowledge_contract_result(_contracts,serial)
	if result.is_empty():reject(encounter.error);return {}
	_contracts=result.session
	return {"clear_player_control":result.clear_player_control,"clear_world_path":result.clear_world_path}

func retained_for_arrival(encounter: RefCounted) -> RefCounted:
	error=""
	if _contracts==null or not encounter is Encounter:reject("The arrival lost its retained contract flight");return null
	var result: RefCounted=encounter.finish_contract_session(_contracts)
	if result==null:reject(encounter.error)
	return result

func contract_owner() -> RefCounted:return null if _contracts==null else _contracts.fork()

func snapshot() -> Dictionary:
	if _contracts==null:return {}
	var result:=_state.duplicate(true);var career: Dictionary=_contracts.snapshot()
	result.progress=career.progress.duplicate(true);result.contracts=career
	result.contract_result=career.pending_result.duplicate(true)
	if _visit!=null:
		result.campaign_visit=_visit.snapshot()
		result.dialogue=result.campaign_visit.dialogue.duplicate(true)
		if result.dialogue.visible:result.phase="campaign_visit"
	return result

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._state=_state.duplicate(true);copy._contracts=null if _contracts==null else _contracts.fork();copy._field_identity=_field_identity
	copy._visit=null if _visit==null else _visit.fork();copy._bindings=_bindings
	return copy

func reject(message: String) -> bool:error=message;return false
