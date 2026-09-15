extends RefCounted
## Stationary Junk debris. A lethal update removes the model immediately and
## may replace it with cargo; ship tumble, fragments and expiry do not apply.
const Rules=preload("res://src/content/contract_junk_definitions.gd")
const Construction=preload("res://src/simulation/opening_npc_construction.gd")
const Resources=preload("res://src/content/npc_destruction_resources.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
var error:=""
var _state:={}
var _rules:={}
var _max_ms:=0

func configure(bindings: RefCounted,resources: RefCounted,construction: RefCounted,actor_id: int) -> bool:
	error="";_state={};_rules={};_max_ms=0
	if not construction is Construction or not resources is Resources:return reject("Debris requires its prepared original cargo resources and construction")
	var packet: Dictionary=construction.snapshot()
	var data:=Rules.population(bindings,packet)
	var models: Dictionary=resources.snapshot()
	if data.is_empty() or actor_id<0 or actor_id>=data.actor_count or models.get("contract_encounter")!=packet.contract_encounter:return reject("Debris resources belong to another accepted encounter")
	for key in ["base_content_id","binding_id"]:
		if models.get(key)!=bindings.get(key):return reject("Debris resources belong to another content identity")
	var rules: Dictionary=data.lifecycle
	var cargo: Variant=models.get("cargo_models",[])
	if not cargo is Array or cargo.size()!=data.actor_count or cargo[actor_id]!={"model_id":int(rules.cargo_model_id),"resource":rules.cargo_model_resource}:return reject("Debris lost its original Midorian container")
	var actor: Dictionary=packet.actors[actor_id]
	_state={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":int(data.campaign_cursor),
		"actor_id":actor_id,"actor_kind":-1,"resource_id":actor.resource_id,"phase":"ready","mode":int(rules.initial_mode),
		"pose":actor.body_pose,"statistics_pose":actor.statistics_pose,"active":bool(rules.initial_active),
		"model_draw_enabled":bool(rules.initial_model_draw_enabled),"cargo":{},"elapsed_ms":0}
	_rules=rules.duplicate(true);_max_ms=int(bindings.frame_clock.max_frame_milliseconds)
	return true

func advance(delta_ms: Variant,random_state: Dictionary,actor: Dictionary) -> Dictionary:
	error=""
	if _state.is_empty() or not Numbers.integer(delta_ms,0,_max_ms):return fail("Debris update needs a configured owner and bounded whole milliseconds")
	for key in ["base_content_id","binding_id","campaign_cursor","actor_id","actor_kind","resource_id"]:
		if actor.get(key)!=_state[key]:return fail("Debris update belongs to another actor")
	if actor.get("body_pose")!=_state.pose or actor.get("pose")!=_state.statistics_pose or actor.get("active")!=_state.active or actor.get("actor_mode")!=_state.mode:return fail("Debris body disagrees with its retained lifecycle")
	if not Numbers.integer(actor.get("vitals",{}).get("hull"),0,1):return fail("Debris lost its source hull")
	var random:=Random.new()
	if not random.restore(random_state):return fail(random.error)
	var next:=_state.duplicate(true);var started:=false;var sounds:=[];var bursts:=[];var clear_target:=false
	if _state.phase=="ready" and actor.vitals.hull==0:
		started=true
		var entries:=[]
		if random.next_int(int(_rules.drop_draw_bound))<=int(_rules.drop_inclusive_maximum):
			entries.append({"item_id":int(_rules.cargo_item_id),"quantity":int(_rules.quantity_add)+random.next_int(int(_rules.quantity_draw_bound))})
		next.cargo={"entries":entries,"model_id":int(_rules.cargo_model_id),"resource":_rules.cargo_model_resource,
			"pose":_state.pose,"eligible":not entries.is_empty(),"model_exists":not entries.is_empty(),"rotation_radians":Vector3.ZERO}
		next.mode=int(_rules.destroyed_mode);next.phase="destroyed"
		next.active=not entries.is_empty();next.model_draw_enabled=false
		clear_target=entries.is_empty() and _rules.empty_clears_selected_target
		sounds.append(int(_rules.sound_id))
		bursts.append({"preset_id":int(_rules.burst_preset.preset_id),"member_index":int(_rules.burst_member_index),
			"count":int(_rules.burst_count),"size_override":int(_rules.burst_size_override),"position":_state.pose.origin})
	elif _state.phase=="destroyed" and actor.vitals.hull!=0:return fail("Destroyed debris cannot regain hull")
	# There is no lifetime or movement branch for the retained container.
	if next.phase=="destroyed":next.elapsed_ms+=int(delta_ms)
	_state=next
	return {"state":snapshot(),"random_state":random.snapshot(),"started":started,
		"sound_events":sounds,"audio_events":sounds.map(func(id):return {"source_id":id,"position":_state.pose.origin}),
		"bursts":bursts,"clear_selected_target":clear_target}

func snapshot() -> Dictionary:return _state.duplicate(true)

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._state=_state.duplicate(true);copy._rules=_rules.duplicate(true);copy._max_ms=_max_ms
	return copy

func reject(message: String) -> bool:error=message;return false
func fail(message: String) -> Dictionary:reject(message);return {}
