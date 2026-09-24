extends SceneTree
## Reuse decoded source PCM only after each audio owner revalidates its bank.
const Library=preload("res://src/content/library.gd")
const Bindings=preload("res://src/content/resource_bindings.gd")
const Resources=preload("res://src/content/audio_resources.gd")
var checks:=0
var failures:=0

func _initialize() -> void:call_deferred("run")

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2:check(false,"Expected content and bindings directories");finish();return
	var library:=Library.new();var bindings:=Bindings.new()
	check(library.open(args[0]) and bindings.open(args[1],library.manifest),library.error+bindings.error)
	if failures:finish();return
	var first:=Resources.new()
	check(first.configure(library,bindings),first.error)
	var clip: Dictionary=first.prepare(1) if not failures else {}
	check(not clip.is_empty() and not clip.has("unsupported"),first.error)
	if failures:finish();return
	var sample: Dictionary=clip.layers[0][0].definition.samples[0]
	var original: PackedByteArray=sample.stream.data
	var cached:=library.cached_audio_pcm(sample.source_bank,int(sample.source_index),original.size())
	check(library.cached_audio_pcm_bytes()>0 and cached==original,"Decoded IMA sample was not cached by its open content library")
	if failures:finish();return
	cached[0]=cached[0]^1
	check(library.cached_audio_pcm(sample.source_bank,int(sample.source_index),original.size())==original,"Cache handed out mutable stored PCM")
	var second:=Resources.new()
	check(second.configure(library,bindings),second.error)
	var again: Dictionary=second.prepare(1) if not failures else {}
	check(not again.is_empty() and again.layers[0][0].definition.samples[0].stream.data==original,"A second audio owner changed the original decoded sample")
	var changed_stream: AudioStreamWAV=again.layers[0][0].definition.samples[0].stream
	var changed_data: PackedByteArray=changed_stream.data.duplicate()
	changed_data[0]=changed_data[0]^1;changed_stream.data=changed_data
	check(library.cached_audio_pcm(sample.source_bank,int(sample.source_index),original.size())==original,"Changing a playback stream poisoned cached PCM")
	var bytes_cached:=library.cached_audio_pcm_bytes()
	print("Audio PCM cache: ",bytes_cached," bytes")
	var original_root: String=library.root
	library.root="user://audio-cache-missing-%d"%OS.get_process_id()
	var missing:=Resources.new()
	check(missing.configure(library,bindings),missing.error)
	check(missing.prepare(1).is_empty() and not missing.error.is_empty(),"Cached PCM masked a missing source bank")
	library.root=original_root
	var retried:=Resources.new()
	check(retried.configure(library,bindings),retried.error)
	check(not retried.prepare(1).is_empty(),"A failed bank read blocked retry after restoring the source")
	check(library.open(args[0]) and library.cached_audio_pcm_bytes()==0,"Reopening content retained decoded PCM")
	var fresh:=Resources.new()
	check(fresh.configure(library,bindings) and not fresh.prepare(1).is_empty() and library.cached_audio_pcm_bytes()>0,"Reopened content could not rebuild the PCM cache")
	check(not library.open("relative-path") and library.cached_audio_pcm_bytes()==0,"A failed content open retained earlier PCM")
	finish()

func check(value: bool,message: String) -> void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish() -> void:
	print("Audio PCM cache: %d checks; %d failures"%[checks,failures]);quit(1 if failures else 0)
