extends "res://tests/support/teller_room_suite.gd"

## Role-unlocked notifications on the HUD show once when the unlock happens
## and fade, never coming back after a save is loaded; the low-reputation
## warning stays up while Reputation is low.

var hud: Hud

func before_test() -> void:
	await super()
	hud = room.hud

# --- helpers -------------------------------------------------------------------

## Steps every running unlock-notification tween by `seconds`.
func advance_notifications(seconds: float) -> void:
	for tween: Tween in hud.unlock_tweens.values():
		tween.custom_step(seconds)
	hud.refresh()

## Clicks away any letters (e.g. the promotion letter).
func acknowledge_all() -> void:
	while room.letter_screen.visible and room.letter_screen.action_button.text == "Acknowledge":
		room.letter_screen.action_button.pressed.emit()

# --- unlock notifications ------------------------------------------------------------

func test_an_unlock_notification_shows_once_then_fades() -> void:
	assert_bool(hud.loan_officer_unlocked_label.visible).is_false()
	XPManager.add_shift_xp(ceili(float(XPManager.XP_UNLOCK_THRESHOLD) / XPManager.XP_PER_SCORE_POINT))
	assert_bool(XPManager.is_loan_officer_unlocked).is_true()
	hud.refresh()
	assert_bool(hud.loan_officer_unlocked_label.visible).is_true()
	assert_bool(hud.notification_panel.visible).is_true()

	# Still up just before the time is up, fading after, gone after the fade.
	advance_notifications(Hud.UNLOCK_NOTIFICATION_SECONDS - 0.1)
	assert_bool(hud.loan_officer_unlocked_label.visible).is_true()
	assert_float(hud.loan_officer_unlocked_label.modulate.a).is_equal(1.0)
	advance_notifications(0.1 + Hud.UNLOCK_FADE_SECONDS / 2.0)
	assert_float(hud.loan_officer_unlocked_label.modulate.a).is_between(0.05, 0.95)
	advance_notifications(Hud.UNLOCK_FADE_SECONDS)
	assert_bool(hud.loan_officer_unlocked_label.visible).is_false()
	assert_bool(hud.notification_panel.visible).is_false()
	assert_dict(hud.unlock_tweens).is_empty()

	# Nothing brings it back: more XP, a screen opened and closed, frames.
	XPManager.add_shift_xp(10)
	room.loan_officer_screen.show_screen()
	room.loan_officer_screen.close_button.pressed.emit()
	for i in 5:
		await get_tree().process_frame
	assert_bool(hud.loan_officer_unlocked_label.visible).is_false()
	assert_bool(hud.notification_panel.visible).is_false()

func test_the_notification_fades_in_real_time() -> void:
	XPManager._grant_branch_manager()
	assert_bool(hud.branch_manager_unlocked_label.visible).is_true()
	# Played at speed: gone a little after 5 s plus the fade, even with the
	# promotion letter pausing the tree.
	assert_bool(get_tree().paused).is_true()
	Engine.time_scale = 10.0
	var waited := 0.0
	while hud.branch_manager_unlocked_label.visible and waited < 2.0:
		await get_tree().process_frame
		waited += get_process_delta_time() / Engine.time_scale
	assert_bool(hud.branch_manager_unlocked_label.visible).is_false()

func test_unlock_notifications_dont_return_after_loading() -> void:
	XPManager._grant_branch_manager()
	acknowledge_all()
	assert_bool(hud.branch_manager_unlocked_label.visible).is_true()
	assert_bool(SaveGame.save()).is_true()

	# Continue the saved career in a fresh room.
	CareerReset.reset_all()
	SaveGame.restore(SaveGame.read().career)
	assert_bool(XPManager.is_branch_manager_unlocked).is_true()
	room.free()
	room = instantiate_room()
	get_tree().root.add_child(room)
	get_tree().current_scene = room
	await get_tree().process_frame
	await get_tree().process_frame
	var fresh_hud := room.hud
	fresh_hud.refresh()
	assert_bool(fresh_hud.branch_manager_unlocked_label.visible).is_false()
	assert_bool(fresh_hud.loan_officer_unlocked_label.visible).is_false()
	assert_bool(fresh_hud.notification_panel.visible).is_false()
	assert_dict(fresh_hud.unlock_tweens).is_empty()

func test_the_low_reputation_warning_stays_up() -> void:
	ReputationManager.add_reputation(-ReputationManager.reputation)
	XPManager.is_loan_officer_unlocked = false
	hud.show_unlock_notification(hud.loan_officer_unlocked_label)
	hud.refresh()
	assert_bool(hud.low_reputation_warning_label.visible).is_true()
	# Long after any notification would have gone, it's still there.
	advance_notifications(60.0)
	for i in 5:
		await get_tree().process_frame
	assert_bool(hud.loan_officer_unlocked_label.visible).is_false()
	assert_bool(hud.low_reputation_warning_label.visible).is_true()
	assert_bool(hud.notification_panel.visible).is_true()
	# And goes once Reputation recovers.
	ReputationManager.add_reputation(30)
	hud.refresh()
	assert_bool(hud.low_reputation_warning_label.visible).is_false()
	assert_bool(hud.notification_panel.visible).is_false()
