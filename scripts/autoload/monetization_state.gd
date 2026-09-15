extends Node
## MonetizationState — Phase 10 quota model (free-tier weekly limits).
## Mock premium flag; weekly rollover via Time.get_unix_time_from_system().

signal quota_changed
signal premium_changed(is_premium: bool)

const FREE_PDF_LIMIT: int = 3
const FREE_GRADE_LIMIT: int = 10
const WEEK_SECONDS: int = 604800

var is_premium: bool = false
var pdf_used_this_week: int = 0
var grades_used_this_week: int = 0
var week_start_unix: int = 0


func _maybe_rollover_week() -> void:
	var now := int(Time.get_unix_time_from_system())
	if week_start_unix == 0:
		week_start_unix = now
		return
	if now >= week_start_unix + WEEK_SECONDS:
		pdf_used_this_week = 0
		grades_used_this_week = 0
		week_start_unix = now
		quota_changed.emit()


func can_consume(type: String) -> bool:
	if is_premium:
		return true
	_maybe_rollover_week()
	match type:
		"pdf":
			return pdf_used_this_week < FREE_PDF_LIMIT
		"grade":
			return grades_used_this_week < FREE_GRADE_LIMIT
		_:
			return false

func consume(type: String) -> bool:
	if is_premium:
		return true
	if not can_consume(type):
		return false
	match type:
		"pdf":
			pdf_used_this_week += 1
			quota_changed.emit()
			return true
		"grade":
			grades_used_this_week += 1
			quota_changed.emit()
			return true
		_:
			return false


func get_remaining(type: String) -> int:
	if is_premium:
		return 999
	_maybe_rollover_week()
	match type:
		"pdf":
			return maxi(0, FREE_PDF_LIMIT - pdf_used_this_week)
		"grade":
			return maxi(0, FREE_GRADE_LIMIT - grades_used_this_week)
		_:
			return 0

## Formatted helper for UI quota labels (premium-aware).
func get_quota_label() -> String:
	if is_premium:
		return "Premium: Unlimited"
	return "Free AI Uses: PDFs %d/%d | Grades %d/%d" % [get_remaining("pdf"), FREE_PDF_LIMIT, get_remaining("grade"), FREE_GRADE_LIMIT]

## Mock premium toggle (Settings UI).
func set_premium(val: bool) -> void:
	if is_premium == val:
		return
	is_premium = val
	premium_changed.emit(is_premium)
	quota_changed.emit()

## Debug: manually trigger a weekly rollover (Settings Reset Quota).
func reset_quota() -> void:
	pdf_used_this_week = 0
	grades_used_this_week = 0
	week_start_unix = int(Time.get_unix_time_from_system())
	quota_changed.emit()

func to_dict() -> Dictionary:
	return {
		"is_premium": is_premium,
		"pdf_used_this_week": pdf_used_this_week,
		"grades_used_this_week": grades_used_this_week,
		"week_start_unix": week_start_unix,
	}


func from_dict(data: Dictionary) -> void:
	is_premium = bool(data.get("is_premium", false))
	pdf_used_this_week = int(data.get("pdf_used_this_week", 0))
	grades_used_this_week = int(data.get("grades_used_this_week", 0))
	week_start_unix = int(data.get("week_start_unix", 0))
	# Clamp to valid ranges (defensive against tampered saves).
	pdf_used_this_week = clampi(pdf_used_this_week, 0, FREE_PDF_LIMIT)
	grades_used_this_week = clampi(grades_used_this_week, 0, FREE_GRADE_LIMIT)
	quota_changed.emit()
	premium_changed.emit(is_premium)
