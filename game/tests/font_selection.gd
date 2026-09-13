extends SceneTree
const Definitions = preload("res://src/content/font_definitions.gd")
const Fixture = preload("res://tests/font_fixture.gd")
var failures := 0
func _initialize() -> void:
	var data := Fixture.definition("baseline", "middle", "large")
	check(Definitions.parameters(data), "Synthetic font declarations rejected")
	var a := Definitions.choice(data, "aa", 0)
	check(a.font_id == 500 and a.resource == "baseline" and a.font_group == 0 and a.spacing == -2, "Default font choice changed")
	a = Definitions.choice(data, "ak", 1)
	check(a.font_id == 504 and a.resource == "middle" and a.language_id == 10 and a.spacing == -5, "Language-specific medium font changed")
	a = Definitions.choice(data, "ap", 3)
	check(a.font_id == 507 and a.resource == "large" and a.spacing == -7, "Japanese large mode changed")
	a = Definitions.choice(data, "ap", 2)
	check(a.resource == "baseline" and a.spacing == -5, "Wide mode must use its source baseline atlas")
	a = Definitions.choice(data, "ap", 3, "secondary")
	check(a.font_id == 501 and a.font_group == 1 and a.spacing == 0, "Secondary font must use its own group and spacing")
	a = Definitions.choice(data, "ak", 0, "language_list")
	check(a.font_id == 502 and a.spacing == 0, "Language list font changed")
	for mode in [-1, 4]: check(Definitions.choice(data, "aa", mode).is_empty(), "Invalid mode accepted")
	check(Definitions.choice(data, "zz", 0).is_empty() and Definitions.choice(data, "aa", 0, "bad").is_empty(), "Unknown language/role guessed")
	var alias := data.duplicate(true)
	alias.languages.rows[0].file = "zz.lang"
	check(Definitions.choice(alias, "aa", 0).is_empty() and Definitions.choice(alias, "zz", 0).font_id == 500, "Language was guessed from numeric ID")
	for mutation in ["font", "language", "spacing", "variants"]:
		var bad := data.duplicate(true)
		match mutation:
			"font": bad.records[1].id = bad.records[0].id
			"language": bad.languages.rows[1].file = bad.languages.rows[0].file
			"spacing": bad.selection.spacing.default[0] = 0.5
			"variants": bad.textures.rows[0].variants.large = bad.textures.rows[0].variants.baseline
		check(not Definitions.parameters(bad) and Definitions.choice(bad, "aa", 0).is_empty(), "Malformed font choice accepted: " + mutation)
	print("Font selection checks: %d failures" % failures)
	quit(1 if failures else 0)
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
