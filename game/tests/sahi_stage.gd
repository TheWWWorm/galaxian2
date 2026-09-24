extends SceneTree
## Detached stage and portal predicates; no mission is admitted or advanced.
const Stage = preload("res://src/content/sahi_stage_definitions.gd")
const Encounter = preload("res://src/content/sahi_encounter_definitions.gd")
const Visit = preload("res://src/content/sahi_visit_definitions.gd")
const Equal = preload("res://src/content/opening_escape_definitions.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	verify_proof()
	verify_composition()
	verify_radio_order()
	verify_contact()
	verify_transition()
	print("Sahi stage declarations: %d checks; %d failures" % [checks, failures])
	quit(1 if failures else 0)

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func proof_for(spans: Dictionary, origin: int) -> Dictionary:
	var result := {}
	for key in spans:result[key] = {"offset": origin + int(spans[key][0]), "bytes": int(spans[key][1])}
	return result

func verify_proof() -> void:
	const ORIGIN := 0x400000
	const EXECUTABLE_BYTES := 0x1000000
	var arrival := {"provenance": {"actor": {"offset": ORIGIN, "bytes": 315}}}
	check(Stage.validate({}, {}, EXECUTABLE_BYTES, "x86_64", {}).is_empty(), "Missing optional stage data was rejected")
	check(not Stage.parameters({}), "Absent data inferred a stage")
	check(Stage.parameters(JSON.parse_string(JSON.stringify(Stage.VALUES, "", true, true))), "Imported JSON numeric values were rejected")
	for spans in [Stage.SPANS, Stage.MAC_SPANS]:
		var proof := proof_for(spans, ORIGIN)
		check(Stage.validate(Stage.VALUES, proof, EXECUTABLE_BYTES, "x86_64", arrival).is_empty(), "A complete source proof was rejected")
		for key in proof:
			for field in ["offset", "bytes"]:
				var changed := proof.duplicate(true);changed[key][field] += 1
				check(not Stage.validate(Stage.VALUES, changed, EXECUTABLE_BYTES, "x86_64", arrival).is_empty(), "Changed source extent was accepted: " + key + "/" + field)
			var missing := proof.duplicate(true);missing.erase(key)
			check(not Stage.validate(Stage.VALUES, missing, EXECUTABLE_BYTES, "x86_64", arrival).is_empty(), "Missing source extent was accepted: " + key)
		var other: Dictionary = Stage.MAC_SPANS if spans == Stage.SPANS else Stage.SPANS
		var mixed := proof.duplicate(true)
		mixed.sahi_stage_portal_vtable.offset = ORIGIN + int(other.sahi_stage_portal_vtable[0])
		check(not Stage.validate(Stage.VALUES, mixed, EXECUTABLE_BYTES, "x86_64", arrival).is_empty(), "Mixed source extents were accepted")
		for architecture in ["armv7", "arm64", ""]:
			check(not Stage.validate(Stage.VALUES, proof, EXECUTABLE_BYTES, architecture, arrival).is_empty(), "Unsupported architecture was accepted")
		for anchor in [{}, {"provenance": {}}, {"provenance": null}, {"provenance": []},
			{"provenance": {"actor": null}}, {"provenance": {"actor": {"offset": ORIGIN, "bytes": 314}}}]:
			check(not Stage.validate(Stage.VALUES, proof, EXECUTABLE_BYTES, "x86_64", anchor).is_empty(), "Missing staging anchor was accepted")
		check(not Stage.validate(Stage.VALUES, proof, ORIGIN, "x86_64", arrival).is_empty(), "Out-of-file source proof was accepted")
		check(not Stage.validate({}, proof, EXECUTABLE_BYTES, "x86_64", arrival).is_empty(), "Orphan optional proof was accepted")
	for key in Stage.VALUES:
		var missing: Dictionary = Stage.VALUES.duplicate(true);missing.erase(key)
		check(not Stage.parameters(missing), "A missing declaration was accepted: " + key)
		if Stage.VALUES[key] is Dictionary:
			for field in Stage.VALUES[key]:
				var changed: Dictionary = Stage.VALUES.duplicate(true);changed[key][field] = null
				check(not Stage.parameters(changed), "Changed stage data was accepted: " + key + "/" + field)
	for field in ["reward", "result_dialogue", "next_encounter", "station_acknowledgement"]:
		var invented: Dictionary = Stage.VALUES.duplicate(true);invented[field] = 25
		check(not Stage.parameters(invented), "An undeclared outcome was accepted: " + field)
	var altered: Dictionary = Stage.VALUES.duplicate(true);altered.spin.elapsed_completion_ms = 5000
	check(not Stage.parameters(altered), "The spin divisor became an invented completion delay")
	altered = Stage.VALUES.duplicate(true);altered.view.scripted_coast = false
	check(not Stage.parameters(altered), "The scripted view froze ordinary player motion")
	altered = Stage.VALUES.duplicate(true);altered.contact.entry_distance_maximum = 1000
	check(not Stage.parameters(altered), "Portal entry lost its strict 1000 boundary")

func context() -> Dictionary:
	return {"campaign_cursor": 24, "system_id": 9, "station_id": 48, "mission_kind": 4,
		"mission_story": true, "mission_completed": false, "mission_failed": false}

func travel(alternate: bool = true) -> Dictionary:
	return {"sahi_stage": Stage.VALUES.duplicate(true),
		"sahi_visit": (Visit.MAC_VALUES if alternate else Visit.VALUES).duplicate(true),
		"sahi_encounter": (Encounter.MAC_VALUES if alternate else Encounter.VALUES).duplicate(true)}

func verify_composition() -> void:
	check(not Stage.coherent({}) and not Stage.selected({}, context()), "An earlier pack inferred stage support")
	for alternate in [false, true]:
		var data := travel(alternate)
		var original := data.duplicate(true)
		var selected := context()
		check(Stage.coherent(data) and Stage.selected(data, selected), "Matching Sahi declarations failed composition")
		check(Equal.equal_value(Stage.declarations(data, selected), Stage.VALUES), "A detached query changed source content")
		var detached := Stage.declarations(data, selected);detached.view.camera_eye_offset.clear()
		check(data == original, "A query mutated imported declarations")
		for key in ["sahi_stage", "sahi_visit", "sahi_encounter"]:
			var missing := data.duplicate(true);missing.erase(key)
			check(not Stage.coherent(missing) and Stage.declarations(missing, selected).is_empty(), "Orphan stage data was accepted")
		var mixed := data.duplicate(true);mixed.sahi_visit = Visit.VALUES if alternate else Visit.MAC_VALUES
		check(not Stage.coherent(mixed), "Arrival and cast from different sources composed")
		for field in ["campaign_cursor", "system_id", "station_id", "mission_kind"]:
			for value in [-1, 0, 23, 25, 24.0, "24", null, true]:
				var wrong := selected.duplicate(true);wrong[field] = value
				check(not Stage.selected(data, wrong) and Stage.declarations(data, wrong).is_empty(), "Foreign story context exposed stage data: " + field)
		for field in ["mission_story", "mission_completed", "mission_failed"]:
			for value in [not selected[field], null, 1, "true"]:
				var wrong := selected.duplicate(true);wrong[field] = value
				check(not Stage.selected(data, wrong), "Ineligible story flags exposed stage data: " + field)
		check(selected == context() and data == original, "A declaration query changed progress")

func verify_radio_order() -> void:
	var data := travel()
	var selected := context()
	var started := [false, false, false, false, false]
	check(Stage.phase_for_started_events(data, selected, 0, started) == 0, "Initial phase advanced without a radio event")
	started[3] = true
	check(Stage.phase_for_started_events(data, selected, 0, started) == 1, "The cargo line did not start the view")
	check(Stage.phase_for_started_events(data, selected, 1, started) == 1, "The portal opened before its line started")
	started[4] = true
	check(Stage.phase_for_started_events(data, selected, 0, started) == 1, "Two ready radio lines skipped the first view update")
	check(Stage.phase_for_started_events(data, selected, 1, started) == 2, "The portal line did not open phase2")
	check(Stage.phase_for_started_events(data, selected, 2, started) == 2, "Open phase manufactured a completion phase")
	check(data.sahi_stage.sequence.spin_on_open_frame, "The opening frame lost its spin update")
	for value in [-1, 3, 1.0, true, null, "1"]:
		check(Stage.phase_for_started_events(data, selected, value, started) == -1, "Malformed phase was accepted")
	for events in [[], [true], [false, false, false, 1, true], [false, false, false, null, true], null, {}]:
		check(Stage.phase_for_started_events(data, selected, 0, events) == -1, "Malformed radio observations were accepted")
	check(Stage.phase_for_started_events({}, selected, 0, started) == -1, "Missing source content drove the stage")
	check(data == travel() and selected == context() and started == [false, false, false, true, true], "The phase predicate mutated an input")

func observation(offset: Vector3 = Vector3.ZERO) -> Dictionary:
	return {"environment_contact_enabled": true, "portal_visible": true, "mining_active": false,
		"portal_elapsed_ms": 0, "player_offset": offset}

func verify_contact() -> void:
	var data := travel()
	var selected := context()
	for row in [[0.0, 0, 156, true], [999.0, 999, 152, true], [999.75, 999, 152, true],
		[1000.0, 1000, 152, false], [39744.0, 39744, 1, false], [39999.0, 39999, 0, false]]:
		var point := Vector3(row[0], 0, 0)
		var result := Stage.portal_contact(data, selected, observation(point))
		check(result == {"distance": row[1], "pull_distance": row[2], "entry_contact": row[3]}, "Portal truncation or pull boundary changed: " + str(row[0]))
		check(Stage.portal_contact(data, selected, observation(-point)) == result, "Portal contact became directional")
	for point in [Vector3(40000, 0, 0), Vector3(0, -40000, 0), Vector3(0, 0, 40000),
		Vector3(30000, 30000, 0), Vector3(INF, 0, 0), Vector3(0, NAN, 0)]:
		check(Stage.portal_contact(data, selected, observation(point)).is_empty(), "An out-of-range or nonfinite point entered the portal")
	for elapsed in [-3000, -1, 0, 60000]:
		var state := observation();state.portal_elapsed_ms = elapsed
		check(Stage.portal_contact(data, selected, state).get("entry_contact", false), "An opening or stable portal rejected contact")
	for elapsed in [60001, 63001, 0.0, null, true, "0"]:
		var state := observation();state.portal_elapsed_ms = elapsed
		check(Stage.portal_contact(data, selected, state).is_empty(), "A closing portal or malformed clock was accepted")
	for field in ["environment_contact_enabled", "portal_visible", "mining_active"]:
		for value in [not observation()[field], 1, null, "true"]:
			var state := observation();state[field] = value
			check(Stage.portal_contact(data, selected, state).is_empty(), "An unavailable portal or malformed flag was accepted: " + field)
	for field in observation():
		var state := observation();state.erase(field)
		check(Stage.portal_contact(data, selected, state).is_empty(), "A missing contact observation was inferred: " + field)
	var wrong_position := observation();wrong_position.player_offset = [0, 0, 0]
	check(Stage.portal_contact(data, selected, wrong_position).is_empty(), "An unnormalized pose bypassed the contact owner")
	var original := observation(Vector3(1000, 0, 0))
	Stage.portal_contact(data, selected, original)
	check(original == observation(Vector3(1000, 0, 0)) and data == travel() and selected == context(), "A contact query moved the player or changed content")
	check(Stage.portal_contact({}, selected, observation()).is_empty(), "Absent content admitted portal contact")

func verify_transition() -> void:
	var data := travel()
	var selected := context()
	var earned := {"portal_entered": true, "player_hull": 1}
	check(Stage.transition_ready(data, selected, earned), "A living portal entrant failed the readiness query")
	for hull in [0, -1, 1.0, true, null, "1"]:
		var state := earned.duplicate();state.player_hull = hull
		check(not Stage.transition_ready(data, selected, state), "A dead or malformed player passed portal readiness")
	for entered in [false, 1, null, "true"]:
		var state := earned.duplicate();state.portal_entered = entered
		check(not Stage.transition_ready(data, selected, state), "Missing earned entry became success")
	check(not Stage.transition_ready(data, selected, {"player_hull": 100, "radio_finished": 4, "elapsed_ms": 999999}), "Radio or elapsed time manufactured portal entry")
	check(not Stage.transition_ready({}, selected, earned), "An absent declaration admitted a transition")
	var next := selected.duplicate();next.campaign_cursor = 25
	check(not Stage.transition_ready(data, next, earned), "The next unsupported cursor repeated the Sahi transition")
	check(earned == {"portal_entered": true, "player_hull": 1} and selected == context(), "Readiness advanced the career")
