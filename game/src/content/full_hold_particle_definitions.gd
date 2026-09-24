extends RefCounted
const Layouts=preload("res://src/content/declaration_layouts.gd")
## Mac second-trip sprite parameters. Frame order and rendering have separate
## owners; these declarations do not by themselves enable a flight effect.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Damage=preload("res://src/content/damage_particle_definitions.gd")
const Owners=preload("res://src/content/damage_particle_owner_definitions.gd")
const Flight=preload("res://src/content/full_hold_flight_definitions.gd")
const Death=preload("res://src/content/player_destruction_definitions.gd")
const VALUES := {"scope":"mac_full_hold_sprite_particles","departure_cursor":4,"story_cursors":[4,5],"player_preset":9,"npc_preset":9,"npc_smoke_preset":15,"npc_fire_preset":42,"npc_count":1,"burst_preset":11,"burst_member_index":0,"burst_count":1,"burst_size_override":-1,"burst_position":"statistics_before_death_spin","player_root":"physical","npc_root":"retained_unbanked","player_smoke_fire_max_cursor":1,"player_initial_emitting":false,"npc_initial_emitting":false,"burst_initial_emitting":true,"initial_visible":true,"manual_emission_ignores_flags":true,"presets":[{"preset_id":9,"material_id":20099,"flags":33554465,"capacity":16,"size_jitter":1000,"lifetime_ms":700,"even_spacing":1,"fade_in_ms":0,"size_growth_per_second":500,"scatter_xz":300,"scatter_y":300,"velocity_scatter":0,"animation_frames":16,"size":100.0,"emission_per_second":8.0,"relative_velocity_factor":1.0,"local_velocity_z":0.0,"local_offset_y":0.0,"local_offset_z":-250.0,"local_offset_z_jitter":500.0,"start_rgba":[255,255,255,255],"end_rgba":[255,255,255,255],"uv_rect":[0.0,0.0,0.25,0.25]},{"preset_id":11,"material_id":20099,"flags":33554689,"capacity":10,"size_jitter":1000,"lifetime_ms":1500,"even_spacing":0,"fade_in_ms":0,"size_growth_per_second":500,"scatter_xz":0,"scatter_y":0,"velocity_scatter":0,"animation_frames":16,"size":2000.0,"emission_per_second":500.0,"relative_velocity_factor":0.0,"local_velocity_z":0.0,"local_offset_y":0.0,"local_offset_z":0.0,"local_offset_z_jitter":0.0,"start_rgba":[255,255,255,255],"end_rgba":[255,255,255,255],"uv_rect":[0.0,0.0,0.25,0.25]}]}
const SPANS := {"defaults":[483042,211],"trail_preset":[491375,293],"burst_preset":[494947,245],"general_material":[-43613,44],"player_registration":[559640,232],"npc_registration":[608550,340],"world_burst_registration":[63207,30],"emitter_registration":[510706,264],"initial_flags":[513047,12],"continuous_gate":[514369,85],"manual_wrapper":[512454,66],"manual_emission":[518916,1982],"burst_position_sample":[582756,250],"burst_position_retained":[583006,1194],"statistics_position_getter":[1241402,96],"position_addition_value":[1059226,144],"player_breakup":[584583,93],"npc_death_enable":[619399,28],"npc_breakup_disable":[626315,25]}

const MAC_ALTERNATE := {"defaults":[483570,211],"trail_preset":[491903,293],"burst_preset":[495475,245],"general_material":[-43613,44],"player_registration":[560176,232],"npc_registration":[609098,340],"world_burst_registration":[63207,30],"emitter_registration":[511242,264],"initial_flags":[513583,12],"continuous_gate":[514905,85],"manual_wrapper":[512990,66],"manual_emission":[519452,1982],"burst_position_sample":[583292,250],"burst_position_retained":[583542,1194],"statistics_position_getter":[1234194,96],"position_addition_value":[1059954,128],"player_breakup":[585119,93],"npc_death_enable":[619947,28],"npc_breakup_disable":[626863,25]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	for row in data.presets:
		if not Damage.sprite_preset(row):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, flight: Dictionary, death: Dictionary, damage: Dictionary) -> String:
	if not data is Dictionary:return "Missing second-flight particle declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data):return "Unsupported second-flight particle declarations"
	if not Flight.parameters(flight) or not Death.parameters(death) or not Damage.emitter_parameters(damage) or not Owners.parameters(damage.get("owners")) or not damage.owners.npc_uses_detail_gate:return "Second-flight particles lack their verified owners or shared emitter defaults"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Second-flight particles lack their source anchor"
	var layouts: Array=[SPANS,MAC_ALTERNATE]
	return "" if Layouts.matches(data.provenance,int(origin.offset),source_bytes,layouts) else "Invalid full hold particles extents"
