extends "res://tests/station_equipment.gd"
## Finish the equipment tutorial with the standard starter gun mounted and the
## alternate gun kept in cargo, as a player may choose in the original hangar.

func choose_starter_gun(state: Dictionary) -> Dictionary:
	check(host.equipment_action("unmount",22) and host.equipment_action("mount",0),host.session.error)
	var next: Dictionary=host.session.snapshot()
	check(next.loadout.equipment_ids.has(0) and not next.loadout.equipment_ids.has(22) and next.equipment.requirements.satisfied and next.cargo.entries==[{"item_id":22,"quantity":1}],"The standard starter gun could not replace the alternate gun")
	return next

func scenario_transactions() -> Array:return EquipmentScenario.STANDARD_GUN_TRANSACTIONS
