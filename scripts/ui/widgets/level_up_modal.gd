class_name LevelUpModal
extends Control
## The level-up party: a jingle, confetti, and a card with the new level, Kuiz's title and the crystals
## it paid. LevelUpModal.open(host, from_level, level). Its look is level_up_modal.tscn; this fills the
## text and runs the show. Contract: docs/ui-and-assets.md §2 Pop-ups.

const SCENE := "res://scenes/ui/widgets/level_up_modal.tscn"
const JINGLE: AudioStream = preload("res://assets/audio/sfx/sfx_level_up.wav")
const DIM := 0.45
# The number ticks over as the jingle's bell chord lands.
const LAND_AT := 0.45

@onready var _dim: ColorRect = %Dim
@onready var _card: PanelContainer = %Card
@onready var _badge: PanelContainer = %Badge
var _closing := false

## Shows the party over `host` (a screen's top layer).
static func open(host: Node, from_level: int, level: int) -> Control:
	var m: LevelUpModal = (load(SCENE) as PackedScene).instantiate()
	host.add_child(m)
	m._fill(from_level, level)
	return m

func _fill(from_level: int, level: int) -> void:
	%Number.text = str(from_level)
	%Rank.text = CompanionState.rank(level)
	%NewTitle.visible = CompanionState.rank(level) != CompanionState.rank(from_level)
	%Reward.text = "+%d crystals" % (CompanionState.LEVEL_CRYSTALS * (level - from_level))
	%Yay.pressed.connect(_close)
	%Yay.grab_focus()
	_card.modulate.a = 0.0
	_card.scale = Vector2.ONE * 0.4
	_pop_in.call_deferred(level)

func _pop_in(level: int) -> void:
	var view := get_viewport_rect().size
	var rain: CPUParticles2D = %Rain
	rain.position = Vector2(view.x / 2.0, -24.0)
	rain.emission_rect_extents.x = view.x / 2.0
	rain.restart()
	MusicManager.play_sfx_layered(JINGLE)
	_card.pivot_offset = _card.size / 2.0
	var t := create_tween().set_parallel().set_ignore_time_scale(true)
	t.tween_property(_dim, "color:a", DIM, 0.2)
	t.tween_property(_card, "modulate:a", 1.0, 0.15)
	t.tween_property(_card, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var land := create_tween().set_ignore_time_scale(true)
	land.tween_interval(LAND_AT)
	land.tween_callback(_land.bind(level))

# The new level lands: the badge pops, confetti bursts out of it, then it breathes until closed.
func _land(level: int) -> void:
	%Number.text = str(level)
	var burst: CPUParticles2D = %Burst
	burst.global_position = _badge.get_global_rect().get_center()
	burst.restart()
	_badge.pivot_offset = _badge.size / 2.0
	var t := create_tween().set_ignore_time_scale(true)
	t.tween_property(_badge, "scale", Vector2.ONE * 1.25, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_badge, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_SINE)
	t.tween_callback(_breathe)

func _breathe() -> void:
	var pulse := create_tween().set_loops().set_ignore_time_scale(true)
	pulse.tween_property(_badge, "scale", Vector2.ONE * 1.06, 0.6).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_badge, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)

func _close() -> void:
	if _closing:
		return
	_closing = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := create_tween().set_parallel().set_ignore_time_scale(true)
	t.tween_property(_dim, "color:a", 0.0, 0.18)
	t.tween_property(_card, "modulate:a", 0.0, 0.18)
	t.tween_property(_card, "scale", Vector2.ONE * 0.9, 0.18)
	await t.finished
	queue_free()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
