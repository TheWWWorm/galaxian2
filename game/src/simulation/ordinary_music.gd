extends RefCounted
## Pure selector over the retained current music ID and one accepted radar sample.
## Playback, fade and lifetime stay with the shared audio presentation owner.
const Definitions=preload("res://src/content/ordinary_music_definitions.gd")
var error:=""
var _rules: Dictionary={}

## Classify one accepted flight/radar observation. The source compares station
## IDs, not location pointers:
## selected +0x218, retained Void +0xB8, and career source +0xC4. The two
## radar flags are the source's counted kind-10 and marked-actor conditions.
## HomeBase, Valkyrie and system27 peace branches remain outside this owner.
static func context_kind(context: Dictionary, battle_count: int) -> String:
	for key in ["world_type","campaign_cursor","selected_station_id","retained_void_station_id","void_source_station_id","system_id"]:
		if not context.has(key):return ""
	for key in ["world_type","campaign_cursor","selected_station_id","retained_void_station_id","void_source_station_id","system_id"]:
		if not context[key] is int:return ""
	if battle_count<0 or context.world_type!=3 or context.campaign_cursor<0:return ""
	if context.system_id==27 or context.selected_station_id in [101,108]:return ""
	if context.selected_station_id==context.retained_void_station_id:
		if context.selected_station_id==-1 and context.system_id==-1:return "portal"
		if context.selected_station_id>=0 and context.system_id>=0:return "portal"
	if context.selected_station_id<0 or context.system_id<0:return ""
	if context.selected_station_id==context.void_source_station_id:return "portal"
	if battle_count>0:
		if context.campaign_cursor==16:return "portal"
		if not context.get("radar_kind10") is bool or not context.get("radar_marked_actor") is bool:return ""
		if context.radar_kind10:return "kind10"
		if context.radar_marked_actor:return "marked"
		return "ordinary"
	if context.campaign_cursor==1:return "intro"
	if context.selected_station_id in [10,100]:return "deep_science"
	return "ordinary"

static func ordinary_context(context: Dictionary, battle_count: int) -> bool:
	return context_kind(context,battle_count)=="ordinary"

func configure(rules: Dictionary) -> bool:
	error=""
	if not Definitions.parameters(rules):error="Ordinary music requires verified source rules";return false
	_rules=rules.duplicate(true)
	# Imported JSON numbers arrive as floats; retained-ID membership is typed.
	# Normalize once at the accepted declaration boundary, before frame queries.
	for key in ["battle_retained_ids","peace_retained_ids"]:
		_rules[key]=PackedInt32Array(_rules[key])
	return true

func prepare(current_music_id: int, battle_count: int, faction: int, radar_sampled: bool, ordinary_context: bool) -> Dictionary:
	error=""
	if not _valid_input(current_music_id,battle_count,faction,true):return {}
	if not ordinary_context:
		error="Special music selection requires its own source-backed scene owner";return {}
	return _prepare_kind(current_music_id,battle_count,faction,radar_sampled,"ordinary")

## The accepted normal-world adapter uses the same retained-ID and count rules
## for source-backed portal, Thynome and special battle cues.
func prepare_for_context(current_music_id: int,battle_count: int,faction: int,radar_sampled: bool,context: Dictionary) -> Dictionary:
	error=""
	if not _valid_input(current_music_id,battle_count,faction,false):return {}
	if not radar_sampled:return {"operations":[],"selected_id":current_music_id}
	if current_music_id==int(_rules.intro_hold_id):return {"operations":[],"selected_id":current_music_id}
	var kind: String=context_kind(context,battle_count)
	if kind.is_empty():error="This flight needs an unsupported location music branch or missing radar context";return {}
	if kind=="ordinary" and battle_count==0 and faction<0:error="Ordinary peace music needs the current system faction";return {}
	return _prepare_kind(current_music_id,battle_count,faction,true,kind)

func _valid_input(current_music_id: int,battle_count: int,faction: int,require_faction: bool) -> bool:
	if _rules.is_empty() or current_music_id< -1 or current_music_id>2292 or battle_count<0 or battle_count>2147483647 or faction< -1 or faction>=_rules.faction_event_ids.size() or (require_faction and faction<0):
		error="Ordinary music received an invalid retained audio or radar state";return false
	return true

func _prepare_kind(current_music_id: int,battle_count: int,faction: int,radar_sampled: bool,kind: String) -> Dictionary:
	if not radar_sampled or current_music_id==int(_rules.intro_hold_id):return {"operations":[],"selected_id":current_music_id}
	if battle_count>0:
		if current_music_id in _rules.battle_retained_ids:return {"operations":[],"selected_id":current_music_id}
	else:
		if current_music_id in _rules.peace_retained_ids:return {"operations":[],"selected_id":current_music_id}
	var target: int=_target(kind,battle_count,faction)
	if target<0:error="Unsupported source music selection branch";return {}
	return {"operations":[{"action":"replace_music","source_id":target}],"selected_id":target}

func _target(kind: String,battle_count: int,faction: int) -> int:
	if battle_count>0:
		if kind=="portal":return int(_rules.portal_battle_id)
		if kind=="kind10":return int(_rules.kind10_battle_id)
		if kind=="marked":return int(_rules.marked_battle_event_ids[0 if battle_count<=int(_rules.marked_battle_maximum) else 1])
		if kind=="ordinary":return int(_rules.battle_event_ids[0 if battle_count<=int(_rules.battle_maximums[0]) else 1 if battle_count<=int(_rules.battle_maximums[1]) else 2])
	else:
		if kind=="portal":return int(_rules.portal_peace_id)
		if kind=="intro":return int(_rules.intro_hold_id)
		if kind=="deep_science":return int(_rules.deep_science_peace_id)
		if kind=="ordinary":return int(_rules.faction_event_ids[faction])
	return -1
