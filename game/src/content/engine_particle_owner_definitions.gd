extends RefCounted
## Normal player engine-manager ownership. Boost and other hulls need their own
## declarations; nozzle attachments and artwork are validated separately.
const Layouts=preload("res://src/content/declaration_layouts.gd")
const Equal=preload("res://src/content/opening_escape_definitions.gd")
const Fonts=preload("res://src/content/font_definitions.gd")
const Engines=preload("res://src/content/engine_particle_definitions.gd")
const VALUES := {"scope":"mac_betty_normal_engine_owner","ship_id":0,"nozzle_count":4,"first_preset":29,"pose":"player_statistics","manager_velocity_interval_ms":10,"initial_engine_enabled":true,"initial_player_hidden":false,"initial_draw_enabled":true,"manager_updates_when_hidden":true,"engine_flag_controls_emission":true,"engine_flag_controls_draw":true,"hidden_flag_controls_emission":false,"manager_hide_resets_emitters":false,"entry_engine_enabled":false,"mining_capture_engine_enabled":false,"mining_release_engine_enabled":true,"death_engine_enabled":false,"revive_engine_enabled":true,"boost_available":false}
const OPENING_SHIP := {"ship_id":10,"nozzle_count":3,"first_preset":29}
const SPANS := {"manager_initial_flags":[509330,46],"player_initial_flags":[551167,14],"world_update":[118201,82],"world_draw":[110499,17],"manager_update":[510392,314],"manager_draw":[512192,56],"engine_enable":[555592,112],"manager_emitting":[511634,52],"emitting_flag":[514238,32],"player_hidden":[603252,54],"entry_disable":[122627,15],"arrival_disable":[380838,16],"mining_cancel_enable":[586859,23],"mining_capture_disable":[587571,15],"mining_release_enable0":[589591,21],"mining_release_enable1":[589894,25],"death_disable":[600188,19],"revive_enable":[600403,18],"drill_stop_enable":[602054,18]}
const MAC_ALTERNATE := {"manager_initial_flags":[509866,46],"player_initial_flags":[551703,14],"world_update":[118201,82],"world_draw":[110499,17],"manager_update":[510928,314],"manager_draw":[512728,56],"engine_enable":[556128,112],"manager_emitting":[512170,52],"emitting_flag":[514774,32],"player_hidden":[603800,54],"entry_disable":[122627,15],"arrival_disable":[381354,16],"mining_cancel_enable":[587395,23],"mining_capture_disable":[588107,15],"mining_release_enable0":[590139,21],"mining_release_enable1":[590442,25],"death_disable":[600736,19],"revive_enable":[600951,18],"drill_stop_enable":[602602,18]}

static func parameters(data: Variant) -> bool:
	if not data is Dictionary or not data.get("provenance") is Dictionary:return false
	var opening: bool=data.has("opening_ship")
	if data.size()!=VALUES.size()+1+int(opening):return false
	for key in VALUES:
		if not Equal.equal_value(data.get(key),VALUES[key]):return false
	if opening and not Equal.equal_value(data.opening_ship,OPENING_SHIP):return false
	return true

static func validate(data: Variant,source_bytes: int,arch: String,arrival: Dictionary,engines: Dictionary) -> String:
	if not data is Dictionary:return "Missing player engine ownership declarations"
	if data.is_empty():return ""
	if arch!="x86_64" or not parameters(data) or not Engines.parameters(engines):return "Unsupported player engine ownership declarations"
	if data.has("opening_ship")!=engines.has("opening_ship"):return "Player engine hull support differs from its nozzle declarations"
	var origin: Variant=arrival.get("provenance",{}).get("actor")
	if not Fonts.extent(origin,"offset","bytes",[315],source_bytes):return "Player engine ownership lacks its source anchor"
	return "" if Layouts.matches(data.provenance,int(origin.offset),source_bytes,[SPANS,MAC_ALTERNATE]) else "Invalid player engine ownership extents"

static func available(bindings: RefCounted) -> bool:
	if bindings==null or bindings.get("source_architecture")!="x86_64" or not Engines.parameters(bindings.get("engine_particles")):return false
	var owner: Variant=bindings.get("engine_particle_owners")
	# Earlier Mac readers already imported and validated Betty's source nozzle
	# declaration, but did not export the separate manager ownership field. The
	# independently verified native manager rule applies to that same hull.
	return parameters(owner) or (owner is Dictionary and owner.is_empty())

static func available_for(bindings: RefCounted,ship_id: Variant) -> bool:
	if not available(bindings):return false
	var owner: Dictionary=bindings.engine_particle_owners
	var engine: Dictionary=bindings.engine_particles
	if ship_id==int(VALUES.ship_id):return true
	if owner.is_empty():return false
	return ship_id==int(OPENING_SHIP.ship_id) and Equal.equal_value(owner.get("opening_ship"),OPENING_SHIP) and Equal.equal_value(engine.get("opening_ship"),Engines.OPENING_SHIP)
