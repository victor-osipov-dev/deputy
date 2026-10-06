class_name TouchStick
extends Control
## Виртуальный джойстик. value — вектор [-1,1]. Показывается только на тачскринах.

var value := Vector2.ZERO
var radius := 95.0

var _touch := -1
var _center := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(radius * 2.0 + 20.0, radius * 2.0 + 20.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch < 0:
			_touch = event.index
			_center = event.position
			_update_knob(event.position)
			accept_event()
		elif not event.pressed and event.index == _touch:
			_touch = -1
			value = Vector2.ZERO
			queue_redraw()
			accept_event()
	elif event is InputEventScreenDrag and event.index == _touch:
		_update_knob(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_touch = -2
			_center = event.position
			_update_knob(event.position)
		else:
			_touch = -1
			value = Vector2.ZERO
			queue_redraw()
	elif event is InputEventMouseMotion and _touch == -2:
		_update_knob(event.position)


func _update_knob(p: Vector2) -> void:
	var d := p - _center
	if d.length() > radius:
		d = d.normalized() * radius
	value = d / radius
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	draw_circle(c, radius, Color(1, 1, 1, 0.10))
	draw_arc(c, radius, 0, TAU, 48, Color(1, 1, 1, 0.45), 3.0)
	draw_circle(c + value * radius * 0.55, 34.0, Color(1, 1, 1, 0.35))
