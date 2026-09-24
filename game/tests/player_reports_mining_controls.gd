extends "res://tests/first_flight_session.gd"
## Focused original tutorial-entry/input regression; no earned-save claim.

func mine_trip(_args: PackedStringArray) -> bool:
	for cycle in 3:
		key(KEY_Q);key(KEY_2)
		check(host.session.snapshot().station_autopilot.active,"Tutorial station autopilot cannot re-engage: "+host.status.text)
		if failures or not step():return false
		key(KEY_Q);key(KEY_1)
		check(not host.session.snapshot().station_autopilot.active,"Tutorial station autopilot did not cancel")
		if failures or not step():return false
	check(host.session.can_control() and host.session.fast_forward_available(),"Tutorial control cancellation lost released input or Fast Forward capability")
	# This test intentionally ends before mining or earning tutorial progress.
	return false
