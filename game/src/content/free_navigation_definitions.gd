extends RefCounted
## Original route and guidance declarations. This capability does not expose a world.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Base=preload("res://src/content/base_contract_navigation_definitions.gd")
const Return=preload("res://src/content/alioth_return_definitions.gd")
const VALUES = {"scope":"base_system_navigation","gate_station_field":6,"gate_environment_object_index":1,"route_available_neighbors_only":true,"route_order":"fewest_links_catalogue_order","same_station_clears_course":true,"pending_story_requires_station_match":true}
const SPANS = {"free_navigation_gate_helpers":[735008,198],"free_navigation_route_graph":[901582,608],"free_navigation_route_search":[902190,430],"free_navigation_route_predecessors":[902620,288],"free_navigation_queue_removal":[903154,98],"free_navigation_course":[137826,368],"free_navigation_story_selection":[856965,661]}

static func parameters(data: Variant) -> bool:
	return Equal.equal_value(data,VALUES)

static func available(bindings: RefCounted) -> bool:
	return bindings!=null and Base.available(bindings) and Return.available(bindings) and parameters(bindings.mido_travel.get("free_navigation"))

static func ordinary_departure_at(bindings: RefCounted,cursor: int,story: Dictionary,station_id: int) -> bool:
	if not available(bindings):return false
	var rules: Dictionary=bindings.mido_travel.alioth_return
	var expected:={"kind":int(rules.next_kind),"station_id":int(rules.next_station_id),"reward":0,"bonus":0,"source_parameter":0}
	return cursor==int(rules.next_cursor) and story==expected and station_id>=0 and station_id<int(bindings.early_contracts.base_navigation.global_station_bound) and station_id!=int(rules.next_station_id)
