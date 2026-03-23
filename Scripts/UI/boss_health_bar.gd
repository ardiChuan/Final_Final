extends Control

@onready var health_bar = $ProgressBar
@onready var boss_name = $BossName

var boss: Node = null



func initialize(boss_node: Node, boss_display_name: String):
	boss = boss_node
	boss_name.text = boss_display_name
	
	# Connect to boss signals
	boss.boss_hurt.connect(_on_boss_hurt)
	boss.boss_died.connect(_on_boss_died)
	
	# Set initial health
	health_bar.max_value = boss.MAX_HP
	health_bar.value = boss.current_hp
	
	show()

func _on_boss_hurt(damage):
	# Animate health drop
	var tween = create_tween()
	tween.tween_property(health_bar, "value", boss.current_hp, 0.3)

func _on_boss_died():
	# Fade out
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(queue_free)
