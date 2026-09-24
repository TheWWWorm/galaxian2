extends SceneTree
## Detached source-catalogue and cursor33 material-accounting checks.
const Library = preload("res://src/content/library.gd")
const Bindings = preload("res://src/content/resource_bindings.gd")
const Catalogues = preload("res://src/content/catalogues.gd")
const Blueprints = preload("res://src/simulation/blueprint_progress.gd")
class CatalogueBag extends RefCounted:
	var content_id: String
	var tables: Dictionary

const BLUEPRINT_IDS = [11,15,25,27,33,37,46,54,59,67,85,90,96,178,179,182,183,206,210,221,223,225,226,227,232]
var checks := 0
var failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3 and args.size() != 6:
		check(false, "Expected one or two imported Mac content/binding/visual triples")
	else:
		verify(args[0], args[1], "Mac content")
		if args.size() == 6: verify(args[3], args[4], "older Mac")
	print("Blueprint progress: %d checks; %d failures" % [checks, failures])
	quit(1 if failures else 0)


func verify(content: String, binding_path: String, label: String) -> void:
	var library := Library.new()
	var bindings := Bindings.new()
	var catalogues := Catalogues.new()
	if not library.open(content) or not bindings.open(binding_path, library.manifest) or not catalogues.open(library):
		check(false, label + ": " + library.error + bindings.error + catalogues.error)
		return
	var owner := Blueprints.new()
	check(owner.configure(catalogues, bindings.binding_id), owner.error)
	if owner.snapshot().is_empty(): return
	var first: Dictionary = owner.snapshot()
	check(first.base_content_id == catalogues.content_id and first.binding_id == bindings.binding_id, "Blueprint state lost content identity")
	check(first.entries.map(func(row): return row.item_id) == BLUEPRINT_IDS, "Initial career blueprint list differs from the 25 source recipes")
	for row in first.entries:
		var recipe: Array = Array(catalogues.tables.items[row.item_id].arrays[1])
		check(not row.available and row.material_value == 0 and row.remaining == recipe, "Initial blueprint progress differs from its source recipe")
	var drive: Dictionary = owner.entry(85)
	check(drive.remaining == [50,10,10,10,40,70,75,40] and not drive.available and drive.material_value == 0, "Khador Drive did not start with its full recipe")
	var detached: Dictionary = owner.snapshot()
	detached.entries[10].remaining[0] = 123
	check(owner.entry(85) == drive, "A snapshot mutated retained blueprint progress")
	var restored := Blueprints.new()
	check(restored.restore(catalogues, bindings.binding_id, first) and restored.snapshot() == first, restored.error)
	verify_entry_boundaries(catalogues, bindings.binding_id, first, owner, restored)
	var staged: RefCounted = owner.fork_for_transaction()
	var transaction: Dictionary = contract(first, drive, 73)
	check(staged.precredit_story33(transaction), staged.error)
	var credited: Dictionary = staged.entry(85)
	check(credited.available and credited.remaining == [0,10,10,10,40,70,75,40] and credited.material_value == 20000, "Story33 did not precredit exactly fifty crystals at 400 each")
	check(owner.snapshot() == first and staged.snapshot().entries.size() == 25, "A staged credit changed the original owner or recipe list")
	check(staged.snapshot().entries[9] == first.entries[9] and staged.snapshot().entries[11] == first.entries[11], "Story33 changed another blueprint")
	check(not staged.snapshot().has("cargo") and not staged.snapshot().has("equipment"), "Blueprint progress fabricated player inventory")
	var after: Dictionary = staged.snapshot()
	check(not staged.precredit_story33(transaction) and staged.snapshot() == after, "The same transaction proposal credited crystals twice")
	var bad: Dictionary = transaction.duplicate(true)
	bad.cargo_after = 24
	check(not owner.precredit_story33(bad) and owner.snapshot() == first, "A debit other than fifty crystals changed blueprint progress")
	bad = transaction.duplicate(true)
	bad.from_cursor = 34
	check(not owner.precredit_story33(bad) and owner.snapshot() == first, "A non-story33 transition changed blueprint progress")
	bad = transaction.duplicate(true)
	bad.binding_id = "wrong"
	check(not owner.precredit_story33(bad) and owner.snapshot() == first, "Another binding changed blueprint progress")
	var dropped: Dictionary = first.duplicate(true)
	dropped.entries.remove_at(10)
	check(not restored.restore(catalogues, bindings.binding_id, dropped) and restored.snapshot() == first, "A save missing item85 was silently accepted")
	var duplicate: Dictionary = first.duplicate(true)
	duplicate.entries[11] = duplicate.entries[10].duplicate(true)
	check(not restored.restore(catalogues, bindings.binding_id, duplicate) and restored.snapshot() == first, "A duplicate blueprint replaced another source entry")
	var partial: Dictionary = first.duplicate(true)
	partial.entries[10].remaining[0] = 20
	partial.entries[10].material_value = 12000
	partial.entries[10].available = true
	check(restored.restore(catalogues, bindings.binding_id, partial), restored.error)
	var partial_transaction: Dictionary = contract(partial, restored.entry(85), 52)
	check(restored.precredit_story33(partial_transaction), restored.error)
	check(restored.entry(85).remaining[0] == -30 and restored.entry(85).material_value == 32000, "Source material helper's full debit/value accounting was clamped")
	var partial_after: Dictionary = restored.snapshot()
	check(not restored.precredit_story33(partial_transaction) and restored.snapshot() == partial_after, "A stale partial-credit proposal was replayed")
	var reload := Blueprints.new()
	check(reload.restore(catalogues, bindings.binding_id, partial_after) and reload.snapshot() == partial_after, "Signed surplus progress failed save restoration")
	print("%s: %d source recipes, item85 crystal credit 50×400" % [label, first.entries.size()])


func verify_entry_boundaries(catalogues: RefCounted, binding_id: String, first: Dictionary, owner: RefCounted, restored: RefCounted) -> void:
	var bag := CatalogueBag.new()
	bag.content_id = catalogues.content_id
	bag.tables = catalogues.tables
	check(not Blueprints.new().configure(bag, binding_id), "An arbitrary RefCounted catalogue bag was accepted")
	check(not restored.restore(bag, binding_id, first) and restored.snapshot() == first, "An arbitrary RefCounted bag replaced restored progress")
	for malformed in ["short", "g".repeat(64), "A".repeat(64)]:
		check(not owner.configure(catalogues, malformed) and owner.snapshot() == first, "A malformed binding identity reset blueprint progress")
		check(not restored.restore(catalogues, malformed, first) and restored.snapshot() == first, "A malformed binding identity replaced restored progress")
	var invalid := Catalogues.new()
	invalid.tables = catalogues.tables
	invalid.content_id = "short"
	check(not Blueprints.new().configure(invalid, binding_id), "A malformed content identity configured blueprint progress")
	check(not restored.restore(invalid, binding_id, first) and restored.snapshot() == first, "A malformed content identity replaced restored progress")
	invalid.content_id = "g".repeat(64)
	check(not Blueprints.new().configure(invalid, binding_id), "A non-hex content identity configured blueprint progress")


func contract(state: Dictionary, expected: Dictionary, cargo_before: int) -> Dictionary:
	return {"base_content_id": state.base_content_id, "binding_id": state.binding_id,
		"from_cursor": 33, "to_cursor": 34, "item_id": 164,
		"cargo_before": cargo_before, "cargo_after": cargo_before - 50,
		"expected_entry": expected.duplicate(true)}


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: ", message)
