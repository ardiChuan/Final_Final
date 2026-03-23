extends CharacterBody2D

# ============ REFERENCES ============
@onready var sprite = $Sprite2D
@onready var anim = $AnimationPlayer
@onready var state_label = $StateLabel  # DEBUG - optional
@onready var hitbox = $HitBox

var player: CharacterBody2D = null

# ============ STATS ============
const MAX_HP = 100000
var current_hp = MAX_HP

const SPEED = 315.0
const DASH_SPEED = 200.0
const ATTACK_RANGE = 50.0
const DASH_RANGE = 150.0

# ============ STATE MACHINE ============
enum State {
	IDLE,
	CHASE,
	CIRCLE_STRAFE,
	DASH_ATTACK,
	PUNCH_COMBO,
	FEINT,
	HEAVY_KICK,
	RETREAT,
	HURT,
	DEATH
}

var current_state = State.IDLE
var prev_state = State.IDLE

# ============ COMBAT VARIABLES ============
var state_timer = 0.0
var attack_cooldown = 0.0
var combo_count = 0
var attack_chain = []
var consecutive_same_attack = 0
var circle_direction = 1
var feint_triggered = false

# ============ AI BEHAVIOR ============
var aggression_level = 0.5
var last_player_position = Vector2.ZERO
var player_movement_speed = 0.0

# ============ SIGNALS ============
signal boss_died
signal boss_hurt(damage)
signal tutorial_trigger(message)
signal attack_telegraph(attack_type)

# ============================================
# READY
# ============================================
func _ready():
	add_to_group("bosses")
	add_to_group("enemies")
	
	# Verify critical nodes exist
	if not sprite:
		push_error("Vernita: Sprite2D node not found! Check scene structure.")
	if not anim:
		push_warning("Vernita: AnimationPlayer not found. Animations won't play.")
	if not hitbox:
		push_warning("Vernita: HitBox not found. Attacks won't connect.")
	
	# Wait for scene tree
	await get_tree().process_frame
	
	# Find player
	player = get_tree().get_first_node_in_group("player")
	if not player:
		push_error("Vernita: Player not found! Add player to 'player' group.")
	
	# Connect hitbox
	if hitbox:
		hitbox.body_entered.connect(_on_hitbox_entered)
	
	change_state(State.IDLE)
	
	print("Vernita initialized - HP: %d" % MAX_HP)

# ============================================
# PROCESS
# ============================================
func _process(delta):
	state_timer += delta
	attack_cooldown = max(0, attack_cooldown - delta)
	
	# Update aggression based on HP
	aggression_level = 1.0 - (float(current_hp) / float(MAX_HP))
	
	# Track player movement for AI
	if player:
		var current_player_pos = player.global_position
		player_movement_speed = current_player_pos.distance_to(last_player_position) / delta
		last_player_position = current_player_pos
	
	# DEBUG label (optional)
	if state_label:
		state_label.text = "%s | Aggro: %.1f" % [State.keys()[current_state], aggression_level]

# ============================================
# PHYSICS PROCESS
# ============================================
func _physics_process(delta):
	match current_state:
		State.IDLE:
			process_idle(delta)
		State.CHASE:
			process_chase(delta)
		State.CIRCLE_STRAFE:
			process_circle_strafe(delta)
		State.DASH_ATTACK:
			process_dash_attack(delta)
		State.PUNCH_COMBO:
			process_punch_combo(delta)
		State.FEINT:
			process_feint(delta)
		State.HEAVY_KICK:
			process_heavy_kick(delta)
		State.RETREAT:
			process_retreat(delta)
		State.HURT:
			process_hurt(delta)
		State.DEATH:
			process_death(delta)
	
	move_and_slide()

# ============================================
# STATE FUNCTIONS
# ============================================

func process_idle(delta):
	velocity = Vector2.ZERO
	
	if state_timer > 1.0:
		change_state(State.CHASE)

