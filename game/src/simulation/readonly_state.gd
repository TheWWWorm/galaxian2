extends RefCounted
## Retained frame observations can share containers only after every nested
## dictionary and array is read-only. Public editable snapshots still duplicate.
static func freeze(value: Variant) -> Variant:
	if value is Dictionary:
		if value.is_read_only():return value
		for child in value.values():
			if child is Dictionary or child is Array:freeze(child)
		value.make_read_only()
	elif value is Array:
		if value.is_read_only():return value
		for child in value:
			if child is Dictionary or child is Array:freeze(child)
		value.make_read_only()
	return value
