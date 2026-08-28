extends Control

func _ready():
	$VBoxContainer/MenuButton.pressed.connect(_on_menu_button_pressed)
	$BlackFade.visible = false

func show_game_over(final_score: int, reason: String = "GAME OVER"):
	# Show screen with title and score
	$VBoxContainer/TitlePanel/Title.text = "♪ " + reason + " ♪"
	$VBoxContainer/FinalScore.text = "Final Score: " + GameManager.format_score(final_score)
	visible = true

	# Fade in from black
	$BlackFade.visible = true
	$BlackFade.color = Color(0, 0, 0, 1)

	var tween = create_tween()
	tween.tween_property($BlackFade, "color:a", 0.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func(): $BlackFade.visible = false)

func _on_menu_button_pressed():
	$VBoxContainer/MenuButton.disabled = true

	# Fade to black then change scene
	$BlackFade.visible = true
	$BlackFade.color = Color(0, 0, 0, 0)

	var tween = create_tween()
	tween.tween_property($BlackFade, "color:a", 1.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
