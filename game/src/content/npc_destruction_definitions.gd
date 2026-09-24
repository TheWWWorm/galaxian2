extends RefCounted
## Source-backed clocks and motion for the fresh opening death path.
const Numbers = preload("res://src/content/opening_definitions.gd")
const Fonts = preload("res://src/content/font_definitions.gd")
const Layouts = preload("res://src/content/declaration_layouts.gd")
const VALUES := {"actor_kind":8,"dying_mode":3,"explosion_mode":4,"delay_base_ms":1500,"delay_bound_ms":1500,"axis_bound":200,"axis_offset":-100,"spin_scale":0.05000000074505806,"rotation_order":"XYZ","rotation_per_update":true,"death_sound":20,"breakup_sound_base":18,"breakup_sound_bound":2,"drift_bound":50,"drift_scale":0.009999999776482582,"drift_base":50.0,"effect_type":0,"model_ids":[16821,16820],"fragment_model_id":14292,"cargo_absent":true,"retire_on_following_update":true,"trigger_uses_pre_motion_position":true,"discard_delay_overshoot":true}
const SPANS := {"x86_64":{"early_retirement":[40,61],"death_guard":[7251,28],"initial_delay":[8207,109],"initial_spin":[8437,196],"tumble":[15113,436],"breakup_draws":[15645,255],"explosion_mode":[16020,34],"cleanup":[16963,75],"cargo_predicate":[-687786,46],"sound_choice":[-1292354,79],"type_zero_models":[-1295321,122],"effect_update":[-1291224,538],"retire":[-689620,18],"active_setter":[-69856,14],"spin_constant":[963016,4],"drift_multiplier":[946148,4],"drift_base":[946312,4]},"armv7":{"early_retirement":[114,60],"death_guard":[5132,18],"initial_delay":[6164,84],"initial_spin":[6346,150],"tumble":[7008,268],"breakup_draws":[7338,192],"explosion_mode":[7624,24],"cleanup":[10066,80],"cargo_predicate":[-621716,40],"sound_choice":[-1576468,78],"type_zero_models":[-1579526,128],"effect_update":[-1575644,424],"retire":[-623276,8],"active_setter":[-54908,8],"drift_multiplier":[7656,4],"drift_base":[7660,4]}}

const MAC_ALTERNATE := {"early_retirement":[40,61],"death_guard":[7251,28],"initial_delay":[8207,109],"initial_spin":[8437,196],"tumble":[15113,436],"breakup_draws":[15645,255],"explosion_mode":[16020,34],"cleanup":[16963,75],"cargo_predicate":[-688334,46],"sound_choice":[-1298790,79],"type_zero_models":[-1301757,122],"effect_update":[-1297660,538],"retire":[-690168,18],"active_setter":[-69868,14],"spin_constant":[937532,4],"drift_multiplier":[920600,4],"drift_base":[920764,4]}

const MAC_AUDIO_ALTERNATE := {"initial":[8316,121],"breakup_entry":[-1299024,10],"breakup_call":[-1298807,17]}

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

static func audio_parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=5 or not Numbers.integer(data.get("initial_source_id"),20,20) or data.get("position")!="pre_motion" or data.get("instance")!="cached_event" or not data.get("provenance") is Dictionary:return false
	var ids: Variant=data.get("breakup_source_ids")
	return ids is Array and ids.size()==2 and Numbers.integer(ids[0],18,18) and Numbers.integer(ids[1],19,19)

static func validate_audio(data: Variant, executable_bytes: int, architecture: String, npc: Dictionary) -> String:
	if not data is Dictionary:return "Invalid NPC destruction audio capability"
	if data.is_empty():return ""
	if not audio_parameters(data) or not parameters(npc.get("destruction")) or not SPANS.has(architecture):return "Unsupported NPC destruction audio declarations"
	if not validate(npc.destruction,executable_bytes,architecture,npc).is_empty():return "NPC audio lacks verified destruction ownership"
	var selection: Dictionary=npc.guidance.provenance.selection
	var update: int=int(selection.offset)-(2095 if architecture=="x86_64" else 2026)
	var spans: Dictionary={"initial":[8316,121],"breakup_entry":[-1292588,10],"breakup_call":[-1292371,17]} if architecture=="x86_64" else {"initial":[6248,98],"breakup_entry":[-1576620,8],"breakup_call":[-1576342,10]}
	var layouts: Array=[spans]
	if architecture=="x86_64":layouts.append(MAC_AUDIO_ALTERNATE)
	return "" if Layouts.matches(data.provenance,update,executable_bytes,layouts) else "Disconnected NPC destruction audio declaration"

static func validate(data: Variant, executable_bytes: int, architecture: String, npc: Dictionary) -> String:
	if not data is Dictionary: return "Invalid NPC destruction capability"
	if data.is_empty(): return ""
	if not parameters(data) or not SPANS.has(architecture): return "Unsupported NPC destruction declarations"
	var guidance: Variant=npc.get("guidance")
	var construction: Variant=npc.get("construction")
	if not guidance is Dictionary or not guidance.get("provenance") is Dictionary or not construction is Dictionary or construction.is_empty(): return "NPC destruction lacks source guidance or construction"
	var selection: Variant=guidance.provenance.get("selection")
	if not selection is Dictionary or not Fonts.extent(selection,"offset","bytes",[119 if architecture=="x86_64" else 132],executable_bytes): return "NPC destruction lacks its guidance anchor"
	var update: int=int(selection.offset)-(2095 if architecture=="x86_64" else 2026)
	if data.provenance.size()!=SPANS[architecture].size(): return "Invalid NPC destruction provenance"
	var layouts: Array = [SPANS[architecture]]
	if architecture=="x86_64":layouts.append(MAC_ALTERNATE)
	return "" if Layouts.matches(data.provenance,update,executable_bytes,layouts) else "Disconnected NPC destruction declaration"
