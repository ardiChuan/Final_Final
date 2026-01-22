extends CharacterBody2D

# --- Movement Stat ---
const SPEED 							:= 315.0
const ACCEL 							:= 200.0
const DECEL 							:= 1500.0

# --- Attack System ---
enum AttackType 						{NONE, LIGHT, HEAVY}
var current_attack 						:= AttackType.NONE
var combo_count 						:= 0 
var max_combo 							:= 3
var buffered_input						:= AttackType.NONE
var is_attacking						:= false

# --- Light Attack Stat ---
var light_attack_duration				:= 0.2
var light_attack_damage 				:= 500
var light_combo_window 					:= 0.3

# --- Heavy Attack Stat ---
var heavy_attack_duration 				:= 0.6
var heavy_attack_damage 				:= 3000
var heavy_charge_time 					:= 0.3

# --- Timer ---
var attack_timer 						:= 0.0
var combo_timer 						:= 0.0

# --- Cooldown ---
var combo_finisher_cooldown 			:= 1
var is_recovering 						:= false 

@onready var visual			: ColorRect = $ColorRect
@onready var camera 		: Camera2D	= $Camera2D
@onready var hitbox			: Area2D 	= $Area2D

func _physics_process(delta):
	var input_dir := get_input_directon()
	if not is_attacking:
		update_velocity(input_dir,delta)
	else :
		update_velocity(Vector2.ZERO,delta)
	move_and_slide()
	handle_attack_input()
	update_attack(delta)

func get_input_directon() -> Vector2: 	
	var direction := Input.get_vector("move_left","move_right","move_up","move_down")
	return direction.normalized() if direction.length() > 1 else direction

func update_velocity(direction:Vector2, delta : float) -> void: 
	if direction != Vector2.ZERO:
		var target_velocity = direction * SPEED
		velocity = velocity.move_toward(target_velocity, ACCEL * SPEED)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, DECEL * delta)

func handle_attack_input() -> void :
	if Input.is_action_just_pressed('attack'):
		if is_attacking :
			buffered_input = AttackType.LIGHT
		else :
			start_light_attack()
	if Input.is_action_just_pressed('heavy_attack'):
		if is_attacking :
			buffered_input = AttackType.HEAVY
		else :
			start_heavy_attack()

func start_light_attack() -> void :
	if is_recovering :
		return 
	is_attacking = true
	current_attack = AttackType.LIGHT
	combo_count += 1
	if combo_count	> max_combo :
		combo_count = 1
	
	attack_timer = light_attack_duration
	if combo_count == max_combo:
		combo_timer = 0.0
	else :
		combo_timer = light_combo_window

	hitbox.monitoring = true 

func start_heavy_attack() -> void :
	if is_recovering :
		return
	is_attacking = true
	current_attack = AttackType.HEAVY
	combo_count = 0 
	combo_timer = 0.0
	attack_timer = heavy_attack_duration
	hitbox.monitoring = true

func update_attack(delta: float) -> void :
	if attack_timer > 0 :
		attack_timer -= delta
	if attack_timer <= 0 :
		end_attack()
			
	if combo_timer > 0 and not is_attacking:
		combo_timer -= delta
		if combo_timer <= 0 :
			combo_count = 0

func end_attack() -> void:
	is_attacking = false
	hitbox.monitoring = false
	
	
	# Recovery after 3rd light combo hit OR after heavy attack
	if combo_count == max_combo :
		is_recovering = true
		combo_count = 0
		visual.color = Color.ORANGE
		buffered_input = AttackType.NONE
		
		await get_tree().create_timer(combo_finisher_cooldown).timeout
		is_recovering = false
		visual.color = Color.BLUE
		return
	
	# Execute buffered input
	if buffered_input != AttackType.NONE and not is_recovering:
		var buffered = buffered_input
		buffered_input = AttackType.NONE
		
		if buffered == AttackType.LIGHT:
			start_light_attack()
		elif buffered == AttackType.HEAVY:
			start_heavy_attack()

func _on_hitbox_body_entered(body: Node2D) -> void:
	if body.has_method("take_damage"):
		var damage = light_attack_damage if current_attack == AttackType.LIGHT else heavy_attack_damage
		body.take_damage(damage)
		
		if current_attack == AttackType.HEAVY :
			apply_hitstop(0.1)
			shake_camera(8.0)
		else : 
			apply_hitstop(0.05)
			shake_camera(5.0)
		spawn_hit_particle(body.global_position)

func apply_hitstop(duration : float = 0.05) -> void:
	Engine.time_scale = 0.1
	await get_tree().create_timer(duration, true, false, true).timeout
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
