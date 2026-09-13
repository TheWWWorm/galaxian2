extends RefCounted
## Fresh opening NPC maximum hull and source integer health percentages.
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")
const VALUES := {"scope":"fresh_opening","rank":0,"campaign_cursor":0,"factory_subtype":0,"hull_catalogue_ids":[2,23,2],"base_hull":20,"difficulty_offset":-0.5,"percentage_scale":100.0,"override_raises_maximum":true}
const SPANS := {"x86_64":{"factory_arguments":[17,38],"rank_base":[166,46],"cursor_and_hull_modifiers":[224,129],"subtype":[399,43],"difficulty":[442,73],"stats_argument":[558,27],"stats_wrapper":[456210,10],"initial_capacity":[456393,12],"hull_setter":[459070,30],"percentage":[457204,42],"rank_getter":[798406,12],"rank_reset":[802796,11],"cursor_getter":[780212,12],"cursor_predicate":[780196,16],"difficulty_constant":[1495834,4],"percentage_constant":[1478982,4],"entry_rank":[257276,48],"rank_calculation":[798084,136],"score_reset_a":[802734,22],"score_reset_b":[802818,11],"score_reset_c":[803231,22],"score_reset_d":[803684,11],"rank_thresholds_constant":[1513666,84]},"armv7":{"factory_arguments":[28,28],"rank_base":[226,64],"cursor_and_hull_modifiers":[290,116],"subtype":[446,36],"difficulty":[482,92],"stats_argument":[626,8],"stats_wrapper":[418096,30],"initial_capacity":[417296,14],"hull_setter":[419896,18],"percentage":[417944,36],"rank_getter":[744032,6],"rank_reset":[748506,40],"cursor_getter":[725104,6],"cursor_predicate":[725088,14],"percentage_literal":[418080,4],"entry_rank":[270940,44],"rank_calculation":[743808,120],"score_reset_a":[748498,56],"score_reset_c":[748854,8],"score_reset_d":[749156,8],"rank_thresholds_constant":[2402916,84]}}
const LEGACY_SPANS := {"x86_64":{"factory_arguments":[17,38],"rank_base":[166,46],"cursor_and_hull_modifiers":[224,129],"subtype":[399,43],"difficulty":[442,73],"stats_argument":[558,27],"stats_wrapper":[456210,10],"initial_capacity":[456393,12],"hull_setter":[459070,30],"percentage":[457204,42],"rank_getter":[798406,12],"rank_reset":[802796,11],"cursor_getter":[780212,12],"cursor_predicate":[780196,16],"difficulty_constant":[1495834,4],"percentage_constant":[1478982,4]},"armv7":{"factory_arguments":[28,28],"rank_base":[226,64],"cursor_and_hull_modifiers":[290,116],"subtype":[446,36],"difficulty":[482,92],"stats_argument":[626,8],"stats_wrapper":[418096,30],"initial_capacity":[417296,14],"hull_setter":[419896,18],"percentage":[417944,36],"rank_getter":[744032,6],"rank_reset":[748506,40],"cursor_getter":[725104,6],"cursor_predicate":[725088,14],"percentage_literal":[418080,4]}}

static func parameters(data: Variant) -> bool:
	return _parameters(data,VALUES)

static func legacy_parameters(data: Variant) -> bool:
	var values:=VALUES.duplicate(true);values.rank=1;values.base_hull=34
	return _parameters(data,values)

static func _parameters(data: Variant, values: Dictionary) -> bool:
	if not data is Dictionary or data.size()!=values.size()+1 or not data.get("provenance") is Dictionary: return false
	for key in values:
		var value: Variant=data.get(key)
		var expected: Variant=values[key]
		if expected is int:
			if not Numbers.integer(value,expected,expected): return false
		elif expected is float:
			if not (value is float or value is int) or value!=expected: return false
		elif expected is Array:
			if not value is Array or value.size()!=expected.size(): return false
			for i in expected.size():
				if not Numbers.integer(value[i],expected[i],expected[i]): return false
		elif typeof(value)!=typeof(expected) or value!=expected: return false
	return true

static func validate(data: Variant, executable_bytes: int, architecture: String, npc: Dictionary) -> String:
	if not data is Dictionary: return "Invalid NPC hull capability"
	if data.is_empty(): return ""
	var legacy:=legacy_parameters(data)
	if (not parameters(data) and not legacy) or not SPANS.has(architecture): return "Unsupported NPC hull"
	var world: Variant=npc.get("world_initialization",{})
	if not world is Dictionary or world.get("campaign_cursor")!=VALUES.campaign_cursor: return "NPC hull requires the fresh campaign context"
	var initial: Variant=npc.get("provenance",{}).get("factory_entry")
	if not Fonts.extent(initial,"offset","bytes",[4],executable_bytes): return "NPC hull lacks its factory anchor"
	var spans: Dictionary=LEGACY_SPANS[architecture] if legacy else SPANS[architecture]
	if data.provenance.size()!=spans.size(): return "Invalid NPC hull provenance"
	for key in spans:
		var rule: Array=spans[key]
		var span: Variant=data.provenance.get(key)
		if not Fonts.extent(span,"offset","bytes",[rule[1]],executable_bytes) or int(span.offset)!=int(initial.offset)+int(rule[0]): return "Disconnected NPC hull declaration"
	return ""