func process_chase(delta):
	if not player:
		return
	
	var distance = global_position.distance_to(player.global_position)
	var direction = (player.global_position - global_position).normalized()
	
	# In attack range?
	if distance < ATTACK_RANGE and attack_cooldown <= 0:
		choose_attack()
		return
	
	# Random chance to circle strafe instead of direct chase
	if distance < 120 and distance > 60 and randf() < 0.3 * aggression_level:
		change_state(State.CIRCLE_STRAFE)
		return
	
	# Far away? Dash attack opportunity
	if distance > DASH_RANGE and distance < 250 and attack_cooldown <= 0:
		if randf() < 0.4 + (0.3 * aggression_level):
			change_state(State.DASH_ATTACK)
			return
	
	# Chase
	velocity = direction * SPEED
	
	# Face player (null check!)
	if sprite and direction.x != 0:
		sprite.flip_h = direction.x < 0

func process_circle_strafe(delta):
	"""Circle around player while maintaining distance"""
	if not player:
		change_state(State.CHASE)
		return
	
	var distance = global_position.distance_to(player.global_position)
	var to_player = (player.global_position - global_position).normalized()
	
	# Calculate tangent (perpendicular) direction
	var tangent = Vector2(-to_player.y, to_player.x) * circle_direction
	
	# Mix tangent with slight inward movement
	var move_dir = tangent * 0.8 + to_player * 0.2
	velocity = move_dir.normalized() * (SPEED * 1.2)
	
	# Face player (null check!)
	if sprite:
		sprite.flip_h = to_player.x < 0
	
	# Exit conditions
	if state_timer > randf_range(1.0, 2.0):
		if distance < ATTACK_RANGE and attack_cooldown <= 0:
			choose_attack()
		else:
			change_state(State.CHASE)
	
	# Too far? Chase instead
	if distance > 100:
		change_state(State.CHASE)

func process_dash_attack(delta):
	"""Quick dash forward with punch"""
	if not player:
		change_state(State.CHASE)
		return
	
	var to_player = (player.global_position - global_position).normalized()
	
	# Windup (0.0-0.3s)
	if state_timer < 0.3:
		velocity = Vector2.ZERO
		if sprite:
			sprite.flip_h = to_player.x < 0
		
		# Visual telegraph at 0.15s
		if state_timer > 0.15 and state_timer < 0.2:
			attack_telegraph.emit("dash")
			tutorial_trigger.emit("Dodge the dash!")
	
	# Dash (0.3-0.6s)
	elif state_timer < 0.6:
		velocity = to_player * DASH_SPEED
		
		# Hit check at peak
		if state_timer > 0.4 and state_timer < 0.5:
			check_hit_player(3)  # Higher damage for dash
	
	# Recovery (0.6-0.9s)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, DASH_SPEED * delta * 3)
	
	# End
	if state_timer > 0.9:
		attack_cooldown = 2.5
		add_to_attack_chain("dash")
		change_state(State.RETREAT)

func process_punch_combo(delta):
	"""Enhanced 3-punch combo with forward movement"""
	if not player:
		change_state(State.CHASE)
		return
	
	var to_player = (player.global_position - global_position).normalized()
	
	# Face player at start (null check!)
	if state_timer < 0.1 and sprite:
		sprite.flip_h = to_player.x < 0
	
	# Punch timing with forward movement
	var punch_times = [0.25, 0.55, 0.85]
	var punch_damage = [1, 1, 2]  # Last punch hits harder
	
	for i in range(3):
		if state_timer > punch_times[i] and state_timer < punch_times[i] + 0.05 and combo_count == i:
			# Move forward slightly on each punch
			velocity = to_player * 40
			check_hit_player(punch_damage[i])
			combo_count += 1
			
			# Tutorial on first punch ever
			if current_hp == MAX_HP and i == 0:
				tutorial_trigger.emit("Dodge or block the combo!")
	
	# Between punches, slow down
	if state_timer > (punch_times[combo_count - 1] + 0.05 if combo_count > 0 else 0):
		velocity = velocity.move_toward(Vector2.ZERO, 200 * delta)
	
	# End combo
	if state_timer > 1.2:
		combo_count = 0
		attack_cooldown = 1.8
		add_to_attack_chain("combo")
		
		# Sometimes retreat after combo
		if randf() < 0.4:
			change_state(State.RETREAT)
		else:
			change_state(State.CHASE)

