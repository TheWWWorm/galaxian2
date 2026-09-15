extends "res://tests/free_lifecycle.gd"
## Render the verified ordinary deaths using their original faction assets.
const Rendering=preload("res://tests/fixtures/freighter_rendering.gd")
var frames:={}
var resources_by_faction:={}

func _initialize() -> void:
	create_timer(120).timeout.connect(func():push_error("Ordinary freighter rendering timed out");quit(1))
	call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size() in [3,4]:
		super.verify(args.slice(0,3))
		if not failures:
			for faction in [0,2]:
				# Original V4 AEM headers contain 14 Terran / 9 Nivelian pieces.
				await Rendering.new().verify(self,args,resources_by_faction[faction],frames[faction],"freighter-"+str(faction),14 if faction==0 else 9,1.35)
	else:check(false,"Expected content, bindings, visuals and optional capture directory")
	print("Ordinary freighter destruction rendering: %d checks; %d failures"%[checks,failures])
	quit(1 if failures else 0)

func observe_ordinary_death(resources: RefCounted,death: RefCounted,label: String) -> void:
	var faction: int=death.snapshot().actor_kind
	if not frames.has(faction):frames[faction]=[];resources_by_faction[faction]=resources
	frames[faction].append({"label":label,"owner":death.fork_for_frame()})
