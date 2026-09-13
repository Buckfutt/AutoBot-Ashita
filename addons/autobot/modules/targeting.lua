local targeting = {}

local settings = nil
local running = false

-------------------------------------------------
-- STATE
-------------------------------------------------
local locked_server_id   = 0
local attack_loop_active = false
local attack_attempts    = 0
local max_attempts       = 30
local tick_scheduled     = false

local facing_running     = false

local chat = require('chat')
local state = require('modules.state')

local STATUS_ENGAGED = 2
local COMBAT_SETTLE_SECONDS = 2.0

-------------------------------------------------
-- HELPERS
-------------------------------------------------
local function entity()
    return AshitaCore:GetMemoryManager():GetEntity()
end

local function target_manager()
    return AshitaCore:GetMemoryManager():GetTarget()
end

local function is_subtarget_active()
    local target = target_manager()

    if not target then
        return false
    end

    local ok, active = pcall(function()
        return target:GetIsSubTargetActive()
    end)

    return ok and active == 1
end

local function party()
    return AshitaCore:GetMemoryManager():GetParty()
end

local function player_manager()
    return AshitaCore:GetMemoryManager():GetPlayer()
end

local function get_player_status()
    local player = player_manager()
    if player then
        local ok_player, player_status =
            pcall(function()
                return player:GetStatus()
            end)

        if ok_player and player_status ~= nil then
            return player_status
        end
    end

    local ent = entity()
    local p = party()
    local status = 0

    if ent and p then
        local ok_index, player_index =
            pcall(function()
                return p:GetMemberTargetIndex(0)
            end)

        if ok_index and player_index then
            local ok_status, entity_status =
                pcall(function()
                    return ent:GetStatus(player_index)
                end)

            if ok_status and entity_status then
                status = entity_status
            end
        end
    end

    if status ~= 0 then
        return status
    end

    return status
end

local function get_current_target()

    local tgt = target_manager()

    if not tgt then
        return -1
    end

    local ok, idx = pcall(function()
        return tgt:GetTargetIndex(0)
    end)

    if not ok or not idx then
        return -1
    end

    return idx
end

local function get_server_id(index)

    local ent = entity()

    if not ent or index < 0 then
        return 0
    end

    return ent:GetServerId(index) or 0
end

local function get_target_status(index)

    local ent = entity()

    if not ent or not index or index <= 0 then
        return 0
    end

    local ok, status =
        pcall(function()
            return ent:GetStatus(index)
        end)

    if not ok or not status then
        return 0
    end

    return status
end

local function is_engaged_status(status)
    return status == 1
        or status == STATUS_ENGAGED
end

local function player_is_engaged()
    return get_player_status() == 1
end

local function is_combat_active()

    if player_is_engaged() then
        return true
    end

    local current =
        get_current_target()

    return is_engaged_status(get_target_status(current))
end

local function locked_target_combat_active()

    if not player_is_engaged() then
        return false
    end

    local current =
        get_current_target()

    if get_server_id(current) ~= locked_server_id then
        return false
    end

    return is_engaged_status(get_target_status(current))
end

local function now()

    return os.clock()
end

local function begin_combat_settle()
    state.combat_settle_until = math.max(
        state.combat_settle_until or 0,
        now() + COMBAT_SETTLE_SECONDS
    )
end

local function combat_settling()
    return (state.combat_settle_until or 0) > now()
end

local function normalize_name(name)

    if not name then
        return ''
    end

    return name:lower():gsub("^%s*(.-)%s*$", "%1")
end

local function target_name_matches(name)

    local lower = normalize_name(name)

    if lower == '' then
        return false
    end

    for _, v in ipairs(settings.target_list or {}) do

        if lower == normalize_name(v) then
            return true
        end
    end

    return false
end

local function is_valid_mob_entity(index)

    local ent = entity()

    if not ent then
        return false
    end

    local ok_spawn, spawn_flags =
        pcall(function()
            return ent:GetSpawnFlags(index)
        end)

    if not ok_spawn
    or not spawn_flags
    or bit.band(spawn_flags, 0x10) == 0
    then
        return false
    end

    local ok_render, render_flags =
        pcall(function()
            return ent:GetRenderFlags0(index)
        end)

    if ok_render
    and render_flags
    and (bit.band(render_flags, 0x200) ~= 0x200
        or bit.band(render_flags, 0x4000) ~= 0)
    then
        return false
    end

    return true
end

-------------------------------------------------
-- FIND INDEX FROM SERVER ID
-------------------------------------------------
local function find_index_by_server_id(server_id)

    local ent = entity()

    if not ent then
        return -1
    end

    for i = 0, 2048 do

        if ent:GetServerId(i) == server_id then
            return i
        end
    end

    return -1
end

