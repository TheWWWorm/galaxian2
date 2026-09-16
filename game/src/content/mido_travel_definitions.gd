extends RefCounted
## Recovered content for the first local journey. Availability of these records
## does not establish full campaign or application support.
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Station=preload("res://src/content/station_entry_definitions.gd")
const Training=preload("res://src/content/combat_training_definitions.gd")
const ControlRules=preload("res://src/content/combat_training_control_definitions.gd")
const WeaponRules=preload("res://src/content/combat_training_weapon_definitions.gd")
const DeathRules=preload("res://src/content/combat_training_destruction_definitions.gd")
const FirstFlight=preload("res://src/content/first_flight_definitions.gd")
const FirstReturn=preload("res://src/content/station_return_definitions.gd")
const VALUES := {"scope":"mido_local_travel","system_id":15,"station_ids":[78,79],"planet_types":[0,11],"conversations":[{"campaign_cursor":9,"station_id":78,"mission_kind":11,"events":[{"speaker_id":17,"text_id":1747,"voice_event_id":453},{"speaker_id":17,"text_id":1748,"voice_event_id":454},{"speaker_id":17,"text_id":1749,"voice_event_id":455},{"speaker_id":2,"text_id":1750,"voice_event_id":456},{"speaker_id":0,"text_id":1751,"voice_event_id":457},{"speaker_id":2,"text_id":1752,"voice_event_id":458},{"speaker_id":0,"text_id":1753,"voice_event_id":459},{"speaker_id":2,"text_id":1754,"voice_event_id":460},{"speaker_id":0,"text_id":1755,"voice_event_id":461},{"speaker_id":2,"text_id":1756,"voice_event_id":462},{"speaker_id":16,"text_id":1757,"voice_event_id":-1}],"acknowledgement_required":true,"next_cursor":10,"next_station_id":79,"next_kind":11,"reward":0,"bonus":0},{"campaign_cursor":10,"station_id":79,"mission_kind":11,"events":[{"speaker_id":3,"text_id":1758,"voice_event_id":190},{"speaker_id":0,"text_id":1759,"voice_event_id":191},{"speaker_id":3,"text_id":1760,"voice_event_id":194},{"speaker_id":0,"text_id":1761,"voice_event_id":195},{"speaker_id":3,"text_id":1762,"voice_event_id":196},{"speaker_id":0,"text_id":1763,"voice_event_id":197},{"speaker_id":3,"text_id":1764,"voice_event_id":198},{"speaker_id":0,"text_id":1765,"voice_event_id":199},{"speaker_id":3,"text_id":1766,"voice_event_id":200},{"speaker_id":0,"text_id":1767,"voice_event_id":201},{"speaker_id":3,"text_id":1768,"voice_event_id":192},{"speaker_id":0,"text_id":1769,"voice_event_id":193}],"acknowledgement_required":true,"next_cursor":11,"next_station_id":76,"next_kind":11,"reward":0,"bonus":0}],"exchange":{"campaign_cursor":9,"find_subtype":19,"replacement_item_id":86,"quantity":1,"slot_selection":"first_empty_in_category","removal_match":"item_id","copy_prototype_price":true},"travel":{"minimum_cursor":10,"excluded_cursor":48,"mission_kind":11,"scanner_subtype":17,"scanner_duration_property":29,"default_acquisition_ms":8000,"acquisition_strict":true,"target_window_divisor":18,"acquisition_sound_id":26,"launch_sound_id":5,"launch_duration_ms":3000,"launch_duration_strict":true,"launch_speed_per_ms":8.0,"source_state":2,"world_type":3,"audio_selector":1,"arrival_keeps_cursor":true},"map":{"scope":"mido_local_system_map","first_cursor":10,"galaxy_cursor":16,"pauses_flight":true,"confirmation_required":true,"selection_starts_autopilot":true,"selection_changes_location":false,"model_base":18180,"material_id":20027,"render_type":6,"texture_id":10145,"seed_multiplier":1000,"angle_units":65536,"first_radius":8000,"radius_step":1600,"radius_draw_bound":5600,"planet_sizes":[320,192,256,256,192,256,192,192,320,256,192,192,320,256,320,256,256,256,320,192,320,256],"size_multiplier":0.000244140625,"ambient":0.20000000298023224,"diffuse":2.0,"visuals":{"background_model_ids":[16850,16851,16852],"orbit_model_id":6779,"orbit_angle_bound":3141,"orbit_angle_divisor":1000.0,"orbit_scale_multiplier":3.0517578125e-05,"parent_scale":0.0078125,"parent_rotation":[-0.39269909262657166,0.39269909262657166,-0.09817477315664291],"sun_mesh_id":6768,"sun_scale":0.004000000189989805,"sun_texture_ids":[10031,10032,10033,10034,10035,10036,10037,10038,10039,10040,10041,10032,10039,10035,10031,11741],"sun_render_type":2,"field_of_view_radians":1.1504000425338745,"camera_distance":500.0,"camera_near":200.0,"camera_far":64000.0},"ui":{"texture_id":10062,"atlas_resources":{"10062":"resources/data/textures/gof2_interface_ipad_1440.aei","10063":"resources/data/textures/gof2_interface2_ipad_large.aei"},"frame_image_id":1162,"selected_image_id":1277,"story_image_id":1108,"current_image_id":1349,"visited_image_id":1186,"footer_image_id":1151,"panel_background_image_id":1150,"panel_corner_image_id":1156,"panel_edge_image_id":1155,"legend":[{"image_id":1108,"text_id":544},{"image_id":1109,"text_id":545},{"image_id":1107,"text_id":536},{"image_id":1186,"text_id":390},{"image_id":1106,"text_id":263}],"faction_image_ids":[1190,1187,1189,1188],"faction_text_base":395,"security_text_base":391,"security_colors":[255,42,0,255,108,0,237,237,0,0,237,0],"button_images":[1116,1115,1117],"pressed_button_images":[1122,1121,1123],"back_image_id":1112,"pressed_back_image_id":1118},"labels":{"title":176,"back":169,"confirm":133,"cancel":134,"target":535,"destination":563,"current":408,"question":410,"key":389}},"entry":{"campaign_cursor":10,"departure_station_id":78,"entry_release_ms":7001,"briefing_events":[],"radio_after_hud":true},"traffic_presentation":{"engine_model_base":18000,"engine_render_type":2,"player_model":false},"planet_size_overrides":[{"planet_type":11,"additional_random_bound":15000,"additional_random_base":35000}],"arrival_flight":{"scope":"mido_kernstal_arrival","campaign_cursor":10,"station_id":79,"system_id":15,"ship_id":0,"world_type":3,"mission_kind":11,"actor_count":0,"weapon_item_sequence":[],"weapon_effect_sequence":[],"restore_player_cache":true,"reset_gamma":true},"player_entry":{"campaign_cursor":10,"ship_id":0,"system_id":15,"cache_reset":-1,"cache_truncates":["shield","gamma"]},"exterior_model_bases":[21000,21800,22000],"collision_sphere_scale":0.5,"reputation":{"scope":"early_mido_lethal_hits","station_id":78,"system_id":15,"primary_faction":3,"initial_axes":[30,0],"override":-1,"axis":1,"minimum":-100,"maximum":100,"lethal_changes":{"8":-1,"3":5},"hardest_difficulty":1.5,"hardest_multiplier":2,"actor_kinds_by_cursor":{"0":[8,8,8],"4":[8],"7":[8,8,8,3]},"location_wrapper_match":false,"special_system":false,"actor_lethal_suppression_flags":[false,false,false],"nonplayer_lethal_changes_reputation":false,"hostile_above":70,"friendly_below":-70},"traffic_control":{"scope":"mido_var_hastra_patrol","campaign_cursor":10,"station_id":78,"system_id":15,"player_ship_id":0,"actor_kind":3,"subtype":0,"supported_ranks":[0,1,2],"initial_actor_mode":0,"initial_active":true,"initial_hostile":false,"friendly":false,"boost_chance":5,"same_kind_targets":false,"player_target_id":-1,"initial_statistics_targeting_blocked":false,"initial_actor_targeting_blocked":false,"initial_mode_defers_flight":true},"traffic_combat":{"scope":"mido_var_hastra_ordinary_combat","campaign_cursor":10,"actor_kind":3,"station_id":78,"credential_subtype":29,"requested_damage_initial":0,"forced_hostile_initial":false,"warning_fraction":0.33000001311302185,"retaliation_fraction":0.5,"faction_fraction":0.6600000262260437,"thresholds_strict":true,"warning_once_per_world":true,"response_once_per_world":true,"station_flag_initial":false,"nonplayer_provokes":false,"hostile_unforced_provokes":false,"requested_damage_bits":32,"radio":{"speaker_id":21,"condition":5,"value":0,"warning_text_ids":[415,416,417],"warning_voice_ids":[645,646,647],"response_text_ids":[418,419,420],"response_voice_ids":[650,651,652],"text_draw_bound":3,"excluded_station_ids":[],"requires_completed_mission":true,"requires_player_display":true,"replaces_pending":true,"retains_active":true,"portrait_family_bound":4,"portrait_zero_family":0,"portrait_other_family":2,"portrait_part_bounds":{"0":[11,11,11,11],"2":[5,5,5,5]},"portrait_at_message_start":true},"weapon":{"item_id":25,"category":0,"kind":0,"catalogue_kind":2,"damage":3,"interval_ms":580,"lifetime_ms":3000,"projectile_capacity":4,"speed_units_per_millisecond":16.0,"model_resource_id":6802,"nonplayer_source":true},"death":{"cargo_model_id":16990,"cargo_model_resource":"resources/data/assets/main/3d/meshes/misc/container_001_midorian.aem","retains_generated_cargo":true,"initial_mode_death":true,"selection_skipped_modes":[3,4],"pirate_kills_delta":0,"nonhostile_remaining_delta":-1}},"departure_traffic":{"scope":"mido_var_hastra_traffic","campaign_cursor":10,"station_id":78,"system_id":15,"ship_id":0,"actor_kind":3,"subtype":0,"world_type":3,"seed_from_unix_seconds":true,"supported_difficulties":[0.5,1.0],"hostile_chance_bound":100,"unused_route_bounds":[100000,0,50000],"unused_route_offsets":[-50000,0,50000],"hostile_faction_bound":100,"hostile_faction_threshold":75,"actor_count_bound":2,"empty_population_fallback":4,"spawn_center_bounds":[20000,20000,30000],"spawn_center_offsets":[-10000,-10000,20000],"hull_draw_bound":37,"hull_candidates":[3,6,19,20,30],"retains_generated_cargo":true,"retains_generated_route":true,"weapon_item_sequence":[0,25],"weapon_effect_sequence":[14600,14606],"weapon_effect_capacity":4,"weapon_effect_random_bound":2,"zero_means_flipped":true}}
const SPANS := {"mode1_counts":[1555258,44],"mode1_offsets":[-694459,60],"mode0_counts":[1554602,44],"ordinary_radio_draw_order":[390696,32],"mode1_speaker":[-692188,57],"mode1_text":[-691916,78],"departure_dialogue":[1546762,88],"arrival_dialogue":[1546850,96],"factory_slots":[871442,8],"exchange_factory":[861087,119],"arrival_factory":[861211,54],"inventory_find":[730168,116],"inventory_remove":[731376,88],"inventory_install":[731910,100],"inventory_equal":[-81946,20],"inventory_clone":[-83770,30],"pending_destination":[818066,26],"map_constructor_wrapper":[808382,18],"map_flight_entry":[350769,157],"map_world_pause":[341289,91],"map_flight_exit":[351007,163],"map_confirm_destination":[836758,170],"map_cancel":[837285,50],"map_initial_view":[811002,74],"map_layout":[814244,1644],"map_planet_sizes":[1589962,88],"map_lighting":[817160,177],"map_material":[1178548,95],"map_material_cases":[1180950,92],"map_presentation_setup":[809986,3767],"map_orbit_presentation":[815888,526],"map_sun_presentation":[816733,427],"map_sun_textures":[1589850,64],"map_faction_icons":[1590074,16],"map_security_colors":[1590122,48],"map_header":[828442,273],"map_legend":[818692,722],"map_projection_tilt_constants":[1589730,20],"map_tilt_y_constant":[1545998,4],"map_camera_distance_constant":[1572198,4],"map_camera_near_constant":[1545982,4],"map_sun_scale_constant":[1582630,4],"map_panel_background":[-62414,20],"map_panel_corners":[-62092,22],"map_panel_border_ids":[-61593,34],"map_panel_type_seven":[-52585,141],"map_panel_type_dispatch":[-52234,44],"destination_autopilot":[137826,368],"autopilot_planet_predicate":[562602,80],"target_selection":[562440,134],"travel_unlock":[342536,61],"scanner_duration":[660703,231],"target_window_size":[661120,48],"target_window":[666639,253],"target_charge":[667047,255],"target_charge_reset":[667547,25],"launch":[600960,154],"launch_clock":[576126,177],"launch_finished":[601176,20],"arrival_transition":[368524,214],"ordinary_world_entry":[335220,77],"arrival_audio_consumer":[337212,42],"ordinary_cache_restore":[335297,335],"departure_cache_reset":[431888,117],"ordinary_gamma_context":[878638,80],"arrival_mission_selection":[856965,661],"story_population_gate":[-42341,312],"story_dispatch_initial":[-43,55],"story_dispatch_middle":[315,21],"story_dispatch_local":[571,41],"early_wormhole_cursor":[858140,16],"ordinary_entry_release":[151038,253],"station_model_choice":[644326,330],"station_mido_layers":[647628,243],"collision_sphere_dispatch":[645917,31],"collision_sphere_arguments":[648286,251],"collision_sphere_scale":[1544586,4],"collision_sphere_constructor":[-709382,46],"collision_sphere_vtable":[2396626,8],"collision_sphere_point":[-709198,128],"collision_sphere_origin":[-708682,54],"collision_sphere_dot":[1060970,80],"target_station_id":[678836,54],"planet_ordinary_size":[843299,151],"planet_type_size":[842473,94],"ordinary_population":[-31880,28546],"traffic_hull_affiliations":[1559482,148],"traffic_hull_selection":[-220778,196],"traffic_spawn_origin":[77999,111],"traffic_weapon_dispatch":[59006,4],"traffic_weapon_mido":[55980,24],"traffic_weapon_rank_damage":[54917,173],"traffic_weapon_rank_choice":[55262,43],"traffic_weapon_context":[56946,566],"traffic_hardest_value":[1545698,4],"traffic_radio_exclusion_initial":[853945,55],"traffic_radio_exclusion_later_dispatch":[871638,4],"traffic_radio_exclusion_later":[864642,210],"traffic_threshold_values":[1544586,12],"traffic_portrait_bounds":[1574410,48],"traffic_radio_voice_dispatch":[-211946,24],"traffic_radio_voice_choices":[-213913,60],"traffic_radio_voice_gate":[-214199,66],"traffic_hostility_update":[611000,445],"traffic_death_attribution":[618447,487],"traffic_cargo_flags":[-81110,39],"traffic_warning_initial":[-45805,9],"traffic_response_reset":[-44048,8],"traffic_warning_reset":[-41711,8],"traffic_health_factory":[78110,433],"traffic_actor_factory":[78713,244],"traffic_model_selector":[-219294,66],"traffic_engine_model":[-217258,164],"traffic_boost_chance":[606598,24],"traffic_fresh_reputation":[882969,25],"reputation_actor_flags":[-81163,31],"reputation_lethal_gates":[540387,135],"reputation_opening_actors":[2702,413],"reputation_full_hold_actor":[315,256],"reputation_training_actors":[571,611],"traffic_normal_hit":[538936,1846],"traffic_statistics_constructor":[534164,980],"traffic_warning":[119652,34],"traffic_faction_response":[113780,214],"traffic_station_response_flag":[851362,10],"traffic_radio_factory":[113994,2616],"traffic_radio_delivery":[682042,70],"traffic_radio_activate":[682154,992],"traffic_radio_update":[683146,630],"traffic_radio_entry_owner":[684362,10],"traffic_radio_constructor":[683790,92],"traffic_portrait_factory":[-86554,158],"traffic_voice_character":[-720294,434],"traffic_station_id":[851352,10],"traffic_forced_hostility":[540800,14],"traffic_forced_friendliness":[535680,14],"traffic_attached_actor":[-77806,14],"traffic_hostile_death":[106510,1044],"traffic_nonhostile_death":[107650,12],"traffic_reseed":[1120906,64],"traffic_default_mission":[399724,290],"traffic_completed_predicate":[400436,14],"traffic_side_mission":[859500,22],"traffic_station_base":[850602,138],"traffic_station_flag":[851372,12],"traffic_special_location":[851384,28],"traffic_station_table1":[852928,68],"traffic_station_table2":[853038,76],"traffic_system_table":[734750,90],"traffic_optional_pilot":[873140,194],"traffic_special_system1":[872962,62],"traffic_special_system2":[873024,82],"traffic_special_system3":[872644,78],"traffic_hardest_predicate":[873106,34],"traffic_system_faction":[734664,10],"traffic_reputation_constructor":[806990,50],"traffic_reputation_hostile":[807440,128],"traffic_reputation_friendly":[807568,128],"traffic_reputation_getter":[876362,10],"reputation_lethal":[807862,184],"reputation_adjust":[808046,184],"reputation_location_wrapper":[858058,26],"reputation_location_match":[853288,22],"reputation_current_system":[872722,14],"voice_1747":[1562474,8],"voice_1748":[1562482,8],"voice_1749":[1562490,8],"voice_1750":[1562498,8],"voice_1751":[1562506,8],"voice_1752":[1562514,8],"voice_1753":[1562522,8],"voice_1754":[1562530,8],"voice_1755":[1562538,8],"voice_1756":[1562546,8],"voice_1758":[1560370,8],"voice_1759":[1560378,8],"voice_1760":[1560402,8],"voice_1761":[1560410,8],"voice_1762":[1560418,8],"voice_1763":[1560426,8],"voice_1764":[1560434,8],"voice_1765":[1560442,8],"voice_1766":[1560450,8],"voice_1767":[1560458,8],"voice_1768":[1560386,8],"voice_1769":[1560394,8]}

