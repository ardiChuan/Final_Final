extends CharacterBody2D

# --- Movement Stat ---
const SPEED := 350.0
const ACCEL := 1200.0
const DECEL := 1800.0

# --- Attack Stat ---
var damage : int = 5
var attack_timer := 0.0
var attack_duration := 0.2
var is_attacking := false

@onready var visual			: ColorRect = $ColorRect
@onready var camera 		: Camera2D	= $Camera2D
@onready var hitbox			: Area2D 	= $Area2D
@onready var weapon_visual 	: ColorRect = $WeaponRect

func _physics_process(delta):
	var input_dir := get_input_directon()
	update_velocity(input_dir,delta)
	move_and_slide()
	handle_attack(delta)

func get_input_directon() -> Vector2: 	
	var direction := Input.get_vector("move_left","move_right","move_up","move_down")
	return direction.normalized() if direction.length() > 1 else direction

func update_velocity(direction:Vector2, delta : float) -> void: 
	if direction != Vector2.ZERO:
		var target_velocity = direction * SPEED
		velocity = velocity.move_toward(target_velocity, ACCEL * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, DECEL * delta)

func handle_attack(delta: float) -> void:
	# Cooldown timer
	if attack_timer > 0:
		attack_timer -= delta
	if attack_timer <= 0:
		end_attack()
	
	# Attack input
	if Input.is_action_just_pressed("attack") and not is_attacking:
		start_attack()

func start_attack() -> void:
	is_attacking = true
	attack_timer = attack_duration
	weapon_visual.visible = true
	hitbox.monitoring = true

func end_attack() -> void:
	is_attacking = false
	weapon_visual.visible = false
	hitbox.monitoring = false

func _on_hitbox_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage"):
		body.take_damage(damage)
		apply_hitstop()
		shake_camera()
		spawn_hit_particle(body.global_position)

func apply_hitstop() -> void:
	Engine.time_scale = 0.1
	await get_tree().create_timer(0.05, true, false, true).timeout
	Engine.time_scale = 1.0

func shake_camera(intensity: float = 5.0) -> void:
	var original_offset = camera.offset
	camera.offset = Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
	await get_tree().create_timer(0.1).timeout
	camera.offset = original_offset

func spawn_hit_particle(pos: Vector2) -> void:
	for i in range(5):
		var particle = ColorRect.new()
		particle.size = Vector2(4, 4)
		particle.color = Color.YELLOW
		get_tree().root.add_child(particle)
		particle.global_position = pos + Vector2(randf_range(-10, 10), randf_range(-10, 10))
		
		var tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(particle, "position", particle.position + Vector2(randf_range(-30, 30), randf_range(-30, 30)), 0.4)
		tween.tween_property(particle, "modulate:a", 0.0, 0.4)
		await tween.finished
		particle.queue_free()
