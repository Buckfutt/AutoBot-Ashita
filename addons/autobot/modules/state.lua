local state = {}

state.debug = false
state.mounted = false
state.auto_assist_active = false

-------------------------------------------------
-- GLOBAL COMBAT LOCK
-------------------------------------------------
state.combat_lock = false

-------------------------------------------------
-- TARGET / PULL COORDINATION
-------------------------------------------------
state.target_server_id = 0
state.target_index = -1
state.target_locked_at = 0

state.pull_in_progress = false
state.pull_target_id = 0
state.pull_started_at = 0
state.pull_completed = false
state.trust_maintenance = false
state.player_resting = false
state.zone_in_progress = false
state.resource_settle_until = 0

state.force_retarget = false
state.force_retarget_reason = ''
state.combat_settle_until = 0

-------------------------------------------------
-- NAVIGATION COORDINATION
-------------------------------------------------
state.navigation_playback = false
state.navigation_paused = false

return state
