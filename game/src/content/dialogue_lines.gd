extends RefCounted
## Resolve imported story events for the current language and input labels.
var error:=""

func read(bindings: RefCounted,library: RefCounted,events: Array,substitutions: Dictionary={}) -> Array:
	error=""
	if bindings==null or library==null or library.manifest.get("content_id")!=bindings.base_content_id:
		return reject("Dialogue belongs to another content pack")
	# Match complete input tokens once. Repeated String.replace calls corrupt
	# overlapping names such as SECONDARY and SECONDARY_WEAPONS, including
	# when the longer token has no supplied binding.
	var tokens:=RegEx.new()
	if tokens.compile("#KEY_[A-Z0-9_]+")!=OK:return reject("Input token matcher is unavailable")
	for token in substitutions:
		var label: Variant=substitutions[token]
		if not token is String or not label is String or label.is_empty() or label.length()>64 or "#" in label or "\n" in label or "\r" in label:return reject("Invalid dialogue input label")
	var lines:=[]
	for event in events:
		if not event is Dictionary or not event.has_all(["speaker_id","text_id","voice_event_id"]):return reject("Incomplete dialogue event")
		var id:=int(event.text_id)
		var desktop_id: int=bindings.desktop_text_id(id)
		if desktop_id<0:return reject(bindings.error)
		var texts:=[]
		for text_id in [id,desktop_id]:
			if text_id<0 or text_id>=library.strings.size() or not library.strings[text_id] is String or library.strings[text_id].is_empty():return reject("Dialogue text is unavailable in this language")
			var source: String=library.strings[text_id]
			var text:="";var offset:=0
			for matched in tokens.search_all(source):
				var token: String=matched.get_string()
				if not substitutions.has(token):return reject("Dialogue requires an unsupported input label: "+token)
				text+=source.substr(offset,matched.get_start()-offset)+substitutions[token]
				offset=matched.get_end()
			text+=source.substr(offset)
			if "#KEY_" in text:return reject("Dialogue requires an unsupported input label")
			texts.append(text)
		var speaker: String=bindings.resolve_speaker_name(int(event.speaker_id),library)
		if not bindings.error.is_empty():return reject(bindings.error)
		lines.append({"speaker_id":int(event.speaker_id),"speaker_name":speaker,"text_id":id,"text":texts[0],
			"desktop_text_id":desktop_id,"desktop_text":texts[1],"voice_event_id":int(event.voice_event_id)})
	return lines

func reject(message: String) -> Array:
	error=message
	return []
