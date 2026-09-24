extends RefCounted
## Source offer terms only. This capability does not enable or complete missions.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Travel=preload("res://src/content/mido_travel_definitions.gd")
const Contacts=preload("res://src/content/lounge_contact_definitions.gd")
const Delivery=preload("res://src/content/delivery_result_definitions.gd")
const Encounters=preload("res://src/content/contract_encounter_definitions.gd")
const ShipCombat=preload("res://src/content/contract_ship_combat_definitions.gd")
const ShipLifecycle=preload("res://src/content/contract_ship_lifecycle_definitions.gd")
const FlightResults=preload("res://src/content/contract_flight_result_definitions.gd")
const World=preload("res://src/content/contract_world_definitions.gd")
const Lounges=preload("res://src/content/lounge_lifecycle_definitions.gd")
const LoungePresentation=preload("res://src/content/lounge_presentation_definitions.gd")
const Stock=preload("res://src/content/station_generation_definitions.gd")
const BaseStock=preload("res://src/content/base_station_stock_definitions.gd")
const Navigation=preload("res://src/content/base_contract_navigation_definitions.gd")
const Ordinary=preload("res://src/content/ordinary_generation_definitions.gd")
const Junk=preload("res://src/content/contract_junk_definitions.gd")
const VALUES = {"scope":"mido_early_contract_terms","system_id":15,"first_cursor":13,"last_cursor":15,"contact_role":0,"kind_choices":[11,0,7,4,12],"difficulty_draw_bound":2,"difficulty_add":1,"initial_destination_count":4,"delivery_kinds":[0,11],"local_challenge_kind":12,"title_text_base":343,"briefing_text_base":773,"courier":{"kind":0,"quantity_by_difficulty":[14,24],"description_text_base":800,"description_draw_bound":7,"cargo_item_id":116,"capacity_text_id":326},"passenger":{"kind":11,"quantity_by_difficulty":[3,5],"capacity_text_id":327},"reward":{"base":1500,"difficulty_divisor":10.0,"difficulty_multiplier":5500.0,"distance_divisor":1200.0,"junk_kind":7,"junk_multiplier":0.699999988079071,"passenger_multiplier":0.6000000238418579,"passenger_quantity_divisor":5.0,"rank_cubic_multiplier":10,"credit_step":50,"credit_rounding":"truncate_except_exact_half_up"},"bonus":{"excluded_kinds":[12],"divisor":100.0,"faction_axes":[0,0,1,1],"faction_signs":[1,-1,1,-1],"other_factions":0,"minimum":0}}
const SPANS = {"lounge_gate":[440570,53],"early_selector":[-233602,129],"early_choices":[-231370,20],"early_difficulty":[-233228,35],"parameter_dispatch":[-232883,45],"parameter_choices":[-231350,48],"courier_quantity":[-232642,55],"passenger_quantity":[-232587,35],"quantity_constants":[1557090,28],"mido_destination":[-233944,93],"delivery_destination":[-233437,209],"mido_destination_retry":[-237078,81],"same_system_distance":[-658475,31],"reward_base":[-232466,157],"passenger_reward":[-232238,61],"rank_reward":[-232177,54],"bonus_reward":[-232123,127],"credit_quantization":[-231996,91],"reward_constructor":[-231905,79],"parameter_setters":[-231568,32],"reward_one":[1544610,4],"junk_multiplier":[1556918,4],"passenger_multiplier":[1556934,4],"reputation_bonus":[808278,104],"reputation_divisor":[1556926,4],"mission_title":[400596,86],"mission_briefing":[-209115,30],"cargo_description":[-208606,30],"mission_constructor":[398969,178],"mission_quantity":[400520,42],"mission_reward_getter":[400774,10],"mission_bonus_getter":[400814,20],"courier_capacity":[748958,90],"passenger_capacity":[749375,89],"courier_cargo":[743771,111],"passenger_load":[743882,57],"side_mission_owner":[859500,44]}

