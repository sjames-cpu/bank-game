extends Node
class_name OnboardingFlow

## Runs a career's onboarding (OnboardingManager, OnboardingData) in the room,
## from whichever step it's at: the background check letter and the
## employment contract ("I agree") on the shared letter screen, then the four
## training lessons (OnboardingScreen). Each step done advances
## OnboardingManager and saves the career, so quitting mid-onboarding resumes
## at the same step. `finished` fires once it's all done (at once for a career
## already past it), and the room then shows its first-run hints.
##
## The F1 and F2 debug shortcuts (debug builds only, the room's
## debug_cheats_enabled) skip whatever is left, then do what they always do.
## This node runs while the tree is paused (the letters and lessons pause
## it), so it hears those keys when the room can't.

signal finished

var room: TellerRoom

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	room.onboarding_screen.lesson_passed.connect(_on_lesson_passed)

func start() -> void:
	_show_current()

func is_running() -> bool:
	return not OnboardingManager.is_complete()

func _show_current() -> void:
	var step := OnboardingManager.step
	match step:
		OnboardingManager.Step.BACKGROUND_CHECK:
			room.letter_screen.show_notice(OnboardingData.BACKGROUND_CHECK_TITLE, OnboardingData.background_check_body(), OnboardingData.SENDER, "", _step_done)
		OnboardingManager.Step.CONTRACT:
			room.letter_screen.show_notice(OnboardingData.CONTRACT_TITLE, OnboardingData.contract_body(), OnboardingData.SENDER, OnboardingData.AGREE_BUTTON_TEXT, _step_done)
		OnboardingManager.Step.DONE:
			finished.emit()
		_:
			room.onboarding_screen.show_lesson(OnboardingManager.lesson_index(step))

func _step_done() -> void:
	OnboardingManager.advance()
	room.save_career()
	_show_current()

func _on_lesson_passed(_index: int) -> void:
	_step_done()

## Everything left is skipped (no training XP): the letter or lesson on
## screen closes, and the room carries on as after onboarding.
func skip() -> void:
	if not is_running():
		return
	var letters := room.letter_screen
	if letters.visible and letters.title_label.text in [OnboardingData.BACKGROUND_CHECK_TITLE, OnboardingData.CONTRACT_TITLE]:
		letters.dismiss_current()
	if room.onboarding_screen.visible:
		room.onboarding_screen.hide_screen()
	OnboardingManager.skip()
	room.save_career()
	finished.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not is_running() or not room.debug_cheats_enabled:
		return
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == TellerRoom.DEBUG_UNLOCK_KEY or key_event.keycode == TellerRoom.DEBUG_LOAN_OFFICER_KEY:
		get_viewport().set_input_as_handled()
		skip()
		room.apply_debug_key(key_event.keycode)