const CONTINUATION = {"scope":"mido_yrdal_visit","campaign_cursor":11,"from_station_id":79,"station_id":76,"system_id":15,"planet_type":10,"ship_id":0,"arrival_actor_count":0,"entry_release_ms":7001,"briefing_events":[],"npc_weapon_interval_ms":578,"weapon_groups":["patrol","travel"],"next_cursor":12,"next_station_id":79,"next_kind":11,"events":[{"speaker_id":0,"text_id":1771,"voice_event_id":202},{"speaker_id":0,"text_id":1772,"voice_event_id":203},{"speaker_id":4,"text_id":1773,"voice_event_id":207},{"speaker_id":0,"text_id":1774,"voice_event_id":208},{"speaker_id":4,"text_id":1775,"voice_event_id":209},{"speaker_id":0,"text_id":1776,"voice_event_id":210},{"speaker_id":4,"text_id":1777,"voice_event_id":211},{"speaker_id":0,"text_id":1778,"voice_event_id":212},{"speaker_id":4,"text_id":1779,"voice_event_id":213},{"speaker_id":0,"text_id":1780,"voice_event_id":214},{"speaker_id":0,"text_id":1781,"voice_event_id":204},{"speaker_id":4,"text_id":1782,"voice_event_id":205},{"speaker_id":0,"text_id":1783,"voice_event_id":206}]}
const CONTINUATION_SPANS = {"continuation_radio_dispatch":[81782,54],"continuation_radio_slot":[104530,4],"continuation_radio_empty":[104126,18],"yrdal_dialogue":[1546946,104],"yrdal_voices":[1560466,104],"yrdal_completion":[861265,38],"ambient_weapon_membership":[55113,387],"ambient_weapon_interval":[57315,107],"ambient_cursor_getter":[858156,12],"small_ship_weapon_flag":[607341,9],"base_weapon_flag":[-81174,4]}

