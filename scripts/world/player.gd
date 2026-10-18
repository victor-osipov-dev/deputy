class_name WorldPlayer
extends CharacterBody2D
## Депутат на карте. WASD/стрелки + виртуальный джойстик (joy выставляет UI).

const SPEED := 230.0

var frozen := false
var joy := Vector2.ZERO
var step_phase := 0.0

var body: Sprite2D
var shade: Polygon2D


func _ready() -> void:
	add_to_group("player")
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 14.0
	shape.shape = circle
	add_child(shape)
	shade = Polygon2D.new()
	shade.polygon = PackedVector2Array([Vector2(-14, 10), Vector2(14, 10), Vector2(10, 16), Vector2(-10, 16)])
	shade.color = Color(0, 0, 0, 0.35)
	add_child(shade)
	body = Tex.spr(Tex.char_for("player"), 3.0)
	body.position = Vector2(0, -32)
	add_child(body)
	var sensor := Area2D.new()
	sensor.name = "Sensor"
	var ss := CollisionShape2D.new()
	var sc := CircleShape2D.new()
	sc.radius = 95.0
	ss.shape = sc
	sensor.add_child(ss)
	add_child(sensor)
	var cam := Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 6.0
	cam.enabled = true
	add_child(cam)


func sensor() -> Area2D:
	return $Sensor


func _physics_process(_delta: float) -> void:
	if frozen:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir.length() < 0.1 and joy.length() > 0.1:
		dir = joy.limit_length(1.0)
	velocity = dir * SPEED
	move_and_slide()
	# лёгкое покачивание при ходьбе
	if velocity.length() > 10.0:
		step_phase += _delta * 10.0
		body.position.y = -34.0 + abs(sin(step_phase)) * -4.0
	else:
		body.position.y = -34.0


func is_moving() -> bool:
	return velocity.length() > 20.0
