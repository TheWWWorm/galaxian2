extends RefCounted

static func definition() -> Dictionary:
	return {"initial_milliseconds":1001,"refresh_at_milliseconds":1001,"reset_milliseconds":0,
		"time_unit":"milliseconds","forced_refresh_resets_clock":false,
		"provenance":{"initial":{"offset":8000,"bytes":11},"batch":{"offset":8100,"bytes":222},"tick":{"offset":8322,"bytes":35}}}