const RETURN_VISIT = {"scope":"mido_kernstal_return_visit","campaign_cursor":12,"from_station_id":76,"station_id":79,"system_id":15,"planet_type":11,"ship_id":0,"arrival_actor_count":0,"entry_release_ms":7001,"briefing_events":[],"npc_weapon_interval_ms":576,"weapon_groups":["patrol","travel"],"next_cursor":13,"next_station_id":0,"next_kind":150,"contract_gate":{"initial_completed_count":0,"additional_completions":4,"comparison":"at_least"},"events":[{"speaker_id":3,"text_id":1784,"voice_event_id":215},{"speaker_id":0,"text_id":1785,"voice_event_id":216},{"speaker_id":3,"text_id":1786,"voice_event_id":217},{"speaker_id":0,"text_id":1787,"voice_event_id":218},{"speaker_id":3,"text_id":1788,"voice_event_id":219},{"speaker_id":0,"text_id":1789,"voice_event_id":220},{"speaker_id":3,"text_id":1790,"voice_event_id":221},{"speaker_id":16,"text_id":1791,"voice_event_id":-1}]}
const RETURN_SPANS = {"return_radio_slot":[104534,4],"return_dialogue":[1547050,64],"return_voices":[1560570,56],"return_completion":[861305,75],"contract_threshold_setter":[400562,24],"contract_gate_dispatch":[874940,27],"contract_gate_slot":[875234,4],"contract_gate_counter":[873767,12],"contract_gate_compare":[874658,21],"contract_gate_complete":[875180,18],"contract_counter_initial":[880689,11],"contract_counter_increment":[859750,12],"contract_story_exclusion":[386937,42],"contract_story_predicate":[400856,16]}

