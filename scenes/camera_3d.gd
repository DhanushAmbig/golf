extends Camera3D

# Drag these in the Inspector, or use the path below
@export var target: NodePath

# Offset matches your current position: Y=1, Z=1 above/behind ball
@export var offset := Vector3(0, 1, 1)
@export var follow_speed := 8.0        # higher = snappier, lower = smoother lag

var _target_node: Node3D


func _ready() -> void:
	_target_node = get_node(target)


func _physics_process(delta: float) -> void:
	if _target_node == null:
		return

	var goal := _target_node.global_position + offset
	# Smoothly interpolate camera toward the ball
	global_position = global_position.lerp(goal, follow_speed * delta)
