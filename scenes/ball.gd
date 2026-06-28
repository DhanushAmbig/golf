extends RigidBody3D

# --- Config ---
const MAX_DRAG_DISTANCE := 4.0   # world units, clamps power
const SHOT_POWER        := 8.0  # multiplier for launch force

var _launch_velocity := Vector3.ZERO
var _apply_launch := false

# --- State ---
enum State { IDLE, DRAGGING, LAUNCHED }
var state: State = State.IDLE

var drag_start: Vector3 = Vector3.ZERO  # world pos where drag began
var drag_current: Vector3 = Vector3.ZERO

# Line drawing (ImmediateMesh for the aim line)
var line_mesh_instance: MeshInstance3D
var line_mesh: ImmediateMesh

var settle_timer: float = 0.0

# Top of script — replace all fall-related vars with these
const COURSE_Y        :=  0.0    # your course sits at Y=0 from debug output
const FALL_THRESHOLD  := -0.1    # anything below -0.1 means off course
var fall_timer        := 0.0
var is_falling        := false
var last_valid_position := Vector3.ZERO

func _ready() -> void:
	last_valid_position = global_position   # add this line
	# DO NOT freeze here — let ball sit on ground via physics
	# Just make sure gravity does its job
	line_mesh = ImmediateMesh.new()
	line_mesh_instance = MeshInstance3D.new()
	line_mesh_instance.mesh = line_mesh
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.RED
	mat.no_depth_test = true
	line_mesh_instance.material_override = mat
	get_parent().add_child(line_mesh_instance)
	line_mesh_instance.visible = false

func _is_on_course() -> bool:
	# Cast a short ray downward from ball — if it hits something it's on course
	var query := PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3(0, -0.5, 0)   # 0.5 units down
	)
	query.exclude = [self]   # ignore the ball itself
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	return not result.is_empty()

func _input(event: InputEvent) -> void:
	match state:
		State.IDLE:
			_handle_idle_input(event)
		State.DRAGGING:
			_handle_drag_input(event)

func _physics_process(delta: float) -> void:
	if state == State.DRAGGING:
		_update_aim_line()

	if _apply_launch:
		linear_velocity = _launch_velocity
		_apply_launch = false

	if state == State.LAUNCHED:

		if not is_falling:
			if global_position.y >= FALL_THRESHOLD:
				# Ball is on course — keep saving valid position
				last_valid_position = global_position
				linear_velocity.y = 0.0    # only lock Y when on course
			else:
				# Ball went below -0.1 — fell off course
				is_falling = true
				fall_timer = 0.0
				print("FELL — will reposition to: ", last_valid_position)

		if is_falling:
			fall_timer += delta
			if fall_timer >= 2.0:
				_reposition_ball()
			return

		settle_timer += delta
		if settle_timer > 0.3 and linear_velocity.length() < 0.15:
			_reset_to_idle()
			settle_timer = 0.0

func _reposition_ball() -> void:
	global_position = last_valid_position + Vector3(0, 0.5, 0)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	fall_timer = 0.0
	is_falling = false
	settle_timer = 0.0
	state = State.IDLE
	line_mesh_instance.visible = false
	print("REPOSITIONED to: ", global_position)
	
func _create_ground_plane() -> void:
	var ground := StaticBody3D.new()
	add_child(ground)
	ground.global_position.y = -10.0    # far below course
	var col := CollisionShape3D.new()
	ground.add_child(col)
	var shape := WorldBoundaryShape3D.new()
	col.shape = shape
		

# ─── IDLE ────────────────────────────────────────────────────────────────────

func _handle_idle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Raycast from camera to see if we clicked THIS ball
			var hit = _raycast_from_mouse(event.position)
			if hit == self:
				drag_start = global_position     # anchor drag to ball position
				drag_current = drag_start
				state = State.DRAGGING
				line_mesh_instance.visible = true


# ─── DRAGGING ────────────────────────────────────────────────────────────────

func _handle_drag_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# Project mouse onto the Y-plane at ball height
		drag_current = _mouse_to_world_plane(event.position)

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_launch()
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_reset_to_idle()       # cancel shot


func _update_aim_line() -> void:
	var direction := drag_start - drag_current          # backward drag → forward shot
	if direction.length() > MAX_DRAG_DISTANCE:
		direction = direction.normalized() * MAX_DRAG_DISTANCE

	var ball_pos := global_position
	var target   := ball_pos + direction                # where ball will go

	line_mesh.clear_surfaces()
	line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	line_mesh.surface_add_vertex(ball_pos)
	line_mesh.surface_add_vertex(target)
	line_mesh.surface_end()


# ─── LAUNCH ──────────────────────────────────────────────────────────────────

func _launch() -> void:
	settle_timer = 0.0

	var direction := drag_start - drag_current
	# Clamp by length, not per-axis — keeps direction accurate
	if direction.length() > MAX_DRAG_DISTANCE:
		direction = direction.normalized() * MAX_DRAG_DISTANCE

	freeze = false

	var shot := direction * SHOT_POWER
	shot.y = 0.0

	_launch_velocity = shot
	_apply_launch = true

	line_mesh_instance.visible = false
	state = State.LAUNCHED


func _reset_to_idle() -> void:
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_apply_launch = false
	_launch_velocity = Vector3.ZERO
	fall_timer = 0.0
	is_falling = false
	state = State.IDLE
	line_mesh_instance.visible = false


# ─── HELPERS ─────────────────────────────────────────────────────────────────

func _raycast_from_mouse(mouse_pos: Vector2) -> Object:
	var camera := get_viewport().get_camera_3d()
	var from   := camera.project_ray_origin(mouse_pos)
	var to     := from + camera.project_ray_normal(mouse_pos) * 1000.0

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = []
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	return result.get("collider")   # returns null if nothing hit


func _mouse_to_world_plane(mouse_pos: Vector2) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	var from   := camera.project_ray_origin(mouse_pos)
	var dir    := camera.project_ray_normal(mouse_pos)
	var plane  := Plane(Vector3.UP, global_position.y)
	var hit: Variant = plane.intersects_ray(from, dir)
	return hit if hit != null else global_position