const CONTRACT_NAVIGATION = {"scope":"mido_contract_navigation","campaign_cursor":13,"station_ids":[75,76,77,78,79],"planet_types":[4,10,18,0,11],"npc_weapon_interval_ms":574}
const NAVIGATION_SPANS = {"contract_navigation_map_flight_entry":[350769,157],"contract_navigation_map_confirm_destination":[836758,170],"contract_navigation_autopilot_planet_predicate":[562602,80],"contract_navigation_arrival_mission_selection":[856965,661],"contract_navigation_planet_ordinary_size":[843299,151],"contract_navigation_planet_type_size":[842473,94],"contract_navigation_departure_cache_reset":[431888,117],"contract_navigation_weapon_interval":[57315,107]}

const Transit=preload("res://src/content/convoy_transit_definitions.gd")
const ContractStory=preload("res://src/content/lounge_story_definitions.gd")
const ConvoyCapture=preload("res://src/content/convoy_capture_definitions.gd")
const ConvoyLifecycle=preload("res://src/content/convoy_lifecycle_definitions.gd")
const ConvoyEffects=preload("res://src/content/convoy_effect_definitions.gd")
const Attack=preload("res://src/content/alioth_attack_definitions.gd")
const AliothReturn=preload("res://src/content/alioth_return_definitions.gd")
const AliothFlight=preload("res://src/content/alioth_flight_definitions.gd")
const AliothLife=preload("res://src/content/alioth_lifecycle_definitions.gd")
const Alioth=preload("res://src/content/alioth_arrival_definitions.gd")
const ConvoyShip=preload("res://src/content/convoy_ship_definitions.gd")
const FreeNavigation=preload("res://src/content/free_navigation_definitions.gd")
const FreePopulation=preload("res://src/content/free_population_definitions.gd")
const FreeTraffic=preload("res://src/content/free_traffic_definitions.gd")
const FreeLifecycle=preload("res://src/content/free_lifecycle_definitions.gd")
const FreeFlight=preload("res://src/content/free_flight_definitions.gd")
const FreeArrival=preload("res://src/content/free_arrival_definitions.gd")
const LocalArrivalEnvironment=preload("res://src/content/local_arrival_environment_definitions.gd")
const Fitting=preload("res://src/content/ordinary_fitting_definitions.gd")
const OrdinaryContracts=preload("res://src/content/ordinary_contracts_definitions.gd")
const EMPBombs=preload("res://src/content/emp_bombs_definitions.gd")
const KappaLife=preload("res://src/content/kappa_lifecycle_definitions.gd")
const KappaFighters=preload("res://src/content/kappa_fighters_definitions.gd")
const KappaRescue=preload("res://src/content/kappa_rescue_definitions.gd")
const KappaPreparation=preload("res://src/content/kappa_preparation_definitions.gd")
const SuttnarVisit=preload("res://src/content/suttnar_visit_definitions.gd")
const Shopping=preload("res://src/content/ordinary_shopping_definitions.gd")
const GateArrival=preload("res://src/content/gate_arrival_definitions.gd")
const GateTransit=preload("res://src/content/gate_transit_definitions.gd")
const Worlds=preload("res://src/content/ordinary_world_definitions.gd")
const GateEnvironment=preload("res://src/content/gate_environment_definitions.gd")

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or data.size()!=VALUES.size()+1+int(data.has("continuation"))+int(data.has("return_visit"))+int(data.has("contract_navigation"))+int(data.has("contract_completion"))+int(data.has("convoy_capture"))+int(data.has("convoy_ship"))+int(data.has("convoy_lifecycle"))+int(data.has("convoy_effects"))+int(data.has("alioth_arrival"))+int(data.has("convoy_transit"))+int(data.has("alioth_attack"))+int(data.has("alioth_lifecycle"))+int(data.has("alioth_flight"))+int(data.has("alioth_return"))+int(data.has("free_navigation"))+int(data.has("free_population"))+int(data.has("free_traffic"))+int(data.has("free_lifecycle"))+int(data.has("free_flight"))+int(data.has("free_arrival"))+int(data.has("gate_environment"))+int(data.has("local_arrival_environment"))+int(data.has("gate_transit"))+int(data.has("ordinary_worlds"))+int(data.has("gate_arrival"))+int(data.has("ordinary_shopping"))+int(data.has("ordinary_fitting"))+int(data.has("ordinary_contracts"))+int(data.has("suttnar_visit"))+int(data.has("kappa_preparation"))+int(data.has("emp_bombs"))+int(data.has("kappa_rescue"))+int(data.has("kappa_fighters"))+int(data.has("kappa_lifecycle")) or not data.get("provenance") is Dictionary:return false
	if data.has("continuation") and not Equal.equal_value(data.continuation,CONTINUATION):return false
	if data.has("return_visit") and (not data.has("continuation") or not Equal.equal_value(data.return_visit,RETURN_VISIT)):return false
	if data.has("contract_navigation") and (not data.has("return_visit") or not Equal.equal_value(data.contract_navigation,CONTRACT_NAVIGATION)):return false
	if data.has("contract_completion") and (not data.has("contract_navigation") or not ContractStory.parameters(data.contract_completion)):return false
	if data.has("convoy_capture") and (not data.has("contract_completion") or not ConvoyCapture.parameters(data.convoy_capture)):return false
	if data.has("convoy_ship") and (not data.has("convoy_capture") or not ConvoyShip.parameters(data.convoy_ship)):return false
	if data.has("convoy_lifecycle") and (not data.has("convoy_ship") or not ConvoyLifecycle.parameters(data.convoy_lifecycle)):return false
	if data.has("convoy_effects") and (not data.has("convoy_lifecycle") or not ConvoyEffects.parameters(data.convoy_effects)):return false
	if data.has("alioth_arrival") and (not data.has("convoy_effects") or not Alioth.parameters(data.alioth_arrival)):return false
	if data.has("convoy_transit") and (not data.has("alioth_arrival") or not Transit.parameters(data.convoy_transit)):return false
	if data.has("alioth_attack") and (not data.has("convoy_transit") or not Attack.parameters(data.alioth_attack)):return false
	if data.has("alioth_lifecycle") and (not data.has("alioth_attack") or not AliothLife.parameters(data.alioth_lifecycle)):return false
	if data.has("alioth_flight") and (not data.has("alioth_lifecycle") or not AliothFlight.parameters(data.alioth_flight)):return false
	if data.has("alioth_return") and (not data.has("alioth_flight") or not AliothReturn.parameters(data.alioth_return)):return false
	if data.has("free_navigation") and (not data.has("alioth_return") or not FreeNavigation.parameters(data.free_navigation)):return false
	if data.has("free_population") and (not data.has("free_navigation") or not FreePopulation.parameters(data.free_population)):return false
	if data.has("free_traffic") and (not data.has("free_population") or not FreeTraffic.parameters(data.free_traffic)):return false
	if data.has("free_lifecycle") and (not data.has("free_traffic") or not FreeLifecycle.parameters(data.free_lifecycle)):return false
	if data.has("free_flight") and (not data.has("free_lifecycle") or not FreeFlight.parameters(data.free_flight)):return false
	if data.has("free_arrival") and (not data.has("free_flight") or not FreeArrival.parameters(data.free_arrival)):return false
	if data.has("gate_environment") and (not data.has("free_arrival") or not GateEnvironment.parameters(data.gate_environment)):return false
	if data.has("local_arrival_environment") and (not data.has("gate_environment") or not LocalArrivalEnvironment.parameters(data.local_arrival_environment)):return false
	if data.has("gate_transit") and (not data.has("local_arrival_environment") or not GateTransit.parameters(data.gate_transit)):return false
	if data.has("ordinary_worlds") and (not data.has("local_arrival_environment") or not Worlds.parameters(data.ordinary_worlds)):return false
	if data.has("gate_arrival") and (not data.has("gate_transit") or not data.has("ordinary_worlds") or not GateArrival.parameters(data.gate_arrival)):return false
	if data.has("ordinary_fitting") and (not data.has("ordinary_shopping") or not Fitting.parameters(data.ordinary_fitting)):return false
	if data.has("ordinary_contracts") and (not data.has("ordinary_fitting") or not OrdinaryContracts.parameters(data.ordinary_contracts)):return false
	if data.has("kappa_lifecycle") and (not data.has("kappa_fighters") or not KappaLife.parameters(data.kappa_lifecycle)):return false
	if data.has("kappa_fighters") and (not data.has("kappa_rescue") or not KappaFighters.parameters(data.kappa_fighters)):return false
	if data.has("kappa_rescue") and (not data.has("emp_bombs") or not KappaRescue.parameters(data.kappa_rescue)):return false
	if data.has("emp_bombs") and (not data.has("kappa_preparation") or not EMPBombs.parameters(data.emp_bombs)):return false
	if data.has("kappa_preparation") and (not data.has("suttnar_visit") or not KappaPreparation.parameters(data.kappa_preparation)):return false
	if data.has("suttnar_visit") and (not data.has("ordinary_contracts") or not SuttnarVisit.parameters(data.suttnar_visit)):return false
	if data.has("ordinary_shopping") and (not data.has("ordinary_worlds") or not Shopping.parameters(data.ordinary_shopping)):return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	return true

