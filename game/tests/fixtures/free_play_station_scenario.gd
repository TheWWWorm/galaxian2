extends "res://tests/fixtures/convoy_station_scenario.gd"
## Earned Alioth return, before implementation of the subsequent free-play loop.
func accepts(state: Dictionary,bindings: RefCounted) -> bool:
	return state.get("base_content_id")==bindings.base_content_id and state.get("binding_id")==bindings.binding_id \
		and state.get("campaign_cursor")==18 and state.get("phase")=="free_play_required" \
		and state.get("alioth_return_acknowledged",false) and state.get("acknowledged",false) \
		and state.get("loadout",{}).get("station_id")==98 and state.get("equipment",{}).get("ship_affiliation")==0 \
		and state.get("mission")=={"kind":156,"station_id":56,"reward":0,"bonus":0,"source_parameter":0} \
		and state.get("completed_side_missions")==4 and state.get("contracts",{}).get("completed_side_missions")==4 \
		and state.get("progress")==state.get("contracts",{}).get("progress")
