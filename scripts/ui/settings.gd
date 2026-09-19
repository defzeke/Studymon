extends Control
## Phase 10: Settings — mock monetization controls + debug quota reset.
## Checkbox toggles MonetizationState.is_premium; button triggers weekly rollover.

@onready var title_label: Label = $Content/Title
@onready var premium_check: CheckBox = $Content/PremiumRow/PremiumCheck
@onready var quota_label: Label = $Content/QuotaLabel
@onready var pdf_label: Label = $Content/PdfQuotaLabel
@onready var grade_label: Label = $Content/GradeQuotaLabel
@onready var reset_btn: Button = $Content/ResetButton
@onready var back_btn: Button = $Content/BackButton
@onready var status_label: Label = $Content/StatusLabel

func _ready() -> void:
	theme = load("res://ui/app_theme.tres") as Theme
	premium_check.toggled.connect(_on_premium_toggled)
	reset_btn.pressed.connect(_on_reset_pressed)
	back_btn.pressed.connect(_on_back)
	var _ms := get_node_or_null("/root/MonetizationState")
	if _ms != null:
		_ms.quota_changed.connect(_refresh)
		_ms.premium_changed.connect(_on_premium_changed)
	_refresh()

func _refresh() -> void:
	var _ms := get_node_or_null("/root/MonetizationState")
	# ponytail: null-guard lets scene run standalone without autoloads
	if _ms == null:
		return
	# Prevent signal loop when setting checked state
	var is_p: bool = _ms.is_premium
	if premium_check.button_pressed != is_p:
		premium_check.set_pressed_no_signal(is_p)
	if is_p:
		quota_label.text = "Premium: Unlimited"
		pdf_label.text = "PDFs: Unlimited (Premium)"
		grade_label.text = "Grades: Unlimited (Premium)"
	else:
		var pdf_rem: int = _ms.get_remaining("pdf")
		var grade_rem: int = _ms.get_remaining("grade")
		quota_label.text = "Free AI Uses: PDFs %d/%d | Grades %d/%d" % [pdf_rem, _ms.FREE_PDF_LIMIT, grade_rem, _ms.FREE_GRADE_LIMIT]
		pdf_label.text = "Free AI Uses: %d/%d PDFs remaining" % [pdf_rem, _ms.FREE_PDF_LIMIT]
		grade_label.text = "Free AI Uses: %d/%d Grades remaining" % [grade_rem, _ms.FREE_GRADE_LIMIT]
	premium_check.text = "Premium" if is_p else "Free Tier"
	status_label.text = "Premium enabled — no limits." if is_p else "Free tier — weekly limits active."

func _on_premium_changed(is_premium: bool) -> void:
	_refresh()
	SaveManager.save_game()

func _on_premium_toggled(toggled_on: bool) -> void:
	var _ms := get_node_or_null("/root/MonetizationState")
	if _ms == null:
		return
	_ms.set_premium(toggled_on)
	SaveManager.save_game()

func _on_reset_pressed() -> void:
	var _ms := get_node_or_null("/root/MonetizationState")
	if _ms == null:
		return
	_ms.reset_quota()
	SaveManager.save_game()
	status_label.text = "Quota reset — weekly rollover simulated."
	_refresh()

func _on_back() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main.tscn")
