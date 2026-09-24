extends SceneTree
## Detached arrival declarations and clock predicates. No career or encounter
## completion is produced by these component checks.
const Sahi = preload("res://src/content/sahi_visit_definitions.gd")
const Equal = preload("res://src/content/opening_escape_definitions.gd")
var checks := 0
var failures := 0

class BindingsFixture extends RefCounted:
	var mido_travel := {}

func _initialize() -> void:
	verify_declarations()
	verify_selection()
	print("Sahi arrival declarations: %d checks; %d failures" % [checks, failures])
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

func verify_declarations() -> void:
	const ORIGIN := 0x400000
	const EXECUTABLE_BYTES := 0x1000000
	var arrival := {"provenance": {"actor": {"offset": ORIGIN, "bytes": 315}}}
	check(Sahi.validate({}, {}, EXECUTABLE_BYTES, "x86_64", {}).is_empty(), "An absent optional declaration was rejected")
	check(not Sahi.parameters({}) and not Sahi.available(null), "Missing declarations inferred Sahi support")
	for alternate in [false, true]:
		var values: Dictionary = Sahi.MAC_VALUES if alternate else Sahi.VALUES
		var spans: Dictionary = Sahi.MAC_SPANS if alternate else Sahi.SPANS
		var proof := proof_for(spans, ORIGIN)
		check(Sahi.parameters(values) and Sahi.validate(values, proof, EXECUTABLE_BYTES, "x86_64", arrival).is_empty(), "The complete source variant was rejected")
		var decoded: Dictionary = JSON.parse_string(JSON.stringify(values))
		check(Sahi.parameters(decoded), "Imported JSON integers failed declaration validation")
		for key in values:
			var bad := values.duplicate(true);bad[key] = null
			check(not Sahi.parameters(bad), "A changed Sahi declaration was accepted: " + key)
		var extra := values.duplicate(true);extra.next_cursor = 25
		check(not Sahi.parameters(extra), "An undeclared cursor25 transition was accepted")
		var next := values.duplicate(true);next.result_event_count = 1
		check(not Sahi.parameters(next), "An invented completion dialogue was accepted")
		for key in proof:
			for field in ["offset", "bytes"]:
				var bad := proof.duplicate(true);bad[key][field] += 1
				check(not Sahi.validate(values, bad, EXECUTABLE_BYTES, "x86_64", arrival).is_empty(), "A changed source extent was accepted: " + key + "/" + field)
			var missing := proof.duplicate(true);missing.erase(key)
			check(not Sahi.validate(values, missing, EXECUTABLE_BYTES, "x86_64", arrival).is_empty(), "Missing source evidence was accepted: " + key)
		var other: Dictionary = Sahi.SPANS if alternate else Sahi.MAC_SPANS
		check(not Sahi.validate(values, proof_for(other, ORIGIN), EXECUTABLE_BYTES, "x86_64", arrival).is_empty(), "Source values and proof layout were mixed")
		var mixed := proof.duplicate(true)
		mixed.sahi_briefing_events.offset = ORIGIN + int(other.sahi_briefing_events[0])
		check(not Sahi.validate(values, mixed, EXECUTABLE_BYTES, "x86_64", arrival).is_empty(), "One foreign source span was accepted")
		for architecture in ["armv7", "arm64", ""]:
			check(not Sahi.validate(values, proof, EXECUTABLE_BYTES, architecture, arrival).is_empty(), "An unsupported source architecture was accepted")
		for anchor in [{}, {"provenance": {}}, {"provenance": null}, {"provenance": []},
			{"provenance": {"actor": null}}, {"provenance": {"actor": {"offset": ORIGIN, "bytes": 314}}}]:
			check(not Sahi.validate(values, proof, EXECUTABLE_BYTES, "x86_64", anchor).is_empty(), "Invalid staging evidence was accepted")
		check(not Sahi.validate(values, proof, ORIGIN, "x86_64", arrival).is_empty(), "Out-of-file source evidence was accepted")
		check(not Sahi.validate({}, proof, EXECUTABLE_BYTES, "x86_64", arrival).is_empty(), "Orphan optional proof was accepted")

func context() -> Dictionary:
	return {"campaign_cursor": 24, "system_id": 9, "station_id": 48, "mission_kind": 4,
		"mission_story": true, "mission_completed": false, "mission_failed": false,
		"controller_ready": true, "briefing_pending": true, "dialogue_active": false, "hud_elapsed_ms": 5001}

func verify_selection() -> void:
	var empty := BindingsFixture.new()
	check(not Sahi.available(empty) and not Sahi.selected({}, context()), "An earlier pack exposed undeclared arrival lines")
	for rules in [Sahi.VALUES, Sahi.MAC_VALUES]:
		var travel := {"sahi_visit": rules.duplicate(true)}
		var bindings := BindingsFixture.new();bindings.mido_travel = travel
		var initial := context()
		var original := travel.duplicate(true)
		check(Sahi.available(bindings) and Sahi.selected(travel, initial), "The selected Sahi story arrival was rejected")
		check(Equal.equal_value(Sahi.briefing(travel, initial), rules.briefing.events), "Arrival selected another source's lines")
		var detached := Sahi.briefing(travel, initial);detached[0].text_id = -1
		check(travel == original, "A detached briefing changed imported declarations")
		for field in ["campaign_cursor", "system_id", "station_id", "mission_kind"]:
			for value in [-1, 0, 10, 23, 25, 55, 24.0, "24", null, true]:
				var wrong := initial.duplicate(true);wrong[field] = value
				if value is int and value == initial[field]:continue
				check(not Sahi.selected(travel, wrong) and Sahi.briefing(travel, wrong).is_empty() and not Sahi.can_start_briefing(travel, wrong), "Foreign story context exposed the Sahi briefing: " + field)
		for field in ["mission_story", "mission_completed", "mission_failed"]:
			var wrong := initial.duplicate(true);wrong[field] = not initial[field]
			check(not Sahi.selected(travel, wrong), "An ineligible mission selected the briefing: " + field)
		for elapsed in [0, 4999, 5000, 5001, 5002, 100000]:
			var timed := initial.duplicate(true);timed.hud_elapsed_ms = elapsed
			check(Sahi.can_start_briefing(travel, timed) == (elapsed >= 5001), "The HUD briefing poll boundary changed")
		for value in [-1, 5001.0, "5001", null, true]:
			var malformed := initial.duplicate(true);malformed.hud_elapsed_ms = value
			check(not Sahi.can_start_briefing(travel, malformed), "A non-native or negative HUD clock was accepted")
		for field in ["controller_ready", "briefing_pending", "dialogue_active"]:
			for value in [not initial[field], null, 1, "true"]:
				var waiting := initial.duplicate(true);waiting[field] = value
				check(not Sahi.can_start_briefing(travel, waiting), "A held or malformed briefing condition was ignored: " + field)
		for field in initial:
			var missing := initial.duplicate(true);missing.erase(field)
			check(not Sahi.can_start_briefing(travel, missing), "Missing arrival context was accepted: " + field)
		check(Sahi.can_start_briefing(travel, initial) and Sahi.can_start_briefing(travel, initial), "A pure readiness query consumed a briefing")
		check(initial == context() and travel == original, "Arrival validation changed progress or original data")
		check(rules.result_event_count == 0 and not rules.has("next_cursor") and not rules.has("next_mission"), "Arrival declarations claimed encounter completion")
