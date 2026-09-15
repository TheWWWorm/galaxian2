extends "res://tests/freighter_destruction.gd"
## Original-art GPU fixture. The isolated lifecycle supplies all displayed state;
## the camera and lighting are explicit test settings, not location fidelity.
var stages:=[]
var selected_identity: RefCounted

func _initialize() -> void:
	create_timer(90).timeout.connect(func():push_error("Freighter rendering timed out");quit(1))
	call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size() in [3,4]:
		super.verify(args.slice(0,3))
		if not failures:await render_stages(args)
	else:check(false,"Expected content, bindings, visuals and optional captures")
	print("Freighter destruction geometry: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func observe_lifecycle(death: RefCounted,label: String) -> void:
	if selected_identity==null and label=="entry" and death.snapshot().cargo.eligible:selected_identity=death.presentation_identity()
	if death.presentation_identity()==selected_identity:stages.append({"label":label,"owner":death.fork_for_frame()})

func render_stages(args: PackedStringArray) -> void:
	await preload("res://tests/fixtures/freighter_rendering.gd").new().verify(self,args,death_resources,stages,"freighter",15)
