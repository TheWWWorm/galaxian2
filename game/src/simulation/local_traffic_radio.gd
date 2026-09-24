extends RefCounted
## A replaceable pending faction message and an independently retained active
## message. Shared RadioSequence owns its source line timing and visibility.
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const ContractWorld=preload("res://src/content/contract_world_definitions.gd")
const FreeFlight=preload("res://src/content/free_flight_definitions.gd")
const Sequence=preload("res://src/simulation/radio_sequence.gd")
const Random=preload("res://src/simulation/seeded_random.gd")
var error:=""
var _identity:={}
var _rules:={}
var _templates:={}
var _last_received:={}
var _pending:={}
var _message:={}
var _portrait:={}
var _active: RefCounted
var _last_time:=-1

func configure(bindings: RefCounted, library: RefCounted, layout: RefCounted,cursor: int=10) -> bool:
	error="";_identity={};_rules={};_templates={};_last_received={};_pending={};_message={};_portrait={};_active=null;_last_time=-1
	if bindings==null or (Travel.journey(bindings.mido_travel,cursor).is_empty() and not ContractWorld.supports(bindings,cursor) and not (load("res://src/content/free_campaign_definitions.gd").supported(bindings.mido_travel,cursor) and FreeFlight.available(bindings))):return reject("Local radio requires its verified declarations")
	var templates:={};var rules: Dictionary=bindings.mido_travel.traffic_combat.radio
	for kind in ["warning","response"]:
		for value in rules[kind+"_text_ids"]:
			var owner:=Sequence.new()
			if not owner.configure_local_message(bindings,library,layout,int(value),cursor):return reject(owner.error)
			templates[int(value)]=owner
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id,"campaign_cursor":cursor,"language":library.active_language}
	_templates=templates;_rules=rules.duplicate(true)
	return true

func evaluate(elapsed_ms: int, reaction: Dictionary, random_state: Dictionary) -> Dictionary:
	error=""
	if _identity.is_empty() or elapsed_ms<0 or elapsed_ms<_last_time or elapsed_ms>2147483647:return fail("Local radio requires monotonic simulation time")
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if reaction.get(key)!=_identity[key]:return fail("Local radio belongs to another encounter")
	var serial: Variant=reaction.get("radio_serial")
	var received: Variant=reaction.get("pending_radio")
	var previous: int=_last_received.get("serial",0)
	if not serial is int or serial<previous or serial>2 or not received is Dictionary:return fail("Invalid local radio history")
	if serial==0:
		if not received.is_empty():return fail("Local radio has a message without its source request")
	elif not valid_message(received) or received.serial!=serial or (serial==previous and received!=_last_received):return fail("Local radio message changed or lacks source text and voice")
	var random:=Random.new()
	if not random.restore(random_state):return fail(random.error)
	var next:=fork_for_frame();next._last_time=elapsed_ms
	if serial>previous:
		next._pending=received.duplicate(true);next._last_received=received.duplicate(true)
	var events:=[]
	if next._active==null:
		if not next._pending.is_empty():
			next._message=next._pending;next._pending={}
			next._active=_templates[next._message.text_id].fork_for_frame()
			var family: int=int(_rules.portrait_zero_family) if random.next_int(int(_rules.portrait_family_bound))==0 else int(_rules.portrait_other_family)
			var parts:=[]
			for bound in _rules.portrait_part_bounds[str(family)]:parts.append(random.next_int(int(bound)))
			# Resolved procedural parts use the existing fixed-layer compositor.
			next._portrait={"status":"fixed","family":family,"parts":parts}
			events=next._step(elapsed_ms)
	else:events=next._step(elapsed_ms)
	if not next.error.is_empty():return fail(next.error)
	return {"radio":next,"random_state":random.snapshot(),"events":events}

func _step(elapsed_ms: int) -> Array:
	var events: Array=_active.step(elapsed_ms,{},0)
	if not _active.error.is_empty():reject(_active.error);return []
	for event in events:
		event.message_kind=_message.kind
		event.merge(_message)
	if _active.snapshot().finished==[true]:
		_active=null;_message={};_portrait={}
	return events

func valid_message(message: Dictionary) -> bool:
	return valid_payload(_rules,message)

static func valid_payload(rules: Dictionary, message: Dictionary) -> bool:
	if rules.is_empty() or message.size()!=5 or not message.get("serial") is int or message.serial<1 or message.serial>2 or message.get("kind") not in ["warning","response"] or message.get("speaker_id")!=int(rules.speaker_id):return false
	for key in ["text_id","voice_event_id"]:
		if not message.get(key) is int:return false
	for i in int(rules.text_draw_bound):
		if message.text_id==int(rules[message.kind+"_text_ids"][i]):return message.voice_event_id==int(rules[message.kind+"_voice_ids"][i])
	return false

static func valid_portrait(rules: Dictionary, portrait: Dictionary) -> bool:
	if rules.is_empty() or portrait.size()!=3 or portrait.get("status")!="fixed" or not portrait.get("family") is int or not portrait.get("parts") is Array:return false
	var bounds: Array=rules.portrait_part_bounds.get(str(portrait.family),[])
	if bounds.size()!=4 or portrait.parts.size()!=4:return false
	for i in 4:
		if not portrait.parts[i] is int or portrait.parts[i]<0 or portrait.parts[i]>=int(bounds[i]):return false
	return true

func snapshot() -> Dictionary:
	if _identity.is_empty():return {}
	var result:=_identity.duplicate()
	result.merge({"last_serial":_last_received.get("serial",0),"pending":_pending.duplicate(true),
		"message":_message.duplicate(true),"portrait":_portrait.duplicate(true),"active_event":-1,"visible":false})
	if _active!=null:result.merge(_active.snapshot(),true)
	return result

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._identity=_identity.duplicate();copy._rules=_rules.duplicate(true);copy._templates=_templates.duplicate()
	copy._last_received=_last_received.duplicate(true);copy._pending=_pending.duplicate(true)
	copy._message=_message.duplicate(true);copy._portrait=_portrait.duplicate(true)
	copy._active=null if _active==null else _active.fork_for_frame();copy._last_time=_last_time
	return copy

func reject(message: String) -> bool:
	error=message;return false

func fail(message: String) -> Dictionary:
	reject(message);return {}
