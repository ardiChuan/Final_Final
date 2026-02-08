extends CharacterBody2D

# --- Movement Stat ---
const SPEED 							:= 315.0
const ACCEL 							:= 2750.0
const DECEL 							:= 1500.0

# --- Attack System ---
enum AttackType 						{NONE, LIGHT, HEAVY}
var current_attack 						:= AttackType.NONE
var combo_count 						:= 0 
var max_combo 							:= 3
var buffered_input						:= AttackType.NONE
var is_attacking						:= false

# --- Light Attack Stat ---
var light_attack_duration				:= 0.31
var light_attack_damage 				:= 500
var light_combo_window 					:= 0.35

# --- Heavy Attack Stat ---
var heavy_attack_duration 				:= 0.65
var heavy_attack_damage 				:= 3000
var heavy_charge_time 					:= 0.3

# --- Dodge Roll Mechanism ---
var is_dodging := false
var dodge_duration := 0.4
var dodge_speed := 500.0
var dodge_cooldown_time := 1.5
var dodge_cooldown := 0.0
var dodge_distance := 120.0
var dodge_travelled := 0.0
var dodge_direction := Vector2.ZERO
var iframe_duration := 0.3
var is_invulnerable := false

# --- Block Mechanism ---
var is_blocking := false
var block_damage_reduction := 0.6

# --- Parry Mecanism --- 
var parry_window := 0.2
var parry_timer := 0.0
var is_parrying := false

# --- Timer ---
var attack_timer 						:= 0.0
var combo_timer 						:= 0.0

# --- Cooldown ---
var combo_finisher_cooldown 			:= 0.9
var is_recovering 						:= false 

@onready var camera 		: Camera2D	= $Camera2D
@onready var visuals		: Node2D	= $Visuals
@onready var visual			: ColorRect = $Visuals/ColorRect
@onready var hitbox			: Area2D 	= $Visuals/Area2D



# --- MAIN CORE LOOP ---
func _ready():
	hitbox.monitoring = false


func _physics_process(delta):
	var input_dir := get_input_directon()
	update_facing(input_dir)
	update_timers(delta)
	handle_defense_input()
	handle_movement(input_dir, delta)
	handle_attack_input()
	update_attack(delta)

func update_timers(delta : float) -> void:
	# Dodge Cooldown 
	if dodge_cooldown > 0 :
		dodge_cooldown -= delta
	# Parry Window
	if parry_timer > 0 :
		parry_timer -= delta
		if parry_timer <= 0 :
			end_parry()
	#Combo window 
	if combo_timer > 0 and not is_attacking:
		combo_timer -= delta
		if combo_timer <= 0 :
			combo_count = 0



# --- Movement Function ---
func get_input_directon() -> Vector2: 	
	var direction := Input.get_vector("move_left","move_right","move_up","move_down")
	return direction.normalized() if direction.length() > 1 else direction

func handle_movement(input_dir : Vector2, delta: float) -> void :
	if is_dodging :
		var step = dodge_speed * delta
		dodge_travelled += step
		if dodge_travelled >= dodge_distance:
			is_dodging = false
			is_invulnerable = false
			dodge_travelled = 0.0 
		else:
			velocity = dodge_direction * dodge_speed
	elif is_blocking : 
		velocity = Vector2.ZERO
	elif not is_attacking:
		update_movement(input_dir, delta)
	else : 
		update_movement(Vector2.ZERO, delta) 
	move_and_slide()

func update_movement(direction:Vector2, delta : float) -> void: 
	if direction != Vector2.ZERO:
		var target_velocity = direction * SPEED
		velocity = velocity.move_toward(target_velocity, ACCEL * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, DECEL * delta)


var facing: int = 1  # 1 = right, -1 = left

func update_facing(input_dir: Vector2) -> void:
	if input_dir.x == 0:
		return

	var new_facing: int = sign(input_dir.x)
	if new_facing == facing:
		return

	facing = new_facing
	visuals.scale.x = facing



# --- Defense Function ---
func handle_defense_input() -> void :
	#Dodge
	if Input.is_action_just_pressed("dodge") and can_dodge():
		if velocity.length() > 0 :
			var dodge_dir = velocity.normalized() 
			start_dodge(dodge_dir)
	#Parry 
	if Input.is_action_just_pressed("block") and can_parry() :
		start_parry()
	#Block
	if not is_parrying : 
		is_blocking = Input.is_action_pressed("block") and can_block

func can_dodge() -> bool :
	return not is_dodging and not is_attacking and dodge_cooldown <= 0 

func start_dodge(direction: Vector2 ) -> void :
	is_dodging = true
	is_invulnerable = true 
	dodge_direction = direction.normalized()
	dodge_travelled = 0.0
	dodge_cooldown = dodge_cooldown_time

func can_block() -> bool :
	return not is_attacking and not is_dodging 

func can_parry() -> bool :
	return not is_attacking and not is_dodging and not is_parrying 

func start_parry() -> void :
	is_parrying = true
	parry_timer = parry_window

func end_parry() : 
	is_parrying = false 

func take_damage(amount : int) -> void : 
	if is_invulnerable : 
		return 
	if is_parrying :
		parry_success()
		return
	var final_damage = amount 
	if is_blocking : 
		final_damage = int(amount * (1.0 - block_damage_reduction))

func parry_success() -> void : 
	apply_hitstop(0.15) 
	shake_camera(10.0)



# --- Attack Function ---
func handle_attack_input() -> void :
	if Input.is_action_just_pressed('light_attack'):
		if is_attacking :
			buffered_input = AttackType.LIGHT
		else :
			start_light_attack()
	if Input.is_action_just_pressed('heavy_attack'):
		if not is_attacking : 
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
	if not is_attacking :
		return 
	attack_timer -= delta
	if attack_timer <= 0 :
		end_attack()

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
	
	# Execute buffered input for light attack 
	if buffered_input != AttackType.NONE and not is_recovering:
		buffered_input = AttackType.NONE
		start_light_attack()

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


# --- Effects
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
