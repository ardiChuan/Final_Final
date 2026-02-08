extends CharacterBody2D

# === VERNITA GREEN BOSS ===
# Week 9 - Basic tutorial boss
# HP: 10 | Attacks: 3-punch combo, heavy kick

# ============ REFERENCES ============
@onready var sprite = $Sprite2D
@onready var anim = $AnimationPlayer
@onready var state_label = $StateLabel  # DEBUG
@onready var hitbox = $HitBox

var player: CharacterBody2D = null

# ============ STATS ============
const MAX_HP = 10
var current_hp = MAX_HP

const SPEED = 80.0
const ATTACK_RANGE = 50.0
const COMBO_RANGE = 45.0

# ============ STATE MACHINE ============
enum State {
	IDLE,
	CHASE,
	PUNCH_COMBO,
	HEAVY_KICK,
	HURT,
	DEATH
}

var current_state = State.IDLE
var prev_state = State.IDLE

# ============ TIMERS ============
var state_timer = 0.0
var attack_cooldown = 0.0
var combo_count = 0

# ============ SIGNALS ============
signal boss_died
signal boss_hurt(damage)
signal tutorial_trigger(message)

# ============================================
# READY
# ============================================
func _ready():
	add_to_group("bosses")
	add_to_group("enemies")
	
	# Find player
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	
	if not player:
		push_error("Vernita: Player not found!")
	
	# Connect hitbox
	if hitbox:
		hitbox.body_entered.connect(_on_hitbox_entered)
	
	change_state(State.IDLE)

# ============================================
# PROCESS
# ============================================
func _process(delta):
	state_timer += delta
	attack_cooldown = max(0, attack_cooldown - delta)
	
	# DEBUG label
	if state_label:
		state_label.text = State.keys()[current_state]

# ============================================
# PHYSICS PROCESS
# ============================================
func _physics_process(delta):
	match current_state:
		State.IDLE:
			process_idle(delta)
		State.CHASE:
			process_chase(delta)
		State.PUNCH_COMBO:
			process_punch_combo(delta)
		State.HEAVY_KICK:
			process_heavy_kick(delta)
		State.HURT:
			process_hurt(delta)
		State.DEATH:
			process_death(delta)
	
	move_and_slide()

# ============================================
# STATE FUNCTIONS
# ============================================

func process_idle(_delta):
	velocity = Vector2.ZERO
	
	# Wait 1 second, then chase
	if state_timer > 1.0:
		change_state(State.CHASE)

func process_chase(_delta):
	if not player:
		return
	
	var distance = global_position.distance_to(player.global_position)
	
	# In attack range?
	if distance < ATTACK_RANGE and attack_cooldown <= 0:
		choose_attack()
		return
	
	# Chase player
	var direction = (player.global_position - global_position).normalized()
	velocity = direction * SPEED
	
	# Face player
	if direction.x != 0:
		sprite.flip_h = direction.x < 0

func choose_attack():
	"""Randomly choose attack"""
	var distance = global_position.distance_to(player.global_position)
	
	# Close range: 70% combo, 30% kick
	# Far range: 30% combo, 70% kick
	var random = randf()
	
	if distance < COMBO_RANGE:
		if random < 0.7:
			change_state(State.PUNCH_COMBO)
		else:
			change_state(State.HEAVY_KICK)
	else:
		if random < 0.3:
			change_state(State.PUNCH_COMBO)
		else:
			change_state(State.HEAVY_KICK)

func process_punch_combo(_delta):
	"""3-punch combo attack"""
	velocity = Vector2.ZERO
	
	# Face player at start
	if state_timer < 0.1 and player:
		var dir = (player.global_position - global_position).normalized()
		sprite.flip_h = dir.x < 0
	
	# Punch timing
	var punch_times = [0.3, 0.6, 0.9]  # 3 punches
	
	for i in range(3):
		if state_timer > punch_times[i] and combo_count == i:
			do_punch()
			combo_count += 1
	
	# End combo
	if state_timer > 1.2:
		combo_count = 0
		attack_cooldown = 2.0  # 2 second cooldown
		change_state(State.CHASE)

func do_punch():
	"""Execute single punch"""
	# Tutorial on first punch
	if current_hp == MAX_HP and combo_count == 0:
		tutorial_trigger.emit("Press SPACE to dodge!")
	
	# Damage nearby player
	if player and global_position.distance_to(player.global_position) < 40:
		# Player should handle damage via their own hitbox detection
		pass

func process_heavy_kick(_delta):
	"""Heavy kick attack"""
	velocity = Vector2.ZERO
	
	# Face player at start
	if state_timer < 0.1 and player:
		var dir = (player.global_position - global_position).normalized()
		sprite.flip_h = dir.x < 0
	
	# Windup: 0.0-0.4s
	# Kick: 0.4s
	# Recovery: 0.4-0.8s
	
	if state_timer > 0.4 and state_timer < 0.5:
		# Tutorial on first kick
		if current_hp >= MAX_HP - 2:
			tutorial_trigger.emit("Press SHIFT to block!")
		
		# Kick hitbox active
		# Player should detect via Area2D
		pass
	
	# End attack
	if state_timer > 0.8:
		attack_cooldown = 2.5  # Longer cooldown
		change_state(State.CHASE)

func process_hurt(_delta):
	"""Hurt state"""
	velocity = Vector2.ZERO
	
	# Brief stun
	if state_timer > 0.3:
		change_state(State.CHASE)

func process_death(_delta):
	"""Death state"""
	velocity = Vector2.ZERO
	
	# Wait for animation
	if state_timer > 1.0:
		boss_died.emit()
		# Don't queue_free yet - let boss room handle it

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
			pass
		State.CHASE:
			pass
		State.PUNCH_COMBO:
			combo_count = 0
		State.HEAVY_KICK:
			pass
		State.HURT:
			# Flash red (implement in animation)
			pass
		State.DEATH:
			# Play death animation
			set_physics_process(false)

# ============================================
# DAMAGE SYSTEM
# ============================================
func take_damage(damage: int):
	if current_state == State.DEATH:
		return
	
	current_hp = max(0, current_hp - damage)
	boss_hurt.emit(damage)
	
	# Tutorial on first damage
	if current_hp == MAX_HP - 1:
		tutorial_trigger.emit("Press Q to parry!")
	
	if current_hp <= 0:
		change_state(State.DEATH)
	else:
		change_state(State.HURT)

# ============================================
# HITBOX DETECTION
# ============================================
func _on_hitbox_entered(body):
	"""When Vernita's hitbox touches player during attack"""
	if body.is_in_group("player") and current_state in [State.PUNCH_COMBO, State.HEAVY_KICK]:
		# Player should detect this and take damage
		# This is just for attack detection
		pass
