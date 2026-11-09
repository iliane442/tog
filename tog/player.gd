extends CharacterBody2D

@export var speed: float = 300.0

var target: Vector2

func _ready() -> void:
	target = global_position

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		target = get_global_mouse_position()

func _physics_process(delta: float) -> void:
	var direction = target - global_position
	if direction.length() > 5.0:
		velocity = direction.normalized() * speed
	else:
		velocity = Vector2.ZERO
	move_and_slide()
