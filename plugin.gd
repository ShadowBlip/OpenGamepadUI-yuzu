extends Plugin

const library_scene := preload("res://plugins/yuzu/core/library_yuzu.tscn")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	logger = Log.get_logger("Yuzu", Log.LEVEL.INFO)
	logger.info("Yuzu plugin loaded")
	var library := library_scene.instantiate()
	add_child(library)
