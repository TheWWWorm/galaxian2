extends Control
## Kill score combo rows (Supernova Challenge). The score itself is in the
## top-right counter plate (flight vitals, readout "score"), left of the pause
## button and clear of the target panel; these rows hang under that plate:
## while a combo window runs with a combo above 1, "x N", larger for the first
## 500 ms after a kill; in the window's last 3 s the row blinks (100 ms) and
## shows the pending combo bonus.
const POP_MS:=500
const BLINK_FROM_MS:=3000
const BLINK_MS:=100
var _column: VBoxContainer
var _combo: Label
var _bonus: Label
var _window_ms:=7500
var _mobile:=false

func _init() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_column=VBoxContainer.new();_column.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_column.alignment=BoxContainer.ALIGNMENT_BEGIN
	add_child(_column)
	_combo=_label(Color.WHITE);_bonus=_label(Color.WHITE)
	for label in [_combo,_bonus]:_column.add_child(label)
	visible=false

func _label(color: Color) -> Label:
	var label:=Label.new();label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color",color)
	label.add_theme_color_override("font_outline_color",Color(0,0,0,0.85));label.add_theme_constant_override("outline_size",4)
	return label

func configure(font: Font,window_ms: int,mobile: bool) -> void:
	var look:=Theme.new();look.default_font=font;theme=look
	_window_ms=window_ms;_mobile=mobile

## `readout`: the flight snapshot's kill_score, or {} to hide. `plate`: the
## counter plate's global rect; the rows are centred under it.
func present(readout: Dictionary,plate: Rect2) -> void:
	visible=not readout.is_empty()
	if not visible:return
	var size:=26 if _mobile else 18
	var combo:=int(readout.get("combo",0))
	var clock:=int(readout.get("combo_clock_ms",0))
	var shown:=combo>1
	var blinking:=shown and clock<BLINK_FROM_MS
	_combo.visible=shown and (not blinking or (clock/BLINK_MS)%2==0)
	_combo.text="x %d"%combo
	_combo.add_theme_font_size_override("font_size",int(size*(1.4 if _window_ms-clock<POP_MS else 1.0)))
	_bonus.visible=blinking;_bonus.text=str(int(readout.get("pending_bonus",0)))
	_bonus.add_theme_font_size_override("font_size",int(size*0.8))
	_column.size=Vector2(maxf(plate.size.x,1.0),0.0)
	_column.global_position=Vector2(plate.position.x,plate.end.y+4.0)
