extends SceneTree
## Validate an earned prerequisite before scheduling dependent component checks.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Catalogues=preload("res://src/content/catalogues.gd")
const Scenario=preload("res://tests/fixtures/equipment_scenario.gd")

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	var library:=Library.new();var bindings:=Bindings.new();var catalogues:=Catalogues.new();var scenario:=Scenario.new()
	var error:=""
	if args.size()<2:error="Expected content and binding paths"
	elif not library.open(args[0]) or not bindings.open(args[1],library.manifest) or not catalogues.open(library):error=library.error+bindings.error+catalogues.error
	elif scenario.open(OS.get_environment("GOF2_SCENARIO_INPUT"),bindings,catalogues)==null:error=scenario.error
	if not error.is_empty():printerr("FAIL ",error)
	print("Scenario prerequisite: 1 checks; %d failures"%[0 if error.is_empty() else 1])
	quit(0 if error.is_empty() else 1)
