extends SceneTree
const Vitals = preload("res://src/simulation/combat_vitals.gd")
var failures := 0

func _initialize() -> void:
	var vitals := Vitals.new()
	check(vitals.normal_hit(1, true).is_empty() and not vitals.error.is_empty(), "Unconfigured hit accepted")
	# Independent examples for the normal-hit rule verified in both supplied
	# editions. These are arithmetic fixtures, not original-executable replay.
	for row in [
		[100, 30, 20.75, 5, 100, 30, 15.0, "shield"],
		[100, 30, 20.75, 20, 100, 30, 0.0, "shield"],
		[100, 30, 20.75, 21, 100, 29, 0.0, "armor"],
		[100, 30, 20.75, 50, 100, 0, 0.0, "armor"],
		[100, 30, 20.75, 51, 99, 0, 0.0, "hull"],
		[100, 30, 20.75, 150, 0, 0, 0.0, "hull"],
		[100, 30, 20.75, 999, 0, 0, 0.0, "hull"],
		[100, 0, 0.9, 1, 99, 0, 0.0, "hull"],
		[100, 30, 0.9, 1, 100, 29, 0.0, "armor"],
		[100, 30, 20.75, 0, 100, 30, 20.0, "shield"],
		[100, 0, 0.0, 0, 100, 0, 0.0, "shield"],
		[2147483647, 2147483647, 0.0, 2147483647, 2147483647, 0, 0.0, "armor"],
		[2147483647, 0, 0.0, 2147483647, 0, 0, 0.0, "hull"],
		[100, 30, 16777218.0, 1, 100, 30, 16777216.0, "shield"],
	]:
		check(vitals.configure(row[0], row[1], row[2]), vitals.error)
		var before: Dictionary = vitals.snapshot()
		var result: Dictionary = vitals.normal_hit(row[3], true)
		check(not result.is_empty(), vitals.error)
		if result.is_empty(): continue
		check(result.accepted and result.after == {"hull": row[4], "armor": row[5], "shield": row[6]}, "Pool overflow/quantization: " + str(row))
		check(result.impact_layer == row[7] and result.destroyed_now == (row[4] == 0), "Impact/death boundary: " + str(row))
		check(result.before == before, "Hit changed its before snapshot")
		result.before.hull = -1
		result.after.hull = -1
		check(vitals.snapshot().hull == row[4], "Hit result aliases live state")
	check_gates_and_failures(vitals)
	check_sequences(vitals)
	print("Combat vitals checks: %d failures" % failures)
	quit(1 if failures else 0)

func check_gates_and_failures(vitals: RefCounted) -> void:
	check(vitals.configure(150, 30, 20.75), vitals.error)
	var before: Dictionary = vitals.snapshot()
	var ignored: Dictionary = vitals.normal_hit(1000, false)
	check(not ignored.accepted and not ignored.destroyed_now and ignored.impact_layer.is_empty() and vitals.snapshot() == before, "Disabled hit consumed pools")
	for bad in [-1, 0.5, 1.0, NAN, INF, true, "1", null, [], {}, 2147483648]:
		check(vitals.normal_hit(bad, true).is_empty() and not vitals.error.is_empty() and vitals.snapshot() == before, "Invalid amount changed pools: " + str(bad))
	for bad in [0, 1, null, "true"]:
		check(vitals.normal_hit(1, bad).is_empty() and not vitals.error.is_empty() and vitals.snapshot() == before, "Implicit hit permission accepted")
	check(vitals.configure(0, 30, 20.75), vitals.error)
	before = vitals.snapshot()
	ignored = vitals.normal_hit(1000, true)
	check(not ignored.accepted and not ignored.destroyed_now and vitals.snapshot() == before, "Dead actor consumed shield/armor or emitted another death")
	for bad in [-1, 1.0, NAN, INF, true, "1", null, 2147483648]:
		check(not vitals.configure(bad, 0, 0) and vitals.snapshot().is_empty(), "Invalid hull retained state")
		check(not vitals.configure(100, bad, 0) and vitals.snapshot().is_empty(), "Invalid armor retained state")
	for bad in [-0.01, NAN, INF, true, "1", null, 2147483521.0]:
		check(not vitals.configure(100, 0, bad) and vitals.snapshot().is_empty(), "Invalid shield retained state")
	check(vitals.configure(100, 0, 0.1), vitals.error)
	check(vitals.snapshot().shield == 0.10000000149011612, "Shield input lost source binary32 precision")
	check(vitals.configure(100, 0, 2147483520.0), vitals.error)
	check(vitals.normal_hit(2147483647, true).after.hull == 0, "Large valid hit did not carry through shield")
	vitals.clear()
	check(vitals.snapshot().is_empty() and vitals.error.is_empty(), "Clear retained combat state")

func check_sequences(vitals: RefCounted) -> void:
	check(vitals.configure(4, 3, 2.9), vitals.error)
	var layers := []
	var deaths := 0
	for i in 12:
		var result: Dictionary = vitals.normal_hit(1, true)
		if result.accepted: layers.append(result.impact_layer)
		if result.destroyed_now: deaths += 1
	check(layers == ["shield", "shield", "armor", "armor", "armor", "hull", "hull", "hull", "hull"] and deaths == 1, "Repeated hits crossed layers or repeated death")
	# Exhaustively check conservation and monotonicity with integer shields.
	for hull in range(1, 7):
		for armor in 6:
			for shield in 6:
				for damage in 24:
					check(vitals.configure(hull, armor, shield), vitals.error)
					var result: Dictionary = vitals.normal_hit(damage, true)
					var after: Dictionary = result.after
					check(after.hull + after.armor + int(after.shield) == maxi(0, hull + armor + shield - damage), "Damage was created or lost")
					check(after.hull <= hull and after.armor <= armor and after.shield <= shield, "Hit replenished a pool")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