func process_feint(delta):
	"""Fake attack to bait dodge, then real attack"""
	if not player:
		change_state(State.CHASE)
		return
	
	var to_player = (player.global_position - global_position).normalized()
	
	# Fake windup (0.0-0.4s)
	if state_timer < 0.4:
		velocity = Vector2.ZERO
		if sprite:
			sprite.flip_h = to_player.x < 0
		
		# Show fake telegraph
		if state_timer > 0.2 and not feint_triggered:
			attack_telegraph.emit("heavy_kick")  # Fake!
			feint_triggered = true
	
	# Cancel fake, dash forward (0.4-0.7s)
	elif state_timer < 0.7:
		velocity = to_player * 150
		
		# Real hit
		if state_timer > 0.5 and state_timer < 0.6:
			check_hit_player(2)
			tutorial_trigger.emit("It was a feint!")
	
	# End
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 300 * delta)
	
	if state_timer > 1.0:
		feint_triggered = false
		attack_cooldown = 3.0
		add_to_attack_chain("feint")
		change_state(State.CHASE)

func process_heavy_kick(delta):
	"""Heavy kick with lunge forward"""
	if not player:
		change_state(State.CHASE)
		return
	
	var to_player = (player.global_position - global_position).normalized()
	
	# Windup (0.0-0.4s)
	if state_timer < 0.4:
		velocity = Vector2.ZERO
		if sprite:
			sprite.flip_h = to_player.x < 0
		
		# Telegraph
		if state_timer > 0.2 and state_timer < 0.25:
			attack_telegraph.emit("heavy_kick")
			
			# Tutorial on first kick
			if current_hp >= MAX_HP - 2:
				tutorial_trigger.emit("Block or parry the heavy kick!")
	
	# Kick with lunge (0.4-0.6s)
	elif state_timer < 0.6:
		velocity = to_player * 120
		
		# Hit check
		if state_timer > 0.45 and state_timer < 0.5:
			check_hit_player(3)
	
	# Recovery (0.6-1.0s)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 200 * delta)
	
	# End
	if state_timer > 1.0:
		attack_cooldown = 2.2
		add_to_attack_chain("kick")
		change_state(State.CHASE)

func process_retreat(delta):
	"""Back away from player"""
	if not player:
		change_state(State.CHASE)
		return
	
	var away_from_player = (global_position - player.global_position).normalized()
	velocity = away_from_player * (SPEED * 1.3)
	
	# Face player while retreating (null check!)
	if sprite:
		sprite.flip_h = away_from_player.x > 0
	
	# Stop retreating
	if state_timer > 0.8 or global_position.distance_to(player.global_position) > 120:
		change_state(State.CHASE)

func process_hurt(delta):
	velocity = Vector2.ZERO
	
	if state_timer > 0.3:
		# Sometimes retreat after being hurt
		if randf() < 0.5:
			change_state(State.RETREAT)
		else:
			change_state(State.CHASE)

func process_death(delta):
	velocity = Vector2.ZERO
	
	if state_timer > 1.0:
		boss_died.emit()

# ============================================
# ATTACK SELECTION AI
# ============================================
func choose_attack():
	"""Smart attack selection based on context"""
	if not player:
		return
	
	var distance = global_position.distance_to(player.global_position)
	var roll = randf()
	
	# Prevent same attack 3 times in a row
	var last_attack = attack_chain[-1] if attack_chain.size() > 0 else ""
	
	# Build probability weights
	var weights = {
		"combo": 0.3,
		"kick": 0.25,
		"dash": 0.15,
		"feint": 0.1
	}
	
	# Adjust based on distance
	if distance < 40:
		weights["combo"] += 0.2
		weights["kick"] += 0.1
	else:
		weights["dash"] += 0.15
		weights["feint"] += 0.1
	
	# Adjust based on player movement
	if player_movement_speed > 100:  # Player is moving fast
		weights["dash"] += 0.15
		weights["feint"] += 0.1
	
	# Adjust based on aggression (HP)
	weights["dash"] += aggression_level * 0.15
	weights["feint"] += aggression_level * 0.1
	
	# Reduce weight of last attack
	if last_attack in weights:
		weights[last_attack] *= 0.3
	
	# Normalize weights
	var total = 0.0
	for w in weights.values():
		total += w
	for key in weights:
		weights[key] /= total
	
	# Select attack
	var cumulative = 0.0
	for attack_type in weights:
		cumulative += weights[attack_type]
		if roll < cumulative:
			execute_attack(attack_type)
			return
	
	# Fallback
	change_state(State.PUNCH_COMBO)

