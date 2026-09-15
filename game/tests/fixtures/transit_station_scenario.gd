extends "res://tests/fixtures/convoy_station_scenario.gd"
## Earned application station immediately before the13 story acknowledgement.
func accepts(state: Dictionary,bindings: RefCounted) -> bool:
	return bindings.mido_travel.has("convoy_transit") and state.get("base_content_id")==bindings.base_content_id and state.get("binding_id")==bindings.binding_id and state.get("campaign_cursor")==13 and state.get("phase")=="conversation" and state.get("contract_conversation",false) and state.get("loadout",{}).get("station_id") in [75,76,77,78,79] and state.get("completed_side_missions")==4 and state.get("contracts",{}).get("completed_side_missions")==4 and state.get("progress")==state.get("contracts",{}).get("progress")
