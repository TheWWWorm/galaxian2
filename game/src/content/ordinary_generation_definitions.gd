extends RefCounted
## Original ordinary lounge generation and quotation data.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const VALUES = {"scope":"ordinary_station_contacts_and_offers","early_max_cursor":15,"persistent":{"resource":"resources/data/bin/agents.bin","count":27,"field_count":9,"station_field":1,"system_field":2,"faction_field":3,"male_field":4,"portrait_indicators":[0,5],"portrait_bytes":5},"roster":{"role":6,"duplicate_role":1,"extra_name_bound":3,"price_bound":1300,"price_add":700,"hard_difficulty":1.5,"hard_multiplier":7},"offers":{"kind_count":15,"difficulty_draw_bound":9,"difficulty_maximum":10,"different_destination_kinds":[0,11,14],"faction_destination_kind":13,"major_faction_count":4,"faction_required_system_array":2,"faction_fallback_kinds":[1,4],"courier_quantity":{"multiplier":95.0,"add":5},"passenger_quantity":{"multiplier":18.0,"add":2},"item_quantity":{"kinds":[3,5],"parameters":[116,117],"multiplier":8.0,"add":2},"random_quantity":{"kind":2,"bound":4,"add":2},"collection":{"kind":8,"first_item_id":97,"excluded_item_ids":[115,116,117,131,164,175,217,218],"difficulty_value_index":7,"price_value_index":17,"quantity_bound":15,"quantity_add":5,"reward_multiplier":1.7000000476837158},"reward_multipliers":{"9":1.2000000476837158,"3":2.0,"5":2.0},"bonus_excluded_kinds":[8,12]}}
const SPANS = {"ordinary_offer_selection":[-233980,885],"ordinary_offer_parameters":[-233095,619],"ordinary_offer_reward":[-232476,594],"ordinary_offer_dispatch":[-231350,48],"ordinary_contact_identity":[-234960,95],"ordinary_contact_roster":[-234652,317],"ordinary_contact_population":[-236767,267],"ordinary_contact_unique_role":[-235772,178],"ordinary_persistent_loader":[-675370,696],"ordinary_persistent_constructor":[-720294,434],"ordinary_contact_station":[-719568,10],"ordinary_contact_system":[-719578,10],"ordinary_system_loader":[-673478,1100],"ordinary_system_constructor":[734132,236],"ordinary_system_stations":[735314,10],"ordinary_item_fields":[-84866,140],"ordinary_item_difficulty":[-84660,10],"ordinary_item_price":[-84616,10],"ordinary_roster_hard_predicate":[873106,34],"ordinary_offer_constants":[1557090,32],"ordinary_escort_multiplier":[1545694,4],"ordinary_roster_hard_value":[1545698,4]}

# Native composition.
static func parameters(data: Variant) -> bool:return Equal.equal_value(data,VALUES)

static func available(bindings: RefCounted) -> bool:
	return bindings!=null and parameters(bindings.early_contracts.get("ordinary_generation")) and load("res://src/content/free_flight_definitions.gd").available(bindings)

static func location_supported(bindings: RefCounted,cat: RefCounted,cursor: Variant,station_id: Variant) -> bool:
	if not available(bindings) or cat==null or cat.content_id!=bindings.base_content_id:return false
	var flight: Dictionary=bindings.mido_travel.free_flight
	var numbers=load("res://src/content/opening_definitions.gd")
	if not numbers.integer(cursor,int(flight.campaign_cursor),int(flight.campaign_cursor)) or not numbers.integer(station_id,0,cat.tables.stations.size()-1):return false
	return not load("res://src/content/ordinary_world_definitions.gd").catalogue_location(bindings,cat,station_id).is_empty()
