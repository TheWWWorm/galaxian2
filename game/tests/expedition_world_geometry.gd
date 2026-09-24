extends "res://tests/ordinary_world_geometry.gd"
## Detached source-world renders; no Thynome travel or Dima story progression.
const Expedition=preload("res://src/content/thynome_expedition_definitions.gd")

func geometry_specs() -> Array:
	return [
		{"station_id":30,"system_id":2,"planet_count":4,"hangar_row":2,"gate":true},
		{"station_id":90,"system_id":18,"planet_count":5,"hangar_row":0,"gate":true},
		{"station_id":91,"system_id":18,"planet_count":5,"hangar_row":0,"gate":false},
	]

func geometry_cursor() -> int:return 27
func geometry_name(station: int) -> String:return "expedition-%d"%station
func geometry_available(bindings: RefCounted) -> bool:return super.geometry_available(bindings) and Expedition.available(bindings)