-------------------------------------------------
-- TARGET
-------------------------------------------------
local function set_target(server_id)

    local tgt = target_manager()

    if not tgt then
        return false
    end

    local index =
        find_index_by_server_id(server_id)

    if index <= 0 then
        return false
    end

    -------------------------------------------------
    -- ALREADY TARGETED
    -------------------------------------------------
    -- The targeting loop runs several times per second. Reapplying
    -- SetTarget to the same entity while a pull spell is active can disturb
    -- the client's current action even though no visible command is issued.
    -- Treat selection as idempotent and only touch target memory when the
    -- desired entity is not already selected.
    if get_current_target() == index then
        return true
    end

    -------------------------------------------------
    -- METHOD 1
    -------------------------------------------------
    local ok = pcall(function()
        tgt:SetTarget(index, true)
    end)

    if ok then
        return true
    end

    -------------------------------------------------
    -- METHOD 2
    -------------------------------------------------
    ok = pcall(function()
        tgt:SetTarget(
            server_id,
            index,
            true
        )
    end)

    return ok
end

-------------------------------------------------
-- CLEAR LOCK
-------------------------------------------------
local function clear_lock(reason)

    locked_server_id   = 0
    attack_loop_active = false
    attack_attempts    = 0

    state.target_server_id = 0
    state.target_index = -1
    state.target_locked_at = 0
    state.pull_in_progress = false
    state.pull_target_id = 0
    state.pull_started_at = 0
    state.pull_completed = false
end

local function pulling_enabled()

    return settings
        and settings.modules
        and settings.modules.pulling == true
        and settings.runtime
        and settings.runtime.pulling == true
end

local function get_claim_id(index)
    local ent = entity()
    if not ent or not index or index <= 0 then return 0 end

    local ok, claim_status = pcall(function()
        return ent:GetClaimStatus(index)
    end)

    return ok and claim_status and bit.band(claim_status, 0xFFFF) or 0
end

local function is_party_claim(claim_id)
    if not claim_id or claim_id == 0 then return false end

    local p = party()
    if not p then return false end

    for member = 0, 17 do
        local member_server_id = p:GetMemberServerId(member)
        if p:GetMemberIsActive(member) == 1
        and member_server_id
        and (
            member_server_id == claim_id
            or bit.band(member_server_id, 0xFFFF) == claim_id
        )
        then
            return true
        end
    end

    return false
end

local function lock_target(server_id)

    locked_server_id   = server_id or 0
    attack_loop_active = false
    attack_attempts    = 0

    state.target_server_id = locked_server_id
    state.target_index = find_index_by_server_id(locked_server_id)
    state.target_locked_at = now()
    state.pull_in_progress = false
    state.pull_target_id = 0
    state.pull_started_at = 0
    state.pull_completed = false
    state.force_retarget = false
    state.force_retarget_reason = ''
end

-------------------------------------------------
-- VALID TARGET
-------------------------------------------------
local function is_valid_target(index)

    if not settings then
        return false
    end

    local ent = entity()

    if not ent then
        return false
    end

    -------------------------------------------------
    -- EXISTS
    -------------------------------------------------
    local sid = ent:GetServerId(index)

    if not sid or sid == 0 then
        return false
    end

    -------------------------------------------------
    -- TARGETABLE RENDERED MOB
    -------------------------------------------------
    if not is_valid_mob_entity(index) then
        return false
    end

    local claim_id = get_claim_id(index)
    if claim_id ~= 0 and not is_party_claim(claim_id) then
        return false
    end

    -------------------------------------------------
    -- FULL HP, SAME AS OLD WINDOWER hpp > 99 CHECK
    -------------------------------------------------
    local hp = ent:GetHPPercent(index)

    if not hp or hp <= 99 then
        return false
    end

    -------------------------------------------------
    -- DISTANCE
    -------------------------------------------------
    local dist = ent:GetDistance(index)

    if not dist then
        return false
    end

    local max_distance = 20

    if settings.targeting
    and settings.targeting.max_distance
    then
        max_distance =
            settings.targeting.max_distance
    end

    if math.sqrt(dist) > max_distance then
        return false
    end

    -------------------------------------------------
    -- NAME MATCH
    -------------------------------------------------
    local name = ent:GetName(index)

    if not name then
        return false
    end

    return target_name_matches(name)
end

-------------------------------------------------
-- FIND TARGET
-------------------------------------------------
local function find_best_target()

    local ent = entity()

    if not ent then
        return 0
    end

    local best_sid  = 0
    local best_dist = math.huge

    for i = 0, 2048 do

        if is_valid_target(i) then

            local dist = ent:GetDistance(i)

            if dist then

                local real =
                    math.sqrt(dist)

                if real < best_dist then

                    best_dist = real
                    best_sid  =
                        ent:GetServerId(i)
                end
            end
        end
    end

    return best_sid
end