static func validate(data: Variant, source_bytes: int, arch: String, arrival: Dictionary, station: Dictionary, training: Dictionary) -> String:
	if not data is Dictionary:return "Missing local travel declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data) or not Station.parameters(station) or not Training.parameters(training):return "Unsupported local travel declarations"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Local travel lacks its source anchor"
	var spans:=SPANS.duplicate(true)
	if data.has("continuation"):spans.merge(CONTINUATION_SPANS)
	if data.has("return_visit"):spans.merge(RETURN_SPANS)
	if data.has("contract_navigation"):spans.merge(NAVIGATION_SPANS)
	if data.has("contract_completion"):spans.merge(ContractStory.SPANS)
	if data.has("convoy_capture"):spans.merge(ConvoyCapture.SPANS)
	if data.has("convoy_ship"):spans.merge(ConvoyShip.SPANS)
	if data.has("convoy_lifecycle"):spans.merge(ConvoyLifecycle.SPANS)
	if data.has("convoy_effects"):spans.merge(ConvoyEffects.SPANS)
	if data.has("alioth_arrival"):spans.merge(Alioth.SPANS)
	if data.has("convoy_transit"):spans.merge(Transit.SPANS)
	if data.has("alioth_attack"):spans.merge(Attack.SPANS)
	if data.has("alioth_lifecycle"):spans.merge(AliothLife.SPANS)
	if data.has("alioth_flight"):spans.merge(AliothFlight.SPANS)
	if data.has("alioth_return"):spans.merge(AliothReturn.SPANS)
	if data.has("free_navigation"):spans.merge(FreeNavigation.SPANS)
	if data.has("free_population"):spans.merge(FreePopulation.SPANS)
	if data.has("free_traffic"):spans.merge(FreeTraffic.SPANS)
	if data.has("free_lifecycle"):spans.merge(FreeLifecycle.SPANS)
	if data.has("free_flight"):spans.merge(FreeFlight.SPANS)
	if data.has("free_arrival"):spans.merge(FreeArrival.SPANS)
	if data.has("gate_environment"):spans.merge(GateEnvironment.SPANS)
	if data.has("local_arrival_environment"):spans.merge(LocalArrivalEnvironment.SPANS)
	if data.has("gate_transit"):spans.merge(GateTransit.SPANS)
	if data.has("ordinary_worlds"):spans.merge(Worlds.SPANS)
	if data.has("gate_arrival"):spans.merge(GateArrival.SPANS)
	if data.has("ordinary_shopping"):spans.merge(Shopping.SPANS)
	if data.has("ordinary_fitting"):spans.merge(Fitting.SPANS)
	if data.has("ordinary_contracts"):spans.merge(OrdinaryContracts.SPANS)
	if data.has("suttnar_visit"):spans.merge(SuttnarVisit.SPANS)
	if data.has("kappa_preparation"):spans.merge(KappaPreparation.SPANS)
	if data.has("emp_bombs"):spans.merge(EMPBombs.SPANS)
	if data.has("kappa_rescue"):spans.merge(KappaRescue.SPANS)
	if data.has("kappa_fighters"):spans.merge(KappaFighters.SPANS)
	if data.has("kappa_lifecycle"):spans.merge(KappaLife.SPANS)
	if data.provenance.size()!=spans.size():return "Invalid local travel provenance"
	for key in spans:
		var span: Variant=data.provenance.get(key);var rule: Array=spans[key]
		if not Fonts.extent(span,"offset","bytes",[rule[1]],source_bytes) or int(span.offset)!=int(origin.offset)+int(rule[0]):return "Invalid local travel extent: "+key
	return ""