const MAC_SPANS = {"lounge_gate":[441082,53],"early_selector":[-234622,129],"early_choices":[-232390,20],"early_difficulty":[-234248,35],"parameter_dispatch":[-233903,45],"parameter_choices":[-232370,48],"courier_quantity":[-233662,55],"passenger_quantity":[-233607,35],"quantity_constants":[1532090,28],"mido_destination":[-234964,93],"delivery_destination":[-234457,209],"mido_destination_retry":[-238098,81],"same_system_distance":[-664363,31],"reward_base":[-233486,157],"passenger_reward":[-233258,61],"rank_reward":[-233197,54],"bonus_reward":[-233143,127],"credit_quantization":[-233016,91],"reward_constructor":[-232925,79],"parameter_setters":[-232588,32],"reward_one":[1519594,4],"junk_multiplier":[1531918,4],"passenger_multiplier":[1531934,4],"reputation_bonus":[808910,104],"reputation_divisor":[1531926,4],"mission_title":[401112,86],"mission_briefing":[-210071,30],"cargo_description":[-209562,30],"mission_constructor":[399485,178],"mission_quantity":[401036,42],"mission_reward_getter":[401290,10],"mission_bonus_getter":[401330,20],"courier_capacity":[749590,90],"passenger_capacity":[750007,89],"courier_cargo":[744403,111],"passenger_load":[744514,57],"side_mission_owner":[860132,44]}
const MAC_VALUES = {"scope":"mido_early_contract_terms","system_id":15,"first_cursor":13,"last_cursor":15,"contact_role":0,"kind_choices":[11,0,7,4,12],"difficulty_draw_bound":2,"difficulty_add":1,"initial_destination_count":4,"delivery_kinds":[0,11],"local_challenge_kind":12,"title_text_base":343,"briefing_text_base":775,"courier":{"kind":0,"quantity_by_difficulty":[14,24],"description_text_base":802,"description_draw_bound":7,"cargo_item_id":116,"capacity_text_id":326},"passenger":{"kind":11,"quantity_by_difficulty":[3,5],"capacity_text_id":327},"reward":{"base":1500,"difficulty_divisor":10.0,"difficulty_multiplier":5500.0,"distance_divisor":1200.0,"junk_kind":7,"junk_multiplier":0.699999988079071,"passenger_multiplier":0.6000000238418579,"passenger_quantity_divisor":5.0,"rank_cubic_multiplier":10,"credit_step":50,"credit_rounding":"truncate_except_exact_half_up"},"bonus":{"excluded_kinds":[12],"divisor":100.0,"faction_axes":[0,0,1,1],"faction_signs":[1,-1,1,-1],"other_factions":0,"minimum":0}}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1+int(data.has("acceptance"))+int(data.has("generation"))+int(data.has("delivery_results"))+int(data.has("encounter_construction"))+int(data.has("ship_combat"))+int(data.has("ship_lifecycle"))+int(data.has("flight_results"))+int(data.has("junk_lifecycle"))+int(data.has("world_initialization"))+int(data.has("station_lounges"))+int(data.has("station_generation"))+int(data.has("base_station_stock"))+int(data.has("base_navigation"))+int(data.has("lounge_presentation"))+int(data.has("ordinary_generation")) or not data.get("provenance") is Dictionary:return false
	var expected: Dictionary=MAC_VALUES if data.get("briefing_text_base")==MAC_VALUES.briefing_text_base else VALUES
	var alternate: bool=expected==MAC_VALUES
	for key in expected:
		if not Equal.equal_value(data.get(key),expected[key]):return false
	if data.has("acceptance") and not Equal.equal_value(data.acceptance,MAC_ACCEPTANCE if alternate else ACCEPTANCE):return false
	if data.has("generation") and (not data.has("acceptance") or not Contacts.parameters(data.generation)):return false
	if data.has("delivery_results") and (not data.has("acceptance") or not Delivery.parameters(data.delivery_results)):return false
	if data.has("encounter_construction") and (not data.has("delivery_results") or not Encounters.parameters(data.encounter_construction)):return false
	if data.has("ship_combat") and (not data.has("encounter_construction") or not ShipCombat.parameters(data.ship_combat)):return false
	if data.has("ship_lifecycle") and (not data.has("ship_combat") or not ShipLifecycle.parameters(data.ship_lifecycle)):return false
	if data.has("flight_results") and (not data.has("ship_lifecycle") or not FlightResults.parameters(data.flight_results)):return false
	if data.has("junk_lifecycle") and (not data.has("flight_results") or not Junk.parameters(data.junk_lifecycle)):return false
	if data.has("world_initialization") and (not data.has("junk_lifecycle") or not World.parameters(data.world_initialization)):return false
	if data.has("station_lounges") and (not data.has("world_initialization") or not data.has("generation") or not Lounges.parameters(data.station_lounges)):return false
	if data.has("station_generation") and (not data.has("station_lounges") or not Stock.parameters(data.station_generation)):return false
	if data.has("base_station_stock") and (not data.has("station_generation") or not Equal.equal_value(data.base_station_stock,BaseStock.MAC_VALUES if alternate else BaseStock.VALUES)):return false
	if data.has("base_navigation") and (not data.has("base_station_stock") or not Navigation.parameters(data.base_navigation)):return false
	if data.has("lounge_presentation") and (not data.has("station_lounges") or not LoungePresentation.parameters(data.lounge_presentation)):return false
	if data.has("ordinary_generation") and (not data.has("base_navigation") or not Ordinary.parameters(data.ordinary_generation)):return false
	return true

