extends RefCounted
## Original equipped EMP ammunition, firing order and launch audio.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const VALUES = {"scope":"equipped_emp_ownership","category":1,"item_ids":[41,42,43],"firing_slots_reversed":true,"update_slots_forward":true,"one_launch_per_trigger":true,"detonate_before_selection":true,"remove_empty_slot":true,"retain_empty_launcher":true,"no_selection":-1,"clear_selection_on_empty_attempt":true,"launch_audio":{"event_ids":[6,7,8],"pitch_raw":0.0,"requires_owner_permission":true,"requires_weapon_sound_flag":false,"position":"owner_origin","detonation_uses_launch_audio":false}}
const SPANS = {"secondary_equipment_factory":[-35917,338],"secondary_category_owner":[541730,282],"secondary_trigger":[543392,646],"secondary_player_request":[560016,320],"secondary_launch_quantity":[-187771,81],"secondary_consume":[-185977,281],"secondary_item_quantity":[-84494,10],"secondary_item_consume":[-84484,10],"secondary_remove_item":[732494,90],"secondary_item_identity":[-81946,20],"secondary_launch_sounds":[1586974,12],"secondary_sound_dispatch":[542344,326]}

# Native composition.
const EMP=preload("res://src/content/emp_bombs_definitions.gd")
const MAC_SPANS = {"secondary_equipment_factory":[-35917,338],"secondary_category_owner":[542266,282],"secondary_trigger":[543928,646],"secondary_player_request":[560552,320],"secondary_launch_quantity":[-188263,81],"secondary_consume":[-186469,281],"secondary_item_quantity":[-84494,10],"secondary_item_consume":[-84484,10],"secondary_remove_item":[733126,90],"secondary_item_identity":[-81946,20],"secondary_launch_sounds":[1562038,12],"secondary_sound_dispatch":[542880,326]}

static func parameters(data: Variant) -> bool:return Equal.equal_value(data,VALUES)
static func available(bindings: RefCounted) -> bool:
	return EMP.available(bindings) and parameters(bindings.mido_travel.get("secondary_ownership"))