static func location_supported(data: Dictionary, station_id: int, system_id: int, planet_type: int) -> bool:
	if not parameters(data):return false
	var ordinary:=Worlds.location(data,station_id) if free_local_navigation(data,18) else {}
	if not ordinary.is_empty():return system_id==ordinary.system_id and planet_type==ordinary.planet_type
	if data.has("alioth_arrival") and station_id==int(data.alioth_arrival.station_id):
		return system_id==int(data.alioth_arrival.system_id) and planet_type==int(data.alioth_arrival.planet_type)
	if system_id!=int(data.system_id):return false
	if data.has("contract_navigation"):
		var index: int=data.contract_navigation.station_ids.map(func(id):return int(id)).find(station_id)
		if index>=0:return planet_type==int(data.contract_navigation.planet_types[index])
	if data.has("continuation") and station_id==int(data.continuation.station_id):return planet_type==int(data.continuation.planet_type)
	for index in data.station_ids.size():
		if int(data.station_ids[index])==station_id:return int(data.planet_types[index])==planet_type
	return false

static func navigation_available(data: Dictionary, cursor: int) -> bool:
	return parameters(data) and data.has("contract_navigation") and Transit.supports(data,cursor)

static func free_local_navigation(data: Dictionary,cursor: int) -> bool:
	return parameters(data) and data.has("local_arrival_environment") and load("res://src/content/free_campaign_definitions.gd").supported(data,cursor)

static func navigation_system(data: Dictionary,cursor: int,station_id: int=-1) -> int:
	if free_local_navigation(data,cursor):
		return int(Worlds.location(data,station_id).get("system_id",-1)) if station_id>=0 else int(data.free_flight.system_id)
	return int(data.get("system_id",-1))

static func navigation_stations(data: Dictionary, cursor: int, station_id: int) -> Array:
	if navigation_available(data,cursor) or free_local_navigation(data,cursor):
		var stations: Array=(Worlds.location(data,station_id).get("station_ids",[]) if free_local_navigation(data,cursor) else data.contract_navigation.station_ids).map(func(id):return int(id))
		return stations if stations.has(station_id) else []
	var trip:=journey(data,cursor)
	if trip.is_empty() or station_id!=int(trip.from_station_id):return []
	return [int(trip.from_station_id),int(trip.station_id)]

static func route(data: Dictionary, cursor: int, from_station_id: int, station_id: int) -> Dictionary:
	var stations:=navigation_stations(data,cursor,from_station_id)
	if stations.is_empty() or not stations.has(station_id) or from_station_id==station_id:return {}
	return {"campaign_cursor":cursor,"from_station_id":from_station_id,"station_id":station_id,"system_id":navigation_system(data,cursor,from_station_id)}

static func navigation_mission(data: Dictionary, cursor: int, mission: Dictionary) -> bool:
	if free_local_navigation(data,cursor):
		return mission==load("res://src/content/free_campaign_definitions.gd").mission(data,cursor)
	if cursor==14 and navigation_available(data,cursor):return mission==Transit.mission(data)
	if navigation_available(data,cursor):
		var target: Variant=mission.get("completed_contract_target")
		if not target is int or target<int(data.return_visit.contract_gate.additional_completions) or target>2147483647:return false
		return mission=={"kind":int(data.return_visit.next_kind),"station_id":int(data.return_visit.next_station_id),"reward":0,"bonus":0,"source_parameter":0,"completed_contract_target":target}
	var trip:=journey(data,cursor)
	return not trip.is_empty() and mission=={"kind":int(data.travel.mission_kind),"station_id":int(trip.station_id),"reward":0,"bonus":0,"source_parameter":0}

static func flight(bindings: RefCounted, station_id: int, cursor: int=10) -> Dictionary:
	if bindings==null or not parameters(bindings.mido_travel) or not FirstFlight.parameters(bindings.first_flight):return {}
	var trip:=journey(bindings.mido_travel,cursor)
	if trip.is_empty() or station_id not in [int(trip.from_station_id),int(trip.station_id)]:return {}
	var departure:=station_id==int(trip.from_station_id)
	var data: Dictionary=(bindings.mido_travel.departure_traffic if departure else bindings.mido_travel.arrival_flight).duplicate(true)
	if cursor in [11,12]:
		if bindings.ambient_lifecycle.get("recycling",{}).is_empty():return {}
		data.campaign_cursor=cursor;data.station_id=station_id
		data.scope=("mido_kernstal_ambient_flight" if cursor==11 else "mido_yrdal_ambient_flight") if departure else ("mido_yrdal_arrival" if cursor==11 else "mido_kernstal_return_arrival")
		if departure:data.ambient=true
	var result: Dictionary=bindings.first_flight.duplicate(true)
	result.merge(data,true)
	# The ordinary departure population samples its own count at construction.
	if departure:result.erase("actor_count")
	return result

static func journey(data: Dictionary, cursor: int) -> Dictionary:
	if not parameters(data):return {}
	if cursor==11:return data.get("continuation",{}).duplicate(true)
	if cursor==12:return data.get("return_visit",{}).duplicate(true)
	if cursor!=10:return {}
	return {"campaign_cursor":10,"from_station_id":int(data.station_ids[0]),"station_id":int(data.station_ids[1]),"system_id":int(data.system_id),"ship_id":int(data.player_entry.ship_id)}

static func valid_response_flags(data: Dictionary, flags: Variant, cursor: int, arrived:=false) -> bool:
	if journey(data,cursor).is_empty() or not flags is Dictionary:return false
	var stations: Array=[78] if cursor==10 else [78,79] if cursor==11 else [78,79,76]
	var destination:=int(journey(data,cursor).station_id)
	if arrived and not stations.has(destination):stations.append(destination)
	if flags.size()!=stations.size():return false
	for station in stations:
		if not flags.get(station) is bool:return false
	return true