func execute_attack(attack_type: String):
	"""Execute chosen attack"""
	match attack_type:
		"combo":
			change_state(State.PUNCH_COMBO)
		"kick":
			change_state(State.HEAVY_KICK)
		"dash":
			change_state(State.DASH_ATTACK)
		"feint":
			change_state(State.FEINT)

func add_to_attack_chain(attack_type: String):
	"""Track attack history"""
	attack_chain.append(attack_type)
	if attack_chain.size() > 5:
		attack_chain.pop_front()

# ============================================
# UTILITY FUNCTIONS
# ============================================
func check_hit_player(damage: int):
	"""Check if attack connects with player"""
	if not player:
		return
	
	var distance = global_position.distance_to(player.global_position)
	if distance < 45:
		# Player's hurtbox should detect this
		# This is just for AI tracking
		pass

# ============================================
# STATE CHANGES
# ============================================
func change_state(new_state):
	prev_state = current_state
	current_state = new_state
	state_timer = 0.0
	
	# State entry logic
	match current_state:
		State.IDLE:
			velocity = Vector2.ZERO
		State.CHASE:
			pass
		State.CIRCLE_STRAFE:
			# Random direction
			circle_direction = 1 if randf() < 0.5 else -1
		State.DASH_ATTACK:
			pass
		State.PUNCH_COMBO:
			combo_count = 0
		State.FEINT:
			feint_triggered = false
		State.HEAVY_KICK:
			pass
		State.RETREAT:
			pass
		State.HURT:
			pass
		State.DEATH:
			set_physics_process(false)
	
	# Update animations
	update_animation()

func update_animation():
	"""Play appropriate animation for state"""
	if not anim:
		return  # No AnimationPlayer, skip
	
	match current_state:
		State.IDLE:
			if anim.has_animation("idle"):
				anim.play("idle")
		State.CHASE, State.RETREAT:
			if anim.has_animation("walk"):
				anim.play("walk")
		State.CIRCLE_STRAFE:
			if anim.has_animation("walk"):
				anim.play("walk")
		State.DASH_ATTACK:
			if anim.has_animation("dash_punch"):
				anim.play("dash_punch")
		State.PUNCH_COMBO:
			if anim.has_animation("punch_combo"):
				anim.play("punch_combo")
		State.FEINT:
			if anim.has_animation("feint"):
				anim.play("feint")
			elif anim.has_animation("heavy_kick"):
				anim.play("heavy_kick")  # Fallback
		State.HEAVY_KICK:
			if anim.has_animation("heavy_kick"):
				anim.play("heavy_kick")
		State.HURT:
			if anim.has_animation("hurt"):
				anim.play("hurt")
		State.DEATH:
			if anim.has_animation("death"):
				anim.play("death")

# ============================================
# DAMAGE SYSTEM
# ============================================
func take_damage(damage: int):
	if current_state == State.DEATH:
		return
	
	current_hp = max(0, current_hp - damage)
	boss_hurt.emit(damage)
	
	print("Vernita took %d damage - HP: %d/%d" % [damage, current_hp, MAX_HP])
	
	# Tutorial on first damage
	if current_hp == MAX_HP - 1:
		tutorial_trigger.emit("Nice hit! Keep attacking!")
	
	# Phase shift at 50% HP
	if current_hp <= MAX_HP / 2 and current_hp > MAX_HP / 2 - damage:
		tutorial_trigger.emit("Vernita is getting desperate!")
		print("Vernita entered Phase 2 - Aggression increased!")
	
	if current_hp <= 0:
		print("Vernita defeated!")
		change_state(State.DEATH)
	else:
		change_state(State.HURT)

func _on_hitbox_entered(body):
	if body.is_in_group("player"):
		# Player handles damage on their end
		pass
