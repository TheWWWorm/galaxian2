extends RefCounted
const Layouts=preload("res://src/content/declaration_layouts.gd")
## First departure only. Travel, mining completion and save loading are separate.
const Values=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Station=preload("res://src/content/station_entry_definitions.gd")
const Cache=preload("res://src/content/flight_player_cache_definitions.gd")
const Repair=preload("res://src/content/player_repair_definitions.gd")
const VALUES := {"scope":"first_station_departure","campaign_cursor":2,"station_id":78,"system_id":15,"ship_id":0,"source_state":2,"world_type":3,"confirmation_text_id":386,"confirmation_required":true,"cache_reset":-1,"initial_cargo_used":0,"audio_selector":1}
const SPANS := {"cargo_gate":[437015,74],"cursor_gates_early":[437089,44],"cursor_gates_middle":[437352,207],"cursor_gate_late":[437666,79],"confirmation":[437559,96],"accept_and_destination":[431746,142],"cache_reset_and_state":[431888,113],"current_station":[858084,12],"mission_selection":[857476,150],"selected_mission":[857239,27],"mission_getter":[858188,12],"mission_completed":[400436,12],"refresh_equipment":[857965,93],"ship_clone_entry":[732832,28],"ship_clone":[732860,162],"fresh_ship":[727320,240],"cargo_used":[729972,10],"world_entry":[335220,77],"audio_selector_consumer":[337212,42]}

const MAC_ALTERNATE := {"cargo_gate":[437451,72],"cursor_gates_early":[437523,44],"cursor_gates_middle":[437785,277],"cursor_gate_late":[438174,83],"confirmation":[438062,101],"accept_and_destination":[432174,142],"cache_reset_and_state":[432316,113],"current_station":[858716,12],"mission_selection":[858108,150],"selected_mission":[857871,27],"mission_getter":[858820,12],"mission_completed":[400952,12],"refresh_equipment":[858597,93],"ship_clone_entry":[733464,28],"ship_clone":[733492,162],"fresh_ship":[727944,240],"cargo_used":[730596,10],"world_entry":[334920,77],"audio_selector_consumer":[336912,42]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1 or not data.get("provenance") is Dictionary:return false
	for key in VALUES:
		if not Values.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, station: Dictionary, player: Dictionary) -> String:
	if not data is Dictionary:return "Missing first-departure declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data):return "Unsupported first-departure declarations"
	if not Station.parameters(station) or not Cache.parameters(player.get("flight_cache",{})) or not Repair.parameters(player.get("repair",{})):return "First departure requires the station and ordinary player restoration"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "First departure lacks its source anchor"
	if data.provenance.size()!=SPANS.size():return "Invalid first-departure provenance"
	return "" if Layouts.matches(data.provenance,int(origin.offset),source_bytes,[SPANS,MAC_ALTERNATE]) else "Invalid station departure extent"
