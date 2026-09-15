extends "res://tests/fixtures/convoy_station_scenario.gd"
## Actual earned station after the Alioth conversation; no player save format.
func accepts(state: Dictionary,bindings: RefCounted) -> bool:
	return bindings.mido_travel.has("alioth_flight") and state.get("base_content_id")==bindings.base_content_id and state.get("binding_id")==bindings.binding_id and state.get("campaign_cursor")==16 and state.get("phase")=="alioth_departure_required" and state.get("alioth_conversation_acknowledged",false) and state.get("loadout",{}).get("station_id")==98 and state.get("completed_side_missions")==4 and state.get("contracts",{}).get("completed_side_missions")==4 and state.get("contracts",{}).get("campaign_cursor")==16 and state.get("progress")==state.get("contracts",{}).get("progress")