static func player_entry(data: Dictionary, station_id: int, cursor: int=10) -> Dictionary:
	var trip:=journey(data,cursor)
	if parameters(data) and cursor==14 and data.has("convoy_lifecycle") and not Transit.available(data):
		if station_id!=int(data.convoy_capture.station_id):return {}
	elif navigation_available(data,cursor):
		if navigation_stations(data,cursor,station_id).is_empty():return {}
	elif trip.is_empty() or station_id not in [int(trip.from_station_id),int(trip.station_id)]:return {}
	var result: Dictionary=data.player_entry.duplicate(true)
	result.station_id=station_id;result.campaign_cursor=cursor
	return result

static func ordinary_weapon(data: Dictionary, cursor: int) -> Dictionary:
	if not parameters(data) or (cursor not in [10,11,12] and not navigation_available(data,cursor)):return {}
	var result: Dictionary=data.traffic_combat.weapon.duplicate(true)
	if navigation_available(data,cursor):result.interval_ms=int(data.convoy_transit.npc_weapon_interval_ms) if cursor==14 else int(data.contract_navigation.npc_weapon_interval_ms)
	# Reader131's detached mixed component retained the preceding cursor's
	# interval. The next visit declaration supplies its source interval.
	if cursor==12 or (cursor==11 and data.has("continuation")):
		var trip:=journey(data,cursor)
		if trip.is_empty():return {}
		result.interval_ms=int(trip.npc_weapon_interval_ms)
	return result

static func station_return_overrides(cursor: int=10) -> Dictionary:
	if cursor not in [10,11,12]:return {}
	var visit: Dictionary=RETURN_VISIT if cursor==12 else CONTINUATION if cursor==11 else VALUES.conversations[1]
	var result:={"scope":visit.scope if cursor==12 else "mido_yrdal_station_visit" if cursor==11 else "mido_kernstal_station_visit","station_id":int(visit.station_id),"departing_cursor":int(visit.campaign_cursor),
		"campaign_cursor":int(visit.campaign_cursor),"minimum_delivered_cargo":0,"local_visit":true,
		"clear_cargo_after_acknowledgement":false,"cursor_after_acknowledgement":int(visit.next_cursor),
		"next_station_id":int(visit.next_station_id),"next_mission_kind":int(visit.next_kind),"next_mission_parameter":0,
		"events":visit.events.duplicate(true)}
	if cursor==12:result.contract_gate=visit.contract_gate.duplicate(true)
	return result

static func station_return(bindings: RefCounted, cursor: int=10) -> Dictionary:
	if bindings==null or not parameters(bindings.mido_travel) or not FirstReturn.parameters(bindings.station_return):return {}
	var result: Dictionary=bindings.station_return.duplicate(true)
	if journey(bindings.mido_travel,cursor).is_empty():return {}
	result.merge(station_return_overrides(cursor),true)
	return result

static func station_return_parameters(rules: Dictionary) -> bool:
	if not rules.get("campaign_cursor") is int:return false
	var changes:=station_return_overrides(rules.campaign_cursor)
	if changes.is_empty():return false
	for key in changes:
		if not Equal.equal_value(rules.get(key),changes[key]):return false
	var original:=rules.duplicate(true)
	for key in changes:
		if FirstReturn.VALUES.has(key):original[key]=FirstReturn.VALUES[key]
		else:original.erase(key)
	return FirstReturn.parameters(original)

static func patrol(bindings: RefCounted, world: Dictionary, rank: Variant, difficulty: Variant) -> Dictionary:
	if bindings==null or not parameters(bindings.mido_travel) or not ControlRules.parameters(bindings.combat_training_control):return {}
	var data: Dictionary=bindings.mido_travel.traffic_control
	var traffic: Dictionary=bindings.mido_travel.departure_traffic
	if not rank is int or not data.supported_ranks.any(func(value):return int(value)==rank) or (not difficulty is float and not difficulty is int) or not traffic.supported_difficulties.any(func(value):return float(value)==float(difficulty)):return {}
	for key in ["base_content_id","binding_id"]:
		if world.get(key)!=bindings.get(key):return {}
	var construction: Dictionary=world.get("npc_construction",{})
	if world.get("campaign_cursor")!=data.campaign_cursor or world.get("station_id")!=data.station_id or construction.get("campaign_cursor")!=data.campaign_cursor:return {}
	var actors: Variant=construction.get("actors")
	if not actors is Array or actors.size() not in [1,4] or construction.get("population",{}).get("actor_count")!=actors.size():return {}
	var result: Dictionary=bindings.combat_training_control.duplicate(true)
	result.merge(data,true)
	result.actor_count=actors.size();result.actor_kinds=[];result.hull_catalogue_ids=[]
	result.target_memberships=[];result.player_weapon_targets=[]
	for id in actors.size():
		var actor: Variant=actors[id]
		if not actor is Dictionary or actor.get("actor_id")!=id or actor.get("actor_kind")!=data.actor_kind or actor.get("subtype")!=data.subtype or not traffic.hull_candidates.any(func(value):return int(value)==actor.get("hull_catalogue_id")):return {}
		result.actor_kinds.append(int(actor.actor_kind));result.hull_catalogue_ids.append(int(actor.hull_catalogue_id))
		result.target_memberships.append([int(data.player_target_id)]);result.player_weapon_targets.append(id)
	return result

static func population(bindings: RefCounted, world: Dictionary, rank: Variant, difficulty: Variant) -> Dictionary:
	if bindings==null or not world.get("campaign_cursor") is int:return {}
	var cursor: int=world.campaign_cursor
	if navigation_available(bindings.mido_travel,cursor):return load("res://src/content/contract_world_definitions.gd").empty_population(bindings,world,rank,difficulty)
	var trip:=journey(bindings.mido_travel,cursor)
	if trip.is_empty():return {}
	if world.get("station_id")!=int(trip.station_id):return patrol(bindings,world,rank,difficulty)
	if flight(bindings,int(trip.station_id),cursor).is_empty() or not ControlRules.parameters(bindings.combat_training_control):return {}
	if not rank is int or rank<0 or rank>=bindings.opening_handoff.rank_thresholds.size():return {}
	if (not difficulty is int and not difficulty is float) or not bindings.mido_travel.departure_traffic.supported_difficulties.any(func(value):return float(value)==float(difficulty)):return {}
	for key in ["base_content_id","binding_id"]:
		if world.get(key)!=bindings.get(key):return {}
	if world.get("npc_construction",{}).get("actors")!=[] or world.get("weapon_effects")!=[]:return {}
	if not world.get("input_random_state") is Dictionary or world.get("random_state")!=world.input_random_state or world.npc_construction.get("random_state")!=world.random_state:return {}
	var result: Dictionary=bindings.combat_training_control.duplicate(true)
	result.merge({"scope":"mido_kernstal_empty_population" if cursor==10 else "mido_yrdal_empty_population","campaign_cursor":cursor,"station_id":int(trip.station_id),"actor_count":0,
		"actor_kinds":[],"hull_catalogue_ids":[],"target_memberships":[],"player_weapon_targets":[],
		"supported_ranks":range(bindings.opening_handoff.rank_thresholds.size())},true)
	return result

