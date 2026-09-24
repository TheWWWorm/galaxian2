extends RefCounted
## Per-edition sound tables and verified ordinary firing ownership.
const Numbers=preload("res://src/content/opening_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Layouts=preload("res://src/content/declaration_layouts.gd")

const VALUES := {"player_sound_limit":2,"npc_sound_limit":1,"initial_enabled":true,"disabled_world_type":2,"price_low_index":15,"price_high_index":17,"sort":"descending_midpoint_price","enabled_index":"sorted_copy_index","duplicates":"first_item_id","position":"firing_owner","instance":"cached_event","requires_successful_launch":true,"player_pitch":"nonnegative_one_minus_interval_multiplier","npc_pitch":0.0,"continuous_kinds":[2,3,8],"npc_default_event_id":61}
const NPC_EVENTS := [52, 55, 54, 53, 61, 61, 61, 61, 61, 62, 2276]
const SPANS := {"x86_64":{"owner_defaults":[412873,25],"owner_setter":[413737,26],"player_limit":[429491,21],"npc_backlink_call":[-202971,12],"npc_backlink_setter":[413763,14],"npc_world_gate":[-66553,26],"weapon_defaults":[-311196,25],"primary_select":[419113,457],"single_install_gate":[419053,17],"single_install_select":[419089,24],"bulk_install_gate":[419915,22],"bulk_install_select":[419956,29],"player_install":[440229,17],"player_install_call":[-157396,5],"npc_install":[-199451,14],"npc_install_call":[-64368,29],"dispatch":[420317,280],"fire_success":[420917,176],"pitch_update":[215010,55],"pitch_wrapper":[482865,13],"pitch_setter":[423427,66],"price_layout":[-206893,140],"price_getter":[-206667,10],"interval_getter":[607601,11],"npc_dispatch_table":[420599,44],"player_table":[1464783,932]},"armv7":{"owner_defaults":[371646,22],"owner_setter":[372386,16],"player_limit":[384836,18],"npc_backlink_call":[-193898,8],"npc_backlink_setter":[372402,6],"npc_world_gate":[-67352,20],"weapon_zero_register":[-294266,2],"weapon_defaults":[-294070,18],"primary_select":[376678,348],"single_install_select":[376586,22],"bulk_install_select":[377338,22],"player_install":[394066,12],"player_install_call":[-153370,16],"npc_install":[-190846,6],"npc_install_call":[-65544,24],"dispatch":[377614,192],"fire_success":[378068,110],"pitch_update":[226382,52],"pitch_wrapper":[426346,6],"pitch_setter":[379986,50],"price_layout":[-196950,84],"price_getter":[-196798,4],"interval_getter":[537622,4],"player_table":[2351530,932],"npc_table":[2352474,44]}}

const MAC_ALTERNATE := {"owner_defaults":[413409,25],"owner_setter":[414273,26],"player_limit":[430027,21],"npc_backlink_call":[-202971,12],"npc_backlink_setter":[414299,14],"npc_world_gate":[-66553,26],"weapon_defaults":[-311688,25],"primary_select":[419649,457],"single_install_gate":[419589,17],"single_install_select":[419625,24],"bulk_install_gate":[420451,22],"bulk_install_select":[420492,29],"player_install":[440765,17],"player_install_call":[-157396,5],"npc_install":[-199451,14],"npc_install_call":[-64368,29],"dispatch":[420853,280],"fire_success":[421453,176],"pitch_update":[214710,55],"pitch_wrapper":[483413,13],"pitch_setter":[423963,66],"price_layout":[-206893,140],"price_getter":[-206667,10],"interval_getter":[608225,11],"npc_dispatch_table":[421135,44],"player_table":[1439847,932]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+3 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		var expected: Variant=VALUES[key]
		var value: Variant=data.get(key)
		if expected is int:
			if not Numbers.integer(value,expected,expected):return false
		elif expected is float:
			if not (value is int or value is float) or not is_finite(value) or value!=expected:return false
		elif expected is Array:
			if not value is Array or value.size()!=expected.size():return false
			for i in expected.size():
				if not Numbers.integer(value[i],expected[i],expected[i]):return false
		elif typeof(value)!=typeof(expected) or value!=expected:return false
	var player: Variant=data.get("player_event_ids")
	var npc: Variant=data.get("npc_event_ids")
	if not player is Array or player.size()!=233 or not npc is Array or npc.size()!=11:return false
	for id in player:
		if not Numbers.integer(id,-1,19999):return false
	for i in npc.size():
		if not Numbers.integer(npc[i],NPC_EVENTS[i],NPC_EVENTS[i]):return false
	return true

static func validate(data: Variant, executable_bytes: int, architecture: String, weapons: Dictionary, actors: Dictionary, staging: Dictionary) -> String:
	if not data is Dictionary:return "Invalid weapon audio capability"
	if data.is_empty():return ""
	if not parameters(data) or not SPANS.has(architecture):return "Unsupported weapon audio declarations"
	var origin: Variant=staging.get("provenance",{}).get("initial",{}).get("offset")
	if not Numbers.integer(origin,0,executable_bytes):return "Weapon audio lacks its opening anchor"
	var npc: Dictionary=actors.get("npc_initialization",{})
	if staging.get("player_flight",{}).is_empty() or npc.get("world_initialization",{}).is_empty() or npc.world_initialization.world_type==data.disabled_world_type:return "Weapon audio lacks its supported world context"
	var spans: Dictionary=SPANS[architecture]
	if data.provenance.size()!=spans.size():return "Invalid weapon audio provenance"
	var layouts: Array=[spans]
	if architecture=="x86_64":layouts.append(MAC_ALTERNATE)
	if not Layouts.matches(data.provenance,int(origin),executable_bytes,layouts):return "Disconnected weapon audio declaration"
	for pair in [["price_layout","item_layout"],["price_getter","price"]]:
		if data.provenance[pair[0]]!=npc.get("construction",{}).get("provenance",{}).get(pair[1]):return "Weapon audio price is disconnected from the catalogue"
	if data.provenance.interval_getter!=weapons.get("provenance",{}).get("interval_getter"):return "Weapon audio pitch is disconnected from its equipment modifier"
	return ""
