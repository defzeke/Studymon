extends Control
## Phase 1: Login / Signup screen

@onready var email_field: LineEdit = $Center/EmailField
@onready var password_field: LineEdit = $Center/PasswordField
@onready var login_btn: Button = $Center/LoginButton
@onready var signup_btn: Button = $Center/SignupButton
@onready var status_label: Label = $Center/StatusLabel
@onready var loading: ProgressBar = $Center/Loading

func _ready() -> void:
	theme = load("res://ui/app_theme.tres") as Theme
	password_field.secret = true
	login_btn.pressed.connect(_on_login)
	signup_btn.pressed.connect(_on_signup)
	Api.request_failed.connect(_on_api_error)

func _on_login() -> void:
	var email = email_field.text.strip_edges()
	var pwd = password_field.text
	if email == "" or pwd == "":
		status_label.text = "Enter email and password"
		return
	_set_loading(true)
	status_label.text = "Logging in..."
	Api.mock_login(email, pwd)
	# In real impl, wait for response via signal
	call_deferred("_mock_login_complete")

func _mock_login_complete() -> void:
	_set_loading(false)
	status_label.text = ""
	get_tree().change_scene_to_file("res://scenes/companion/meet_companion.tscn")

func _on_signup() -> void:
	var email = email_field.text.strip()
	var pwd = password_field.text
	if email == "" or pwd == "":
		status_label.text = "Enter email and password"
		return
	_set_loading(true)
	status_label.text = "Creating account..."
	Api.mock_login(email, pwd)  # mock reuses login
	call_deferred("_mock_login_complete")

func _on_api_error(endpoint: String, error: String) -> void:
	_set_loading(false)
	status_label.text = "Error: " + error

func _set_loading(on: bool) -> void:
	loading.visible = on
	login_btn.disabled = on
	signup_btn.disabled = on
	email_field.editable = not on
	password_field.editable = not on