-------------------------------------------------
-- FACING
-------------------------------------------------
local function facing_tick()

    if not facing_running then
        return
    end

    -------------------------------------------------
    -- JUST USE LOCKON
    -------------------------------------------------
    if player_is_engaged() then

        AshitaCore:GetChatManager():QueueCommand(
            1,
            '/lockon on'
        )
    end

    ashita.tasks.once(
        1.0,
        facing_tick
    )
end

function targeting.start_facing()

    if facing_running then
        return
    end

    facing_running = true

    facing_tick()
end

function targeting.stop_facing()

    facing_running = false
end

-------------------------------------------------
-- ATTACK LOOP
-------------------------------------------------
local function attack_tick()

    if not running then

        attack_loop_active = false

        return
    end

    if combat_settling() then
        ashita.tasks.once(
            0.3,
            attack_tick
        )
        return
    end

    -------------------------------------------------
    -- STOP IF ENGAGED
    -------------------------------------------------
    if locked_target_combat_active() then

        attack_loop_active = false
        attack_attempts    = 0

        return
    end

    if is_subtarget_active() then
        ashita.tasks.once(
            0.3,
            attack_tick
        )
        return
    end

    if player_is_engaged() then

        attack_loop_active = false
        attack_attempts    = 0

        return
    end

    attack_attempts =
        attack_attempts + 1

    -------------------------------------------------
    -- FAIL SAFE
    -------------------------------------------------
    if attack_attempts > max_attempts then
        clear_lock('attack_attempt_limit')

        return
    end

    set_target(locked_server_id)

    if is_subtarget_active() then
        ashita.tasks.once(
            0.3,
            attack_tick
        )
        return
    end

    if not player_is_engaged() then
        AshitaCore:GetChatManager():QueueCommand(1, '/attack <t>')
    end

    ashita.tasks.once(
        1.0,
        attack_tick
    )
end

local function start_attack()

    if attack_loop_active then
        return
    end

    if combat_settling() then
        ashita.tasks.once(
            0.3,
            start_attack
        )
        return
    end

    attack_loop_active = true
    attack_attempts    = 0

    set_target(locked_server_id)

    if is_subtarget_active() then
        ashita.tasks.once(
            0.3,
            attack_tick
        )
        return
    end

    if not player_is_engaged() then
        AshitaCore:GetChatManager():QueueCommand(1, '/attack <t>')
    end

    ashita.tasks.once(
        1.0,
        attack_tick
    )
end

local function target_only(server_id)

    if not server_id or server_id == 0 then
        return
    end

    if not set_target(server_id) then
        return
    end

    if pulling_enabled()
    and not (
        state.pull_completed
        and state.pull_target_id == server_id
    )
    then
        state.pull_in_progress = true
        state.pull_target_id = server_id
        state.pull_started_at = now()
        state.pull_completed = false
        return
    end

    -- Pulling owns engagement whenever it is enabled. Targeting only keeps
    -- the selected mob targeted and waits for combat to finish.
end

function targeting.force_attack(server_id)

    if server_id and server_id ~= 0 then
        lock_target(server_id)
        set_target(server_id)
    end

    start_attack()
end

-------------------------------------------------
-- MAIN LOOP
-------------------------------------------------
local tick

local function schedule_tick(delay)

    if tick_scheduled then
        return
    end

    tick_scheduled = true

    ashita.tasks.once(
        delay or 0.3,
        function()

            tick_scheduled = false

            if running then
                tick()
            end
        end
    )
end