static func combat_population(bindings: RefCounted, combat: Dictionary) -> bool:
	if bindings==null or not parameters(bindings.mido_travel) or not combat.get("campaign_cursor") is int:return false
	if navigation_available(bindings.mido_travel,combat.campaign_cursor):
		return bindings.early_contracts.has("world_initialization") and combat.get("actors")==[] and combat.get("base_content_id")==bindings.base_content_id and combat.get("binding_id")==bindings.binding_id and navigation_stations(bindings.mido_travel,combat.campaign_cursor,int(combat.get("provocation",{}).get("station_id",-1))).size()>0
	var trip:=journey(bindings.mido_travel,combat.campaign_cursor)
	if trip.is_empty():return false
	for key in ["base_content_id","binding_id"]:
		if combat.get(key)!=bindings.get(key):return false
	var actors: Variant=combat.get("actors")
	var station: Variant=combat.get("provocation",{}).get("station_id")
	if not actors is Array:return false
	if station==int(trip.station_id):return actors.is_empty()
	if combat.campaign_cursor!=10 or station!=78 or actors.size() not in [1,4]:return false
	for id in actors.size():
		var actor: Variant=actors[id]
		if not actor is Dictionary or actor.get("actor_id")!=id or actor.get("actor_kind")!=3 or not bindings.mido_travel.departure_traffic.hull_candidates.any(func(value):return int(value)==actor.get("hull_catalogue_id")):return false
	return true

static func weapons(bindings: RefCounted, world: Dictionary, rank: Variant, difficulty: Variant) -> Dictionary:
	var data:=population(bindings,world,rank,difficulty)
	if data.is_empty() or not WeaponRules.parameters(bindings.combat_training_weapons):return {}
	var result: Dictionary=bindings.combat_training_weapons.duplicate(true)
	result.scope="mido_var_hastra_ordinary_weapons";result.campaign_cursor=int(data.campaign_cursor)
	if int(data.actor_count)==0:result.scope="mido_kernstal_empty_weapons" if int(data.campaign_cursor)==10 else "mido_yrdal_empty_weapons";result.station_id=int(data.station_id)
	result.rank_min=int(data.supported_ranks[0]);result.rank_max=int(data.supported_ranks[-1])
	result.actor_count=int(data.actor_count);result.target_memberships=data.target_memberships.duplicate(true);result.npc_weapons=[]
	for id in int(data.actor_count):
		var row: Dictionary=bindings.mido_travel.traffic_combat.weapon.duplicate(true)
		row.actor_id=id;row.actor_kind=int(data.actor_kind);row.hull_catalogue_id=data.hull_catalogue_ids[id]
		result.npc_weapons.append(row)
	return result

static func npc_hit(data: Dictionary, weapon: Dictionary) -> bool:
	if [data.get("scope"),data.get("campaign_cursor")] not in [["mido_var_hastra_ordinary_weapons",10],["mido_ambient_ordinary_weapons",11],["mido_ambient_ordinary_weapons",12],["mido_ambient_ordinary_weapons",13],["mido_ambient_ordinary_weapons",14]] or weapon.get("nonplayer_source")!=true:return false
	for key in ["item_id","category","kind","damage"]:
		if not weapon.get(key) is int or weapon[key]!=int(VALUES.traffic_combat.weapon[key]):return false
	return true

static func destruction(bindings: RefCounted, world: Dictionary, rank: Variant, difficulty: Variant) -> Dictionary:
	var data:=population(bindings,world,rank,difficulty)
	if data.is_empty() or not DeathRules.parameters(bindings.combat_training_destruction):return {}
	var result: Dictionary=bindings.mido_travel.traffic_combat.death.duplicate(true)
	result.campaign_cursor=int(data.campaign_cursor);result.actor_count=int(data.actor_count)
	if int(data.actor_count)==0:result.scope="mido_kernstal_empty_death" if int(data.campaign_cursor)==10 else "mido_yrdal_empty_death";result.station_id=int(data.station_id)
	result.cargo=bindings.combat_training_destruction.cargo.duplicate(true);result.actors=[]
	for id in int(data.actor_count):
		result.actors.append({"actor_id":id,"actor_kind":int(data.actor_kind),"hull_catalogue_id":data.hull_catalogue_ids[id],"subtype":int(data.subtype),
			"cargo_model_id":int(result.cargo_model_id),"cargo_model_resource":result.cargo_model_resource})
	return result

static func destruction_parameters(bindings: RefCounted, data: Dictionary) -> bool:
	if bindings==null or not parameters(bindings.mido_travel) or not DeathRules.parameters(bindings.combat_training_destruction):return false
	var count: Variant=data.get("actor_count")
	var actors: Variant=data.get("actors")
	if not count is int or count not in [0,1,4] or not actors is Array or actors.size()!=count:return false
	var expected: Dictionary=bindings.mido_travel.traffic_combat.death.duplicate(true)
	if not data.get("campaign_cursor") is int:return false
	var trip:=journey(bindings.mido_travel,data.campaign_cursor)
	var contract: bool=navigation_available(bindings.mido_travel,data.campaign_cursor) and bindings.early_contracts.has("world_initialization") and navigation_stations(bindings.mido_travel,data.campaign_cursor,int(data.get("station_id",-1))).size()>0
	if (trip.is_empty() and not contract) or (count>0 and data.campaign_cursor!=10):return false
	if count==0:expected.scope="mido_kernstal_empty_death" if int(data.campaign_cursor)==10 else "mido_yrdal_empty_death";expected.station_id=int(data.station_id) if contract else int(trip.station_id)
	expected.campaign_cursor=data.campaign_cursor;expected.actor_count=count;expected.cargo=bindings.combat_training_destruction.cargo.duplicate(true);expected.actors=[]
	for id in count:
		var row: Variant=actors[id]
		if not row is Dictionary or not row.get("hull_catalogue_id") is int or not bindings.mido_travel.departure_traffic.hull_candidates.any(func(value):return int(value)==row.hull_catalogue_id):return false
		expected.actors.append({"actor_id":id,"actor_kind":3,"hull_catalogue_id":row.hull_catalogue_id,"subtype":0,
			"cargo_model_id":int(expected.cargo_model_id),"cargo_model_resource":expected.cargo_model_resource})
	return Equal.equal_value(data,expected)