static func first_generation_cursor(data: Dictionary) -> int:
	return int(data.station_generation.first_cursor) if data.has("station_generation") else int(data.first_cursor)

static func acceptance_parameters(data: Variant) -> bool:
	return parameters(data) and data.has("acceptance")

static func generation_parameters(data: Variant) -> bool:
	return acceptance_parameters(data) and data.has("generation")

static func delivery_parameters(data: Variant) -> bool:
	return acceptance_parameters(data) and data.has("delivery_results")

static func encounter_parameters(data: Variant) -> bool:
	return delivery_parameters(data) and data.has("encounter_construction")

static func ship_combat_parameters(data: Variant) -> bool:
	return encounter_parameters(data) and data.has("ship_combat")

static func ship_lifecycle_parameters(data: Variant) -> bool:
	return ship_combat_parameters(data) and data.has("ship_lifecycle")

static func validate(data: Variant,source_bytes: int,arch: String,arrival: Dictionary,travel: Dictionary) -> String:
	if not data is Dictionary:return "Missing early contract terms"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data) or not Travel.parameters(travel) or not travel.has("return_visit"):return "Unsupported early contract terms"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Early contract terms lack their source anchor"
	var alternate: bool=data.briefing_text_base==MAC_VALUES.briefing_text_base
	var spans: Dictionary=(MAC_SPANS if alternate else SPANS).duplicate(true)
	if data.has("acceptance"):spans.merge(MAC_ACCEPTANCE_SPANS if alternate else ACCEPTANCE_SPANS)
	if data.has("generation"):spans.merge(Contacts.MAC_SPANS if alternate else Contacts.SPANS)
	if data.has("delivery_results"):spans.merge(Delivery.MAC_SPANS if alternate else Delivery.SPANS)
	if data.has("encounter_construction"):
		if not Travel.navigation_available(travel,13):return "Contract construction lacks ordinary navigation"
		spans.merge(Encounters.MAC_SPANS if alternate else Encounters.SPANS)
	if data.has("ship_combat"):spans.merge(ShipCombat.MAC_SPANS if alternate else ShipCombat.SPANS)
	if data.has("ship_lifecycle"):spans.merge(ShipLifecycle.MAC_SPANS if alternate else ShipLifecycle.SPANS)
	if data.has("flight_results"):spans.merge(FlightResults.MAC_SPANS if alternate else FlightResults.SPANS)
	if data.has("junk_lifecycle"):spans.merge(Junk.MAC_SPANS if alternate else Junk.SPANS)
	if data.has("world_initialization"):spans.merge(World.MAC_SPANS if alternate else World.SPANS)
	if data.has("station_lounges"):spans.merge(Lounges.MAC_SPANS if alternate else Lounges.SPANS)
	if data.has("station_generation"):spans.merge(Stock.MAC_SPANS if alternate else Stock.SPANS)
	if data.has("base_station_stock"):spans.merge(BaseStock.MAC_SPANS if alternate else BaseStock.SPANS)
	if data.has("base_navigation"):
		if not travel.has("alioth_arrival"):return "Base contracts lack their supported Alioth arrival"
		spans.merge(Navigation.MAC_SPANS if alternate else Navigation.SPANS)
	if data.has("lounge_presentation"):spans.merge(LoungePresentation.MAC_SPANS if alternate else LoungePresentation.SPANS)
	if data.has("ordinary_generation"):
		if not travel.has("free_flight"):return "Ordinary contacts lack their supported free-flight context"
		spans.merge(Ordinary.MAC_SPANS if alternate else Ordinary.SPANS)
	if data.provenance.size()!=spans.size():return "Invalid early contract provenance"
	for key in spans:
		var span: Variant=data.provenance.get(key);var rule: Array=spans[key]
		if not Fonts.extent(span,"offset","bytes",[rule[1]],source_bytes) or int(span.offset)!=int(origin.offset)+int(rule[0]):return "Invalid early contract extent: "+key
	return ""

