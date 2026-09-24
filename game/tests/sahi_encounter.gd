extends SceneTree
## Detached cast, radio and source-coherence checks. No career is advanced.
const Sahi = preload("res://src/content/sahi_encounter_definitions.gd")
const Visit = preload("res://src/content/sahi_visit_definitions.gd")
const Equal = preload("res://src/content/opening_escape_definitions.gd")
const Dialogue = preload("res://src/content/dialogue_definitions.gd")
const Radio = preload("res://src/simulation/radio_sequence.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	verify_declarations()
	verify_composition()
	verify_runtime_radio_predicate()
	print("Sahi encounter declarations: %d checks; %d failures" % [checks, failures])
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
	check(not Sahi.parameters({}), "Missing data inferred an encounter")
	for alternate in [false, true]:
		var values: Dictionary = Sahi.MAC_VALUES if alternate else Sahi.VALUES
		var spans: Dictionary = Sahi.MAC_SPANS if alternate else Sahi.SPANS
		var proof := proof_for(spans, ORIGIN)
		check(Sahi.validate(values, proof, EXECUTABLE_BYTES, "x86_64", arrival).is_empty(), "The complete source variant was rejected")
		check(Sahi.parameters(JSON.parse_string(JSON.stringify(values))), "Imported JSON numbers failed validation")
		for key in values:
			var bad := values.duplicate(true);bad[key] = null
			check(not Sahi.parameters(bad), "A missing encounter declaration was accepted: " + key)
		for field in ["completion", "failure", "next_cursor", "next_mission", "reward"]:
			var invented := values.duplicate(true);invented[field] = 25
			check(not Sahi.parameters(invented), "An undeclared outcome was accepted: " + field)
		for key in proof:
			for field in ["offset", "bytes"]:
				var bad := proof.duplicate(true);bad[key][field] += 1
				check(not Sahi.validate(values, bad, EXECUTABLE_BYTES, "x86_64", arrival).is_empty(), "A changed proof extent was accepted: " + key + "/" + field)
			var missing := proof.duplicate(true);missing.erase(key)
			check(not Sahi.validate(values, missing, EXECUTABLE_BYTES, "x86_64", arrival).is_empty(), "Missing proof was accepted: " + key)
		var other: Dictionary = Sahi.SPANS if alternate else Sahi.MAC_SPANS
		check(not Sahi.validate(values, proof_for(other, ORIGIN), EXECUTABLE_BYTES, "x86_64", arrival).is_empty(), "Values were accepted with another source layout")
		var mixed := proof.duplicate(true)
		mixed.sahi_encounter_waypoints.offset = ORIGIN + int(other.sahi_encounter_waypoints[0])
		check(not Sahi.validate(values, mixed, EXECUTABLE_BYTES, "x86_64", arrival).is_empty(), "A mixed source layout was accepted")
		for architecture in ["armv7", "arm64", ""]:
			check(not Sahi.validate(values, proof, EXECUTABLE_BYTES, architecture, arrival).is_empty(), "An unsupported architecture was accepted")
		for anchor in [{}, {"provenance": {}}, {"provenance": null}, {"provenance": []},
			{"provenance": {"actor": null}}, {"provenance": {"actor": {"offset": ORIGIN, "bytes": 314}}}]:
			check(not Sahi.validate(values, proof, EXECUTABLE_BYTES, "x86_64", anchor).is_empty(), "A missing staging anchor was accepted")
		check(not Sahi.validate(values, proof, ORIGIN, "x86_64", arrival).is_empty(), "Out-of-file proof was accepted")
		check(not Sahi.validate({}, proof, EXECUTABLE_BYTES, "x86_64", arrival).is_empty(), "Orphan optional proof was accepted")
		verify_authored_differences(values)

func verify_authored_differences(values: Dictionary) -> void:
	var wrong := values.duplicate(true);wrong.weapons.void.damage_multiplier = 2
	check(not Sahi.parameters(wrong), "The Alioth Void damage multiplier was reused")
	wrong = values.duplicate(true);wrong.population.freighter_assembly.body_resource_ids = [17065, 17066, 17067]
	check(not Sahi.parameters(wrong), "Terran freighter models replaced the authored assembly")
	wrong = values.duplicate(true);wrong.population.freighter_combat.boxes[0].half_extents[0] = 1500
	check(not Sahi.parameters(wrong), "Terran collision dimensions were reused")
	wrong = values.duplicate(true);wrong.population.actor_route_loop = true
	check(not Sahi.parameters(wrong), "The Kappa looping route replaced the authored nonloop route")
	wrong = values.duplicate(true);wrong.population.actors.reverse()
	check(not Sahi.parameters(wrong), "The original actor and random-draw order changed")
	wrong = values.duplicate(true);wrong.weapons.npc_target_memberships[0] = [-1, 3, 4]
	check(not Sahi.parameters(wrong), "The Void player target moved ahead of the freighters")
	wrong = values.duplicate(true);wrong.radio_events[3].condition = 20
	check(not Sahi.parameters(wrong), "Destroyed targets replaced collected cargo")
	wrong = values.duplicate(true);wrong.radio_events[3].values = [2]
	check(not Sahi.parameters(wrong), "The source cargo quantity threshold changed")
	wrong = values.duplicate(true);wrong.radio_conditions["6"] = "event_finished"
	check(not Sahi.parameters(wrong), "Started-event dependencies became finished-event dependencies")
	wrong = values.duplicate(true);wrong.portal.visible = true
	check(not Sahi.parameters(wrong), "The initially hidden portal was exposed")

func verify_runtime_radio_predicate() -> void:
	for values in [Sahi.VALUES,Sahi.MAC_VALUES]:
		var definition:={"campaign_cursor":24,"events":values.radio_events.duplicate(true),"timing":values.radio_timing.duplicate(true)}
		check(Dialogue.valid_parameters(definition,24),"Sahi radio was not admitted by the shared dialogue owner")
		var changed:=definition.duplicate(true);changed.events[3].values=[2]
		check(not Dialogue.valid_parameters(changed,24),"A changed Sahi cargo threshold passed shared dialogue validation")
	var predicate:=Radio.new()
	check(not predicate.eligible({"condition":22,"values":[3]},0,{},0,false,0,{"collected_cargo_quantity":2}),"Two accepted units satisfied the three-unit Sahi threshold")
	check(predicate.eligible({"condition":22,"values":[3]},0,{},0,false,0,{"collected_cargo_quantity":3}),"Three accepted units did not satisfy the Sahi threshold")
	check(not predicate.eligible({"condition":22,"values":[3]},0,{},0,false,0,{}),"Missing recovery state satisfied the Sahi threshold")
	var radio:=Radio.new()
	radio._definition={"events":[{"speaker_id":6,"text_id":0,"condition":22,"values":[3]}],"timing":Sahi.VALUES.radio_timing.duplicate(true)}
	radio._lines=[1];radio._text=["test"];radio._started=[false];radio._finished=[false]
	radio._identity={"base_content_id":"base","binding_id":"binding","campaign_cursor":24}
	var combat:={"base_content_id":"base","binding_id":"binding","campaign_cursor":24,"recovery":{"accepted_quantity":2}}
	check(radio.step_sahi(0,combat).is_empty() and not radio.snapshot().started[0],"Sahi radio started before the accepted transfer threshold")
	combat.recovery.accepted_quantity=3
	check(radio.step_sahi(0,combat)==[{"kind":"started","event":0}],"Sahi radio did not consume the current-world accepted transfer counter")
	var before:=radio.snapshot();var foreign:=combat.duplicate(true);foreign.binding_id="other"
	check(radio.step_sahi(0,foreign).is_empty() and not radio.error.is_empty() and radio.snapshot()==before,"Foreign recovery state changed Sahi radio")

func context() -> Dictionary:
	return {"campaign_cursor": 24, "system_id": 9, "station_id": 48, "mission_kind": 4,
		"mission_story": true, "mission_completed": false, "mission_failed": false}

func verify_composition() -> void:
	check(not Sahi.coherent({}) and not Sahi.selected({}, context()), "An earlier pack inferred Sahi declarations")
	for alternate in [false, true]:
		var values: Dictionary = Sahi.MAC_VALUES if alternate else Sahi.VALUES
		var visit: Dictionary = Visit.MAC_VALUES if alternate else Visit.VALUES
		var travel := {"sahi_visit": visit.duplicate(true), "sahi_encounter": values.duplicate(true)}
		var original := travel.duplicate(true)
		var selected := context()
		check(Sahi.coherent(travel) and Sahi.selected(travel, selected), "The matching selected source was rejected")
		check(Equal.equal_value(Sahi.declarations(travel, selected), values), "Detached declarations changed source values")
		check(Equal.equal_value(Sahi.actors(travel, selected), values.population.actors), "Actor descriptors changed order or identity")
		check(Equal.equal_value(Sahi.radio_events(travel, selected), values.radio_events), "Radio declarations selected another source")
		var detached := Sahi.declarations(travel, selected);detached.population.waypoints[0][0] = -1
		var cast := Sahi.actors(travel, selected);cast[0].hull_catalogue_id = -1
		var radio := Sahi.radio_events(travel, selected);radio[3].values.clear()
		check(travel == original, "A detached query mutated imported declarations")
		for missing in ["sahi_visit", "sahi_encounter"]:
			var absent := travel.duplicate(true);absent.erase(missing)
			check(not Sahi.coherent(absent) and Sahi.declarations(absent, selected).is_empty(), "An orphan capability was accepted")
		var mixed := travel.duplicate(true);mixed.sahi_visit = Visit.VALUES if alternate else Visit.MAC_VALUES
		check(not Sahi.coherent(mixed) and Sahi.radio_events(mixed, selected).is_empty(), "Encounter and briefing source editions were mixed")
		for field in ["campaign_cursor", "system_id", "station_id", "mission_kind"]:
			for value in [-1, 0, 23, 25, 24.0, "24", null, true]:
				var wrong := selected.duplicate(true);wrong[field] = value
				check(not Sahi.selected(travel, wrong) and Sahi.actors(travel, wrong).is_empty() and Sahi.radio_events(travel, wrong).is_empty(), "A foreign story context exposed the encounter: " + field)
		for field in ["mission_story", "mission_completed", "mission_failed"]:
			for value in [not selected[field], null, 1, "true"]:
				var wrong := selected.duplicate(true);wrong[field] = value
				check(not Sahi.selected(travel, wrong), "An ineligible mission exposed the encounter: " + field)
		for field in selected:
			var missing := selected.duplicate(true);missing.erase(field)
			check(Sahi.declarations(travel, missing).is_empty(), "Missing context exposed the encounter: " + field)
		check(selected == context() and travel == original, "Declaration queries changed progress or original content")
