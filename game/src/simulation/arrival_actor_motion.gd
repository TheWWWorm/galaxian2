extends RefCounted
## Scripted body motion, statistics synchronization and the mode-five branch.
## The world must supply constructed poses and the result of its earlier NPC
## checks. This owner does not choose a faction, target, cargo or combat state.
const Definitions=preload("res://src/content/arrival_actor_motion_definitions.gd")
const StagingDefinitions=preload("res://src/content/arrival_staging_definitions.gd")
const Location=preload("res://src/simulation/arrival_location.gd")
const Flight=preload("res://src/simulation/npc_flight.gd")
const Poses=preload("res://src/simulation/opening_staging.gd")
const Numbers=preload("res://src/content/opening_definitions.gd")
var error:=""
var _rules:={}
var _state:={}
var _flight: RefCounted

func configure(bindings: RefCounted, catalogues: RefCounted, cache: Variant, construction: Dictionary) -> bool:
	clear()
	if bindings==null or not Definitions.parameters(bindings.arrival_actor_motion):return reject("Rescue actor motion is unavailable in this profile")
	if not StagingDefinitions.parameters(bindings.arrival_staging):return reject("Prepare current resource bindings for corrected rescue visibility")
	var location:=Location.new();var context:=location.resolve(bindings,catalogues,cache)
	if context.is_empty():return reject(location.error)
	for key in ["base_content_id","binding_id","campaign_cursor"]:
		if construction.get(key)!=context.get(key):return reject("Rescue actor construction belongs to another flight")
	if construction.get("actor_id")!=0:return reject("Rescue motion requires the authored actor")
	for key in ["body_pose","statistics_pose","model_local_pose"]:
		if not Flight.rigid_pose(construction.get(key)):return reject("Rescue motion requires explicit finite constructed poses")
	var initial: Vector3=Poses.vec(bindings.arrival_staging.actor_initial_position)
	if construction.body_pose.origin!=initial:return reject("Rescue actor body has not received its authored placement")
	var flight:=Flight.new()
	if not flight.configure(bindings,construction.body_pose):return reject(flight.error)
	_rules=bindings.arrival_actor_motion.duplicate(true)
	_state={"base_content_id":context.base_content_id,"binding_id":context.binding_id,"campaign_cursor":1,
		"actor_id":int(_rules.actor_id),"actor_kind":int(_rules.actor_kind),"hull_catalogue_id":int(_rules.hull_catalogue_id),
		"generation":0,"elapsed_ms":0,"body_pose":construction.body_pose,"statistics_pose":construction.statistics_pose,
		"model_local_pose":construction.model_local_pose,"mode":int(_rules.initial_mode),"active":bool(_rules.initial_active),
		"targeting_blocked":false,"model_draw_enabled":bool(bindings.arrival_staging.actor_model_draw_enabled),
		"engine_draw_enabled":bool(bindings.arrival_staging.actor_engine_draw_enabled),"engine_resource_id":int(bindings.arrival_staging.actor_engine_resource_id),
		"route_index":0,"route_points":bindings.arrival_staging.actor_route_points.duplicate(true),"target_index":-1,"model_visibility_request":{}}
	_flight=flight
	return true

func advance(staging: Dictionary, dispatch: Dictionary) -> bool:
	error=""
	if _state.is_empty():return reject("Configure rescue actor motion before advancing")
	for row in [staging,dispatch]:
		for key in ["base_content_id","binding_id","campaign_cursor"]:
			if row.get(key)!=_state.get(key):return reject("Rescue actor frame belongs to another flight")
		if not Numbers.integer(row.get("generation"),1,2147483647) or row.generation!=_state.generation+1:return reject("Rescue actor frame is stale or skipped")
	if not Numbers.integer(staging.get("elapsed_ms"),_state.elapsed_ms,_state.elapsed_ms+150):return reject("Rescue actor frame has unsupported elapsed time")
	var frame: Variant=staging.get("frame")
	if not frame is Dictionary or frame.get("initial")!=false or frame.get("actor_script_mode")!=int(_rules.script_mode) or not Flight.rigid_pose(frame.get("actor_pose_override")):return reject("Rescue actor frame lacks its scripted pose")
	# Earlier NPC checks can replace mode five (including hostile activation).
	# A missing target-list takes another route path. Neither is inferred here.
	if dispatch.get("mode_at_dispatch")!=int(_rules.script_mode) or dispatch.get("route_has_targets")!=true:return reject("Rescue motion requires the resolved mode-five branch and target list")
	# The earlier hostile activation path still needs a live decision owner.
	# The rescue caller must establish its neutral disposition before using this
	# owner; a mode number alone does not establish that branch's prerequisites.
	if not dispatch.get("actor_hostile") is bool or dispatch.actor_hostile:return reject("Rescue motion requires an explicitly nonhostile actor")
	if not dispatch.get("target_present") is bool or not dispatch.get("target_excluded") is bool:return reject("Rescue motion requires explicit target eligibility")
	var delta: Variant=dispatch.get("target_relative_position")
	if not delta is Vector3 or not delta.is_finite() or not Flight.rigid_pose(dispatch.get("model_local_pose")):return reject("Rescue motion requires finite resolved target and model poses")
	var staged: RefCounted=_flight.fork_for_frame()
	if not staged.apply_scripted_pose(frame.actor_pose_override):return reject(staged.error)
	var next:=_state.duplicate(true)
	next.body_pose=frame.actor_pose_override
	next.model_local_pose=dispatch.model_local_pose
	# This prefix runs before the mode dispatch, even when ordinary motion is
	# held. Keep statistics separate from the model's draw permission.
	next.statistics_pose=next.body_pose*next.model_local_pose
	if not Flight.rigid_pose(next.statistics_pose):return reject("Rescue statistics exceed supported precision")
	next.mode=int(_rules.script_mode);next.active=bool(_rules.script_active)
	next.targeting_blocked=bool(_rules.script_targeting_blocked)
	next.target_index=int(_rules.target_index) if dispatch.target_present else -1
	next.model_visibility_request={}
	var limit:=float(_rules.activation_half_extent)
	if dispatch.target_present and not dispatch.target_excluded and delta.x>-limit and delta.x<limit and delta.y>-limit and delta.y<limit and delta.z>-limit and delta.z<limit:
		next.mode=int(_rules.active_mode);next.active=true
		next.model_draw_enabled=true
		next.model_visibility_request={"enabled":true}
	# The whole-model switch does not alter the attached engine mesh's flag.
	# Activation does not re-enter ordinary movement in this update. The next
	# controller update explicitly selects mode five again.
	next.generation=int(staging.generation);next.elapsed_ms=int(staging.elapsed_ms)
	_state=next;_flight=staged
	return true

func snapshot() -> Dictionary:
	if _state.is_empty():return {}
	var result:=_state.duplicate(true);result.flight=_flight.snapshot()
	return result

func fork_for_frame() -> RefCounted:
	var copy: RefCounted=get_script().new()
	copy._rules=_rules;copy._state=_state.duplicate(true)
	if _flight!=null:copy._flight=_flight.fork_for_frame()
	return copy

func clear() -> void:error="";_rules={};_state={};_flight=null
func reject(message: String) -> bool:error=message;return false