const ACCEPTANCE = {"scope":"mido_generated_contract_acceptance","initial_credits":0,"initial_passengers":0,"fee_difficulty":1.5,"fee_divisor":10,"insufficient_credits_text_id":192,"replacement_text_id":851,"cabin_subtype":20,"cabin_places_property":34,"clear_cargo_kinds":[0,3,5],"generated_contact_source_id":-1,"generated_contact_stays_consumed":true}
const ACCEPTANCE_SPANS = {"accept_fee_predicate":[873106,34],"accept_fee_difficulty":[1545698,4],"accept_fee_calculation":[742832,109],"accept_fee_shortfall":[742951,5],"accept_fee_debit":[743350,19],"contract_replacement":[743369,402],"contract_replacement_notice":[750530,146],"cargo_capacity_sum":[731124,20],"installed_capacity_recalculation":[727580,1370],"cabin_capacity_getter":[732332,10],"mission_cargo_flag_setter":[-84714,10],"mission_cargo_flag_getter":[-81574,12],"cargo_merge_by_item_id":[-83740,562],"passenger_count_setter":[859476,10],"generated_contact_identity":[-234748,22],"contact_identity_argument":[-720263,3],"generated_contact_flag":[-720106,16],"generated_contact_predicate":[-719502,14],"contact_consumed_setter":[-718610,14],"accepted_contact_consumed":[747747,26],"accepted_side_mission":[744191,55],"initial_contract_wallet":[880656,11],"initial_passenger_count":[881587,8]}

static func draw_enemy_faction(rules: Dictionary,random: RefCounted,alternate_faction: int) -> int:
	# All selected mission branches consume this draw, including Courier0.
	return int(rules.pirate_actor_kind) if random.next_int(int(rules.enemy_faction_draw_bound))<int(rules.pirate_faction_threshold) else alternate_faction

const MAC_ACCEPTANCE = {"scope":"mido_generated_contract_acceptance","initial_credits":0,"initial_passengers":0,"fee_difficulty":1.5,"fee_divisor":10,"insufficient_credits_text_id":192,"replacement_text_id":853,"cabin_subtype":20,"cabin_places_property":34,"clear_cargo_kinds":[0,3,5],"generated_contact_source_id":-1,"generated_contact_stays_consumed":true}
const MAC_ACCEPTANCE_SPANS = {"accept_fee_predicate":[873738,34],"accept_fee_difficulty":[1520682,4],"accept_fee_calculation":[743464,109],"accept_fee_shortfall":[743583,5],"accept_fee_debit":[743982,19],"contract_replacement":[744001,402],"contract_replacement_notice":[751162,146],"cargo_capacity_sum":[731756,20],"installed_capacity_recalculation":[728204,1370],"cabin_capacity_getter":[732964,10],"mission_cargo_flag_setter":[-84714,10],"mission_cargo_flag_getter":[-81574,12],"cargo_merge_by_item_id":[-83740,562],"passenger_count_setter":[860108,10],"generated_contact_identity":[-235768,22],"contact_identity_argument":[-726159,3],"generated_contact_flag":[-726002,16],"generated_contact_predicate":[-725398,14],"contact_consumed_setter":[-724506,14],"accepted_contact_consumed":[748379,26],"accepted_side_mission":[744823,55],"initial_contract_wallet":[881288,11],"initial_passenger_count":[882219,8]}
