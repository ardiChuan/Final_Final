extends StaticBody2D

@export var max_health := 100000
var current_health := 100000

@onready var visual: ColorRect = $ColorRect
@onready var health_label: Label = $Labels

func _ready():
	update_health_display()

func take_damage(amount: int) -> void:
	current_health -= amount
	update_health_display()
	body_flash_red()
	if current_health <= 0:
		die()

func update_health_display() -> void:
	health_label.text = str(current_health) + "/" + str(max_health)

func body_flash_red() -> void:
	visual.color = Color.RED
	await get_tree().create_timer(0.1).timeout
	visual.color = Color.GREEN if current_health > 0 else Color.DARK_GRAY

func die() -> void:
	visual.color = Color.DARK_GRAY
	health_label.text = "DEAD"
	collision_layer = 0  # Disable collision