tick = function()

    if not running then
        return
    end

    if state.mounted == true then
        schedule_tick(0.5)
        return
    end

    if combat_settling() then
        schedule_tick(0.3)
        return
    end

    -------------------------------------------------
    -- DROP AN EXTERNALLY CLAIMED LOCK BEFORE THE COMBAT GUARD.
    -- A mob being fought by another party reports an engaged entity status,
    -- which would otherwise make is_combat_active() return early forever.
    -------------------------------------------------
    if locked_server_id ~= 0 and not player_is_engaged() then
        local locked_index =
            find_index_by_server_id(
                locked_server_id
            )

        if locked_index > 0 then
            local claim_id = get_claim_id(locked_index)

            if claim_id ~= 0
            and not is_party_claim(claim_id)
            then
                clear_lock('claimed_by_other_pre_guard')
                schedule_tick(0.1)
                return
            end
        end
    end

    -------------------------------------------------
    -- HONOR PULLING'S RETARGET REQUEST BEFORE CHECKING ENTITY COMBAT STATUS.
    -- An externally claimed mob can report engaged and would otherwise keep
    -- this request blocked until that unrelated fight ends.
    -------------------------------------------------
    if state.force_retarget then
        local retarget_reason = state.force_retarget_reason
        state.force_retarget = false
        state.force_retarget_reason = ''

        if player_is_engaged() then
            state.force_retarget = true
            state.force_retarget_reason = retarget_reason
            schedule_tick(0.3)
            return
        end

        clear_lock('forced_retarget:' .. tostring(retarget_reason))
    end

    -------------------------------------------------
    -- TARGETING ONLY SELECTS TARGETS.
    -- DO NOT RETARGET WHILE ENGAGED.
    -------------------------------------------------
    if is_combat_active() then

        schedule_tick(0.3)

        return
    end

    -------------------------------------------------
    -- LOCK EXISTS:
    -- KEEP THIS MOB UNTIL IT DIES, DISAPPEARS,
    -- CANNOT BE ATTACKED, OR PULLING TIMES OUT.
    -------------------------------------------------
    if locked_server_id ~= 0 then

        local index =
            find_index_by_server_id(
                locked_server_id
            )

        -------------------------------------------------
        -- TARGET GONE
        -------------------------------------------------
        if index <= 0 then

            begin_combat_settle()
            clear_lock('target_disappeared')

            schedule_tick(0.3)

            return
        end

        local ent = entity()

        if ent then
            local claim_id = get_claim_id(index)
            if claim_id ~= 0
            and not is_party_claim(claim_id)
            and not player_is_engaged()
            then
                clear_lock('claimed_by_other')
                schedule_tick(0.1)
                return
            end

            local hp =
                ent:GetHPPercent(index)

            -------------------------------------------------
            -- TARGET DEAD
            -------------------------------------------------
            if not hp or hp <= 0 then

                begin_combat_settle()
                clear_lock('target_dead')

                schedule_tick(0.3)

                return
            end
        end

        -------------------------------------------------
        -- PULLING OWNS THIS TARGET RIGHT NOW.
        -- DO NOT SEARCH, SWITCH, OR ATTACK UNTIL PULLING FINISHES
        -- OR REQUESTS A FORCED RETARGET.
        -------------------------------------------------
        if pulling_enabled()
        and state.pull_target_id == locked_server_id
        and not state.pull_completed
        then

            local current =
                get_current_target()

            local current_sid =
                get_server_id(current)

            if current_sid ~= locked_server_id then
                set_target(locked_server_id)
            end

            schedule_tick(0.3)

            return
        end

        -------------------------------------------------
        -- MAINTAIN TARGET
        -------------------------------------------------
        local current =
            get_current_target()

        local current_sid =
            get_server_id(current)

        if current_sid ~= locked_server_id then
            set_target(locked_server_id)
        end

        -------------------------------------------------
        -- KEEP TARGETED
        -------------------------------------------------
        target_only(locked_server_id)

        schedule_tick(0.3)

        return
    end

    -------------------------------------------------
    -- NO LOCK:
    -- FIND TARGET ONCE
    -------------------------------------------------
    local best_sid =
        find_best_target()

    if best_sid ~= 0 then

        -------------------------------------------------
        -- HARD LOCK
        -------------------------------------------------
        lock_target(best_sid)

        -------------------------------------------------
        -- TARGET ONLY; PULLING/COMBAT MODULES OWN ACTIONS.
        -------------------------------------------------
        target_only(best_sid)
    end

    schedule_tick(0.3)
end

-------------------------------------------------
-- PACKET HANDLER
-------------------------------------------------
ashita.events.register(
    'packet_in',
    'targeting_packet_in_cb',
    function(e)

        if not running then
            return
        end

        if e.id == 0x029 then

            local ok_tid, target_id =
                pcall(function()
                    return struct.unpack(
                        'I',
                        e.data,
                        0x04 + 1
                    )
                end)

            local ok_mid, message_id =
                pcall(function()
                    return struct.unpack(
                        'H',
                        e.data,
                        0x18 + 1
                    )
                end)

            -------------------------------------------------
            -- MESSAGE 8
            -------------------------------------------------
            if ok_tid
            and ok_mid
            and message_id == 8
            then

                if target_id ==
                    locked_server_id
                then
                    begin_combat_settle()
                    clear_lock('death_packet')

                    schedule_tick(0.1)
                end
            end
        end
    end
)

-------------------------------------------------
-- CONTROL
-------------------------------------------------
function targeting.set_settings(cfg)

    settings = cfg

    if not settings.target_list then
        settings.target_list = {}
    end
end

function targeting.start()

    if running then
        return
    end

    running = true
    clear_lock('module_start')

    print(chat.header('Targeting') ..
        chat.message('Started!'))

    tick()
end

function targeting.stop()
    local was_running = running
    running = false

    -- Always clear coordination and targeting locks. Stop may be called after
    -- another controller has already marked this module inactive.
    clear_lock('module_stop')

    targeting.stop_facing()

    if was_running then
        print(chat.header('Targeting') ..
            chat.message('Stopped!'))
    end
end

return targeting
