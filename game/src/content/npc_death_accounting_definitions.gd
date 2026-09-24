extends RefCounted
## Verified counter changes, without inferred save totals or mission rewards.
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")
const Layouts = preload("res://src/content/declaration_layouts.gd")
const VALUES := {"actor_kind":8,"initial_nonplayer_kill":false,"nonplayer_flag_on_lethal_hit":true,"credit_on_destruction_start":true,"requires_hostile":true,"hostile_remaining_delta":-1,"hostile_deaths_delta":1,"world_player_kills_delta":1,"world_other_kills_delta":1,"player_kills_delta":1,"pirate_kills_delta":1}
const SPANS := {"x86_64":{"initial_attribution":[-75841,4],"hit_argument":[-71830,82],"lethal_attribution":[-70390,38],"death_guard":[7251,28],"hostile_kind":[7681,32],"pirate_credit":[7713,30],"world_call":[8146,29],"world_counters":[-504241,44],"other_counter":[-503229,4],"player_counter":[265484,26],"pirate_counter":[265534,26]},"armv7":{"initial_attribution":[-59644,26],"hit_argument":[-56288,66],"lethal_attribution":[-55290,22],"death_guard":[5132,18],"hostile_kind":[5630,24],"pirate_credit":[5864,32],"world_call":[6136,28],"world_counters":[-443192,66],"player_counter":[266600,28],"pirate_counter":[266644,28]}}

const MAC_ALTERNATE := {"initial_attribution":[-75853,4],"hit_argument":[-71842,82],"lethal_attribution":[-70402,38],"death_guard":[7251,28],"hostile_kind":[7681,32],"pirate_credit":[7713,30],"world_call":[8146,29],"world_counters":[-504789,44],"other_counter":[-503777,4],"player_counter":[265568,26],"pirate_counter":[265618,26]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary: return false
	for key in VALUES:
		var value: Variant=data.get(key)
		var expected: Variant=VALUES[key]
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
	if not data is Dictionary: return "Invalid NPC death accounting capability"
	if data.is_empty(): return ""
	if not parameters(data) or not SPANS.has(architecture): return "Unsupported NPC death accounting declarations"
	for key in ["guidance","destruction","hostility","primary_weapon"]:
		if not npc.get(key) is Dictionary or npc[key].is_empty(): return "NPC death accounting lacks source dependencies"
	var selection: Variant=npc.guidance.get("provenance",{}).get("selection")
	if not Fonts.extent(selection,"offset","bytes",[119 if architecture=="x86_64" else 132],executable_bytes): return "NPC death accounting lacks its guidance anchor"
	var update: int=int(selection.offset)-(2095 if architecture=="x86_64" else 2026)
	if data.provenance.size()!=SPANS[architecture].size(): return "Invalid NPC death accounting provenance"
	var layouts: Array=[SPANS[architecture]]
	if architecture=="x86_64":layouts.append(MAC_ALTERNATE)
	if not Layouts.matches(data.provenance,update,executable_bytes,layouts):return "Disconnected NPC death accounting declaration"
	var stats: Variant=npc.get("provenance",{}).get("stats_entry")
	if not Fonts.extent(stats,"offset","bytes",[20 if architecture=="x86_64" else 28],executable_bytes): return "NPC death accounting lacks its statistics owner"
	if int(stats.offset)+(0x2f9 if architecture=="x86_64" else 0x20c)!=int(data.provenance.initial_attribution.offset): return "Disconnected NPC attribution initializer"
	return ""
