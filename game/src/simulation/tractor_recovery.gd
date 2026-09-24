extends RefCounted
## Retained tractor requests and detached wreck transactions. The frame applies
## the returned actor, inventory and counter changes together after validation.
const Definitions=preload("res://src/content/tractor_recovery_definitions.gd")
const Frames=preload("res://src/simulation/frame_clock.gd")
const Library=preload("res://src/content/library.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
const Vitals=preload("res://src/simulation/combat_vitals.gd")
const Vectors=preload("res://src/simulation/source_vectors.gd")
const TargetProjection=preload("res://src/presentation/target_projection.gd")
const Readonly=preload("res://src/simulation/readonly_state.gd")
const Resources=preload("res://src/content/tractor_resources.gd")
const Playback=preload("res://src/simulation/model_playback.gd")
var error:=""
var _identity:={}
var _rules:={}
var _item_kinds:=[]
var _max_ms:=0
var _state:={}
var _sample:={}
var _loadout:={}
var _transaction_identity: RefCounted

func configure(bindings: RefCounted, catalogues: RefCounted, loadout: Dictionary, library: RefCounted=null) -> bool:
	error=""
	if not Definitions.available(bindings) or catalogues==null:return reject("Tractor recovery requires verified source declarations and catalogues")
	if not Library.valid_hash(bindings.base_content_id) or not Library.valid_hash(bindings.binding_id) or catalogues.content_id!=bindings.base_content_id:return reject("Tractor recovery content identity is unavailable")
	for key in ["base_content_id","binding_id"]:
		if loadout.get(key)!=bindings.get(key):return reject("Tractor equipment belongs to another departure")
	var rules: Dictionary=bindings.mido_travel.tractor_recovery.duplicate(true)
	# JSON numeric arrays arrive as floats. Normalize the validated configuration
	# once so native IDs and modes have the same membership semantics in flight.
	for pair in [[rules.pull,"supported_player_hulls"],[rules.equipment,"modes"],
		[rules.acquisition,"ship_auto_modes"],[rules.transfer,"wreck_modes"],
		[rules.transfer,"faction_kinds"],[rules.transfer,"special_item_ids"]]:
		pair[0][pair[1]]=pair[0][pair[1]].map(func(value):return int(value))
	if loadout.get("ship_id") not in rules.pull.supported_player_hulls or not loadout.get("equipment_ids") is Array:return reject("Tractor beam origins currently support Betty's equipped loadout")
	var items: Variant=catalogues.tables.get("items")
	if not items is Array or items.is_empty():return reject("Tractor equipment catalogue is unavailable")
	var kinds:=[]
	for item in items:
		if not item is Dictionary or not item.get("properties") is Dictionary or not Numbers.integer(item.properties.get(1),0,2147483647):return reject("Invalid tractor item catalogue")
		kinds.append(int(item.properties[1]))
	var equipment:=-1;var scanner:=-1
	for id in loadout.equipment_ids:
		if not Numbers.integer(id,-1,items.size()-1):return reject("Invalid installed tractor equipment slot")
		if id<0:continue
		var properties: Dictionary=items[id].properties
		if properties.get(int(rules.equipment.item_kind_property))!=int(rules.equipment.equipment_kind):continue
		if equipment<0 and properties.get(int(rules.equipment.category_property))==int(rules.equipment.category):equipment=int(id)
		if scanner<0 and properties.get(int(rules.equipment.category_property))==int(rules.equipment.scanner_category):scanner=int(id)
	var mode:=-1;var duration:=0;var model:=-1
	if equipment>=0:
		var properties: Dictionary=items[equipment].properties
		if properties.get(int(rules.equipment.mode_property)) not in rules.equipment.modes or not Numbers.integer(properties.get(int(rules.equipment.duration_property)),0,2147483647):return reject("Unsupported installed tractor mode or acquisition time")
		mode=int(properties[int(rules.equipment.mode_property)]);duration=int(properties[int(rules.equipment.duration_property)])
		var selector:=equipment-int(rules.equipment.beam_item_base) if equipment<int(rules.equipment.beam_item_limit) else int(rules.equipment.beam_fallback_selector)
		if selector<0:return reject("Unsupported tractor beam resource selector")
		model=int(rules.equipment.beam_model_base)+selector
	var maximum:=Frames.simulation_limit(bindings)
	if maximum<1:return reject("Tractor recovery requires the source frame clock")
	var visual:={}
	if equipment>=0 and library!=null:
		var resources:=Resources.new()
		visual=resources.prepare(library,bindings,model)
		if visual.is_empty():return reject(resources.error)
		visual.time_ms=visual.start_ms;visual.playing=true
	_identity={"base_content_id":bindings.base_content_id,"binding_id":bindings.binding_id}
	_loadout={"ship_id":int(loadout.ship_id),"equipment_ids":loadout.equipment_ids.duplicate()}
	_transaction_identity=RefCounted.new()
	_rules=Readonly.freeze(rules);_item_kinds=Readonly.freeze(kinds);_max_ms=maximum
	_state={"equipment_id":equipment,"scanner_id":scanner,"mode":mode,"duration_ms":duration,
		"candidate_actor_id":-1,"request_actor_id":-1,"current_actor_id":-1,"elapsed_ms":0,
		"request_group":"npc","current_group":"npc",
		"active":false,"loop_started":false,"captured_hull":0,"transfer_serial":0,
		"beam":{"model_id":model,"pose":Transform3D.IDENTITY,"scale":Vector3.ONE,"animation_elapsed_ms":0}}
	if not visual.is_empty():_state.beam.playback=visual
	_sample={}
	return true

## Ordered NPC observations include ordinary candidates so a later wreck cannot
## steal their source scan window. Other target populations retain their owners.
## Call this HUD phase after advance; its request starts in the next player phase.
func acquire(delta_ms: Variant, observations: Array, context: Dictionary) -> bool:
	error=""
	if _state.is_empty() or not Numbers.integer(delta_ms,0,_max_ms) or not same_identity(context):return reject("Invalid tractor acquisition frame or identity")
	for key in ["enabled","guidance_active","alternate_operation_active","mining_approach_active","alternate_approach_active","autopilot","other_target_selected","ordinary_scan_enabled","ordinary_scan_blocked"]:
		if not context.get(key) is bool:return reject("Tractor acquisition requires explicit native selection gates")
	var aim: Variant=context.get("aim_pixels");var viewport: Variant=context.get("viewport_size")
	if not aim is Vector2 or not aim.is_finite() or not viewport is Vector2i or viewport.x<1 or viewport.y<1:return reject("Invalid tractor acquisition window")
	@warning_ignore("integer_division")
	var radius: int=viewport.x/int(_rules.acquisition.window_divisor)
	var lower:=Vector2(Vitals.single(aim.x-float(radius)),Vitals.single(aim.y-float(radius)))
	for value in [lower.x,lower.y,lower.x+radius*2,lower.y+radius*2]:
		if not TargetProjection.safe_pixel(value):return reject("Tractor acquisition exceeds source pixel coordinates")
	var low:=Vector2i(int(lower.x),int(lower.y));var high:=low+Vector2i(radius*2,radius*2)
	var ids:={}
	for row in observations:
		if not row is Dictionary or not same_identity(row) or not Numbers.integer(row.get("actor_id"),0,2147483647) or ids.has(row.actor_id) or not Numbers.integer(row.get("actor_mode"),0,2147483647) or not row.get("pixels") is Vector2i:return reject("Invalid ordered tractor target population")
		for key in ["active","cargo_eligible","excluded","scan_blocked","priority","in_view"]:
			if not row.get(key) is bool:return reject("Incomplete tractor target observation")
		ids[row.actor_id]=true
	var next:=_state.duplicate(true)
	var sample:={"phase":"acquisition","ordinary_candidate_actor_id":-1,"found_actor_id":-1,"events":[]}
	if not context.enabled or next.scanner_id<0:
		_state=next;_sample=sample;return true
	var blocked: bool=context.other_target_selected or next.request_actor_id>=0
	var found:=-1;var found_cargo:=false;var found_priority:=false
	for row in observations:
		var wreck: bool=int(row.actor_mode) in _rules.transfer.wreck_modes
		var cargo: bool=wreck and row.cargo_eligible
		if not row.active or row.excluded or (wreck and not cargo):continue
		var normal_gate: bool=row.in_view and not context.guidance_active and not context.alternate_operation_active and (not row.scan_blocked or cargo) and (found<0 or row.priority)
		if normal_gate and (not cargo or row.actor_mode==int(_rules.acquisition.ship_requested_mode)):
			var pixel: Vector2i=row.pixels
			var inside:=pixel.x>low.x and pixel.x<high.x and pixel.y>low.y and pixel.y<high.y
			var automatic: bool=cargo and next.mode==1 and next.request_actor_id<0
			if automatic or (inside and ((cargo and next.equipment_id>=0) or (context.ordinary_scan_enabled and not context.ordinary_scan_blocked))):
				found=int(row.actor_id);found_cargo=cargo;found_priority=row.priority
				if automatic:next.request_actor_id=found;next.request_group="npc"
		# Mode2 deliberately survives the offscreen and guidance branches.
		if next.mode==2 and next.request_actor_id<0 and cargo and row.actor_mode==int(_rules.acquisition.ship_requested_mode):
			found=int(row.actor_id);found_cargo=true;found_priority=row.priority;next.request_actor_id=found;next.request_group="npc"
	sample.found_actor_id=found
	if found>=0:
		if next.candidate_actor_id!=found:next.elapsed_ms=0
		next.candidate_actor_id=found
		if not found_cargo:
			if found_priority:return reject("Living-actor tractor theft requires its separate source path")
			sample.ordinary_candidate_actor_id=found
			next.elapsed_ms=0
		elif not blocked and not context.autopilot and not context.mining_approach_active and not context.alternate_approach_active:
			if next.elapsed_ms>2147483647-int(delta_ms):return reject("Tractor acquisition clock exceeds the source integer range")
			next.elapsed_ms+=int(delta_ms)
			if next.elapsed_ms>next.duration_ms:
				next.request_actor_id=found;next.request_group="npc";next.elapsed_ms=0
				if next.equipment_id<0:
					next.request_actor_id=-1
					sample.events.append({"kind":"notification","source_id":int(_rules.acquisition.missing_device_notification),"actor_id":found})
	elif not blocked and not context.autopilot and not context.mining_approach_active and not context.alternate_approach_active:
		next.elapsed_ms=0
		if next.request_actor_id<0:next.candidate_actor_id=-1
	_state=next;_sample=sample
	return true

## Bridge for the distinct scenery acquisition owner. This is a queued request,
## not a player action or a substitute for that owner's selection predicates.
func queue_acquired_wreck(actor: Dictionary) -> bool:
	error=""
	if _state.is_empty() or _state.equipment_id<0 or not valid_actor(actor):return reject("An acquired wreck requires installed tractor equipment and its live observation")
	if actor.actor_mode not in _rules.transfer.wreck_modes or not actor.cargo_eligible or (not actor.active and not actor.statistics_exempt):return reject("The selected actor is not recoverable wreck cargo")
	_state=_state.duplicate(true)
	_state.request_actor_id=int(actor.actor_id)
	_state.request_group=actor.get("target_group","npc")
	# Scenery has its own candidate and clock. Its timed request must not replace
	# the NPC scanner's retained candidate with a coincidentally equal array index.
	if _state.request_group=="npc":_state.candidate_actor_id=int(actor.actor_id)
	return true

## actor is the current actor, or queued actor when idle; an empty observation
## means that the enclosing world's retained target has ceased to exist.
func advance(delta_ms: Variant, player: Dictionary, actor: Dictionary, hold: Dictionary) -> bool:
	error=""
	if _state.is_empty() or not Numbers.integer(delta_ms,0,_max_ms) or not same_identity(player) or not player.get("pose") is Transform3D or not player.pose.is_finite() or not player.get("autopilot") is bool:return reject("Invalid tractor player phase")
	var next:=_state.duplicate(true)
	var sample:={"phase":"idle","actor_changes":{},"transfer":{},"events":[]}
	var expected:=int(next.current_actor_id) if next.current_actor_id>=0 else int(next.request_actor_id)
	if expected<0:_sample=sample;return true
	if next.equipment_id<0:return reject("A tractor request cannot grant missing equipment")
	if not actor.is_empty() and (not valid_actor(actor) or actor.actor_id!=expected or actor.get("target_group","npc")!=target_group()):return reject("Tractor target observation does not match its retained request")
	if next.current_actor_id<0 and not player.autopilot and not actor.is_empty():
		if actor.actor_mode not in _rules.transfer.wreck_modes:return reject("Living-actor tractor theft is not supported")
		if first_positive(actor.cargo_entries)<0:
			next.active=false;next.request_actor_id=-1;sample.phase="empty"
		else:
			next.current_actor_id=expected;next.current_group=next.request_group;next.captured_hull=int(actor.hull);next.active=true;sample.phase="started"
			if not actor.cargo_model_exists:
				var model: int=int(_rules.pull.cargo_models.get(str(actor.actor_kind),_rules.pull.cargo_models.other))
				var pose:=Transform3D(Basis.IDENTITY,actor.body_pose.origin)
				sample.actor_changes={"actor_id":expected,"cargo_model_exists":true,"cargo_model_id":model,"cargo_pose":pose,"statistics_pose":pose}
		_state=next;_sample=sample;return true
	if actor.is_empty() or not actor.cargo_model_exists or (not actor.statistics_exempt and not actor.active) or next.current_actor_id<0:
		finish(next);sample.phase="cancelled"
		sample.events.append({"kind":"stop_sound","source_id":int(_rules.pull.loop_sound)})
		_state=next;_sample=sample;return true
	if actor.actor_mode not in _rules.transfer.wreck_modes:return reject("Living-actor tractor continuation is not supported")
	var offset:=Vectors.added(actor.cargo_pose.origin,-player.pose.origin)
	var distance:=Vitals.single(sqrt(Vectors.dot(offset,offset)))
	if not is_finite(distance):return reject("Tractor distance exceeds source coordinates")
	var direction:=Vectors.normalized(offset)
	var right:=Vectors.normalized(Vectors.cross(Vector3.UP,direction))
	var up:=Vectors.normalized(Vectors.cross(direction,right))
	if next.beam.animation_elapsed_ms>2147483647-int(delta_ms):return reject("Tractor animation clock exceeds source integer range")
	next.beam.pose=Transform3D(Basis(right,up,direction),player.pose.origin)
	next.beam.scale=Vector3(float(_rules.pull.beam_width),float(_rules.pull.beam_width),distance)
	next.beam.animation_elapsed_ms+=int(delta_ms)
	if next.beam.has("playback"):Playback.advance([next.beam.playback],int(delta_ms),true)
	if distance<=float(_rules.pull.distance):
		if not valid_hold(hold):return reject("Tractor pickup requires the retained hold including its used-space cache")
		var transfer:=_transfer_plan(actor,hold)
		if transfer.is_empty():return false
		if next.transfer_serial==2147483647:return reject("Tractor transfer serial exceeds source integer range")
		next.transfer_serial+=1;transfer.serial=next.transfer_serial
		sample.phase="pickup";sample.transfer=transfer
		sample.actor_changes={"actor_id":expected,"cargo_eligible":false,"cargo_model_exists":false,
			"cargo_entries":transfer.remaining_entries.duplicate(true),"active":actor.active and not actor.retire_on_transfer}
		sample.events=transfer.events.duplicate(true)
		finish(next)
		sample.events.append({"kind":"stop_sound","source_id":int(_rules.pull.loop_sound)})
		sample.events.append({"kind":"sound","source_id":int(_rules.pull.pickup_sound)})
	else:
		var displacement:=-Vectors.scaled(direction,Vitals.single(float(int(delta_ms)*int(_rules.pull.units_per_ms))))
		var cargo_pose: Transform3D=actor.cargo_pose
		cargo_pose.origin=Vectors.added(cargo_pose.origin,displacement)
		if not cargo_pose.is_finite():return reject("Pulled cargo exceeded source coordinates")
		sample.phase="pulling";sample.actor_changes={"actor_id":expected,"cargo_pose":cargo_pose}
		if not actor.body_motion_blocked and not actor.body_motion_detached:
			var body_pose: Transform3D=actor.body_pose
			var origin: Vector3=Vector3(actor.freighter_position) if actor.has("freighter_position") else body_pose.origin
			body_pose.origin=Vectors.added(origin,displacement)
			if not body_pose.is_finite():return reject("Pulled wreck exceeded source coordinates")
			if actor.has("freighter_position"):
				for component in [body_pose.origin.x,body_pose.origin.y,body_pose.origin.z]:
					if not TargetProjection.safe_pixel(component):return reject("Pulled freighter exceeded source integers")
				# Its position setter refreshes statistics and integer XYZ. The
				# ordinary NPC movement path deliberately leaves statistics stale.
				sample.actor_changes.freighter_position=Vector3i(body_pose.origin)
				sample.actor_changes.statistics_pose=body_pose
			var centers:=[]
			for center in actor.collision_centers:
				var moved:=Vectors.added(Vector3(center),displacement)
				for component in [moved.x,moved.y,moved.z]:
					if not TargetProjection.safe_pixel(component):return reject("Pulled collision bounds exceeded source integers")
				centers.append(Vector3i(int(moved.x),int(moved.y),int(moved.z)))
			sample.actor_changes.body_pose=body_pose;sample.actor_changes.collision_centers=centers
		next.request_actor_id=-1
		if not next.loop_started:
			next.loop_started=true;sample.events.append({"kind":"sound","source_id":int(_rules.pull.loop_sound)})
	_state=next;_sample=sample
	return true

func _transfer_plan(actor: Dictionary,hold: Dictionary) -> Dictionary:
	var rows: Array=actor.cargo_entries.duplicate(true)
	var index:=first_positive(rows)
	var plan:={"actor_id":int(actor.actor_id),"expected_entries":actor.cargo_entries.duplicate(true),
		"expected_hold":hold.duplicate(true),"remaining_entries":rows,"item_id":-1,"quantity":0,"accepted_quantity":0,
		"inventory_entries":hold.entries.duplicate(true),"used":int(hold.used),"refresh_used":false,
		"matching_indices":[],"created_item_flag":false,"new_entry_index":-1,"events":[]}
	if index<0:return plan
	var item_id:=int(rows[index].item_id)
	var quantity:=maxi(int(_rules.transfer.minimum_quantity),mini(int(rows[index].quantity),int(hold.capacity)-int(hold.used)))
	rows[index].quantity-=quantity
	plan.item_id=item_id;plan.quantity=quantity
	if actor.friendly:plan.events.append({"kind":"friendly_cargo_taken","actor_id":int(actor.actor_id)})
	if not actor.statistics_exempt and actor.actor_kind in _rules.transfer.faction_kinds:
		plan.events.append({"kind":"faction_cargo_taken","actor_id":int(actor.actor_id),"actor_kind":int(actor.actor_kind),"base_magnitude":int(_rules.transfer.faction_base_magnitude)})
	var special: bool=actor.special_cargo and item_id in _rules.transfer.special_item_ids
	plan.special_cargo=special
	var accepted: bool=int(hold.used)<=int(hold.capacity)-quantity
	if accepted:
		plan.accepted_quantity=quantity
		plan.created_item_flag=special
		var matches:=[]
		for i in plan.inventory_entries.size():
			if plan.inventory_entries[i].item_id==item_id:matches.append(i)
		var fast: bool=_item_kinds[item_id]==int(_rules.transfer.fast_stack_kind) and not matches.is_empty()
		plan.matching_indices=matches if fast else ([] if matches.is_empty() else [matches[0]])
		for i in plan.matching_indices:
			if plan.inventory_entries[i].quantity>2147483647-quantity:reject("Recovered stack exceeds source integer range");return {}
			plan.inventory_entries[i].quantity+=quantity
		if matches.is_empty():
			plan.new_entry_index=plan.inventory_entries.size()
			var copied:={"item_id":item_id,"quantity":quantity}
			# This is the same original item flag used by courier cargo. A
			# merged existing row keeps its own flag, as the source does.
			if special:copied.mission=true
			plan.inventory_entries.append(copied)
		plan.refresh_used=not fast
		if plan.refresh_used:
			plan.used=0
			for entry in plan.inventory_entries:
				if plan.used>2147483647-int(entry.quantity):reject("Recovered hold exceeds source integer range");return {}
				plan.used+=int(entry.quantity)
		plan.events.append({"kind":"career_cargo_quantity","quantity":quantity})
		plan.events.append({"kind":"inventory_transfer","item_id":item_id,"quantity":quantity,"refresh_used":plan.refresh_used})
		plan.events.append({"kind":"world_cargo_quantity","quantity":quantity})
		if special:plan.events.append({"kind":"special_cargo_accepted","actor_id":int(actor.actor_id)})
		elif actor.actor_kind==int(_rules.transfer.separate_quantity_kind):plan.events.append({"kind":"kind9_cargo_quantity","quantity":quantity})
		elif item_id>=int(_rules.transfer.item_flag_first) and item_id<=int(_rules.transfer.item_flag_last):plan.events.append({"kind":"item_recovery_flag","index":item_id-int(_rules.transfer.item_flag_first)})
	elif special:plan.events.append({"kind":"special_cargo_rejected","actor_id":int(actor.actor_id)})
	plan.events.append({"kind":"cargo_notification","item_id":item_id,"quantity":quantity,"rejected":not accepted,"special":special and accepted})
	return plan

## NPC and scenery arrays may have the same numeric index. Keep the selected
## population with the retained pointer instead of inventing offset source IDs.
func target_group() -> String:
	if _state.is_empty():return "npc"
	if _state.current_actor_id>=0:return _state.current_group
	return _state.request_group if _state.request_actor_id>=0 else "npc"

func valid_actor(actor: Dictionary) -> bool:
	if actor.get("target_group","npc") not in ["npc","scenery"]:return false
	if actor.has("freighter_position") and not actor.freighter_position is Vector3i:return false
	if not same_identity(actor) or not Numbers.integer(actor.get("actor_id"),0,2147483647) or not Numbers.integer(actor.get("actor_mode"),0,2147483647) or not Numbers.integer(actor.get("actor_kind"),-1,2147483647) or not Numbers.integer(actor.get("hull"),0,2147483647):return false
	for key in ["active","cargo_eligible","cargo_model_exists","retire_on_transfer","statistics_exempt","body_motion_blocked","body_motion_detached","friendly","special_cargo"]:
		if not actor.get(key) is bool:return false
	for key in ["body_pose","cargo_pose"]:
		if not actor.get(key) is Transform3D or not actor[key].is_finite():return false
	if not valid_entries(actor.get("cargo_entries")) or not actor.get("collision_centers") is Array:return false
	for center in actor.collision_centers:
		if not center is Vector3i:return false
	return true

func valid_hold(hold: Dictionary) -> bool:
	return same_identity(hold) and Numbers.integer(hold.get("capacity"),0,2147483647) and Numbers.integer(hold.get("used"),0,2147483647) and valid_entries(hold.get("entries"))

func valid_entries(entries: Variant) -> bool:
	if not entries is Array:return false
	for row in entries:
		if not row is Dictionary or not Numbers.integer(row.get("item_id"),0,_item_kinds.size()-1) or not Numbers.integer(row.get("quantity"),0,2147483647):return false
	return true

static func first_positive(entries: Array) -> int:
	for i in entries.size():
		if entries[i].quantity>0:return i
	return -1

static func finish(state: Dictionary) -> void:
	if state.current_group=="npc" and state.request_group=="npc":state.candidate_actor_id=-1
	state.active=false;state.current_actor_id=-1;state.request_actor_id=-1;state.loop_started=false
	state.current_group="npc";state.request_group="npc"

func same_identity(value: Dictionary) -> bool:
	for key in _identity:
		if value.get(key)!=_identity[key]:return false
	return not _identity.is_empty()

func snapshot() -> Dictionary:
	if _state.is_empty():return {}
	var result:=_identity.duplicate()
	result.merge(_state.duplicate(true));result["frame"]=_sample.duplicate(true)
	return result

func equipment_loadout() -> Dictionary:return _loadout.duplicate(true)
func transaction_identity() -> RefCounted:return _transaction_identity

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._identity=_identity;copy._rules=_rules;copy._item_kinds=_item_kinds;copy._max_ms=_max_ms
	copy._state=_state.duplicate(true);copy._sample=_sample.duplicate(true)
	copy._loadout=_loadout;copy._transaction_identity=_transaction_identity
	return copy

func clear() -> void:
	error="";_identity={};_rules={};_item_kinds=[];_max_ms=0;_state={};_sample={}
	_loadout={};_transaction_identity=null

func reject(message: String) -> bool:error=message;return false
