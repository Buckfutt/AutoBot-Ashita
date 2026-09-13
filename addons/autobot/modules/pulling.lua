local pulling = {}

local settings = nil
local running = false
local targeting_module = nil

local state = require('modules.state')

local current_pull_target = 0
local pull_action_sent = false
local pull_action_sent_at = 0
local tick_scheduled = false
local interval = 0.25
local default_timeout = 8
local tick = nil
local schedule_tick = nil
local pull_spell_id = 0
local pull_spell_recast_before = 0
local post_pull_attack_target = 0
local post_pull_attack_attempts = 0
local post_pull_require_spell_start = false
local post_pull_attack_generation = 0
local last_attack_debug_at = 0
local pull_spell_action_started = false
local pull_spell_action_active = false
local pull_spell_action_succeeded = false
local pull_spell_action_started_at = 0
local pull_spell_recast_started = nil
local is_spell_pull = nil
local read_u16 = nil
local read_u32 = nil
local get_player_server_id = nil
local get_incoming_action_type = nil
local get_incoming_action_param = nil

local STATUS_ENGAGED = 2
local CAST_START_WINDOW = 1.5
local CAST_WAIT_TIMEOUT = 12.0
local CAST_POLL_INTERVAL = 0.2
local CAST_FAILURE_RETRY_DELAY = 3.0
local CAST_COMMAND_ACCEPT_TIMEOUT = 2.0
local POST_PULL_ENGAGE_RETRY_DELAY = 0.25
local pull_retry_not_before = 0

-------------------------------------------------
-- HELPERS
-------------------------------------------------
local function cmd(str)
    AshitaCore:GetChatManager():QueueCommand(1, str)
end

local function now()
    return os.clock()
end

local function combat_settling()
    return (state.combat_settle_until or 0) > now()
end

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

local function get_player_status()
    local ok_player, player =
        pcall(function()
            return AshitaCore:GetMemoryManager():GetPlayer()
        end)

    if ok_player and player then
        local ok_status, status =
            pcall(function()
                return player:GetStatus()
            end)

        if ok_status and status ~= nil then
            return status
        end
    end

    local p = party()
    local ent = entity()

    if p and ent then
        local ok_index, player_index =
            pcall(function()
                return p:GetMemberTargetIndex(0)
            end)

        if ok_index and player_index and player_index > 0 then
            local ok_status, status =
                pcall(function()
                    return ent:GetStatus(player_index)
                end)

            if ok_status and status then
                return status
            end
        end
    end

    return 0
end

local function get_player_name()
    local p = party()

    if p then
        local ok, name = pcall(function()
            return p:GetMemberName(0)
        end)

        if ok and name and name ~= '' then
            return tostring(name)
        end
    end

    return ''
end

local function castbar_is_active()

    local castbar = nil

    local ok_global, global_castbar =
        pcall(function()
            if type(GetCastBarSafe) == 'function' then
                return GetCastBarSafe()
            end

            return nil
        end)

    if ok_global and global_castbar then
        castbar = global_castbar
    end

    if not castbar then
        local ok_manager, manager_castbar =
            pcall(function()
                local mem = AshitaCore:GetMemoryManager()

                if mem and mem.GetCastBar then
                    return mem:GetCastBar()
                end

                return nil
            end)

        if ok_manager and manager_castbar then
            castbar = manager_castbar
        end
    end

    if not castbar then
        return false
    end

    local ok_percent, percent =
        pcall(function()
            return castbar:GetPercent()
        end)

    if ok_percent
    and percent
    and percent > 0
    and percent < 1
    then
        return true
    end

    local ok_active, active =
        pcall(function()
            return castbar:GetActive()
        end)

    return ok_active
        and (active == true or active == 1)
end

local function player_is_casting()
    if castbar_is_active() then
        return true
    end

    if pull_spell_action_active then
        if pull_spell_recast_started()
        or (pull_spell_action_started_at > 0
            and (now() - pull_spell_action_started_at) > CAST_WAIT_TIMEOUT)
        then
            pull_spell_action_active = false
            return false
        end

        return true
    end

    return false
end

local function player_is_engaged()
    local status = get_player_status()

    -- Player status 1 is weapon-drawn/engaged. Status 2 must not suppress
    -- engagement merely because the player is being attacked.
    return status == 1
end

local function get_current_target_index()

    local tgt = target_manager()

    if not tgt then
        return -1
    end

    local ok, index = pcall(function()
        return tgt:GetTargetIndex(0)
    end)

    if not ok or not index then
        return -1
    end

    return index
end

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

local function set_target_by_server_id(server_id)

    local tgt = target_manager()

    if not tgt then
        return false
    end

    local index =
        find_index_by_server_id(server_id)

    if index <= 0 then
        return false
    end

    local ok =
        pcall(function()
            tgt:SetTarget(index, true)
        end)

    if ok then
        return true
    end

    ok =
        pcall(function()
            tgt:SetTarget(server_id, index, true)
        end)

    return ok
end

local function get_entity_status(index)

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

local function is_in_combat_with(server_id)

    if not player_is_engaged() then
        return false
    end

    local index =
        find_index_by_server_id(server_id)

    return index > 0
        and get_entity_status(index) == 1
end

local function normalize_name(name)

    if type(name) ~= 'string' then
        return ''
    end

    return name:lower():gsub("^%s*(.-)%s*$", "%1")
end

local function get_resource_name(value)

    if type(value) == 'string' then
        return value
    end

    if not value then
        return nil
    end

    for _, index in ipairs({ 1, 0, 2 }) do
        local ok, name = pcall(function()
            return value[index]
        end)

        if ok and type(name) == 'string' then
            return name
        end
    end

    return nil
end

local function reset_pull_state(preserve_post_attack)

    current_pull_target = 0
    pull_action_sent = false
    pull_action_sent_at = 0
    pull_spell_id = 0
    pull_spell_recast_before = 0
    pull_spell_action_started = false
    pull_spell_action_active = false
    pull_spell_action_succeeded = false
    pull_spell_action_started_at = 0
    pull_retry_not_before = 0

    if not preserve_post_attack then
        post_pull_attack_target = 0
        post_pull_attack_attempts = 0
        post_pull_require_spell_start = false
        last_attack_debug_at = 0
    end

    state.pull_in_progress = false
    state.pull_target_id = 0
    state.pull_started_at = 0
    state.pull_completed = false
end

local function ensure_attack_started(server_id)
    if not server_id or server_id == 0 then
        return
    end

    if post_pull_attack_target == server_id then
        return
    end

    post_pull_attack_target = server_id
    post_pull_attack_attempts = 0
    post_pull_require_spell_start = false
    post_pull_attack_generation = post_pull_attack_generation + 1
    local generation = post_pull_attack_generation

    local function attempt()
        if post_pull_attack_target ~= server_id
        or post_pull_attack_generation ~= generation
        then
            return
        end

        local t_index = find_index_by_server_id(server_id)
        local ent = entity()
        if not ent
        or t_index <= 0
        or ent:GetServerId(t_index) ~= server_id
        or (ent:GetHPPercent(t_index) or 0) <= 0
        then
            post_pull_attack_target = 0
            post_pull_attack_attempts = 0
            return
        end

        post_pull_attack_attempts = post_pull_attack_attempts + 1
        if post_pull_attack_attempts > 20 then
            post_pull_attack_target = 0
            post_pull_attack_attempts = 0
            state.force_retarget = true
            state.force_retarget_reason = 'engage_not_accepted'
            return
        end

        set_target_by_server_id(server_id)
        if post_pull_attack_attempts == 1 then
            -- Menu mode bypasses typed-chat command handling and mirrors
            -- selecting Attack from the game's action menu.
            AshitaCore:GetChatManager():QueueCommand(0, '/attack on')
        else
            -- Typed mode is a compatibility fallback if menu mode produced
            -- no outgoing attack packet.
            cmd('/attack on')
        end

        -- handle_packet_out clears the pending target as soon as FFXI accepts
        -- the attack packet. Retry only while no packet was produced.
        ashita.tasks.once(POST_PULL_ENGAGE_RETRY_DELAY, attempt)
    end

    attempt()
end

local function cancel_post_pull_engagement(reason)
    post_pull_attack_target = 0
    post_pull_attack_attempts = 0
    post_pull_require_spell_start = false
    post_pull_attack_generation = post_pull_attack_generation + 1

    if current_pull_target ~= 0 then
        state.pull_in_progress = true
        state.pull_target_id = current_pull_target
        state.pull_completed = false
    end
end

local function start_attack_handoff(server_id, reason, require_spell_start)

    if not server_id or server_id == 0 then
        return
    end

    ensure_attack_started(server_id, require_spell_start)
end

local function complete_spell_pull(reason)
    if pull_spell_action_succeeded then
        return
    end

    local server_id = current_pull_target
    if not running
    or server_id == 0
    or state.pull_in_progress ~= true
    or state.pull_target_id ~= server_id
    then
        return
    end

    pull_spell_action_started = true
    pull_spell_action_active = false
    pull_spell_action_succeeded = true
    pull_spell_action_started_at = 0

    current_pull_target = server_id
    pull_action_sent = true
    state.pull_in_progress = false
    state.pull_target_id = server_id
    state.pull_completed = true
    start_attack_handoff(server_id, reason, false)

    schedule_tick(0)
end

local function get_claim_id(index)

    local ent = entity()

    if not ent then
        return 0
    end

    local ok, claim_status =
        pcall(function()
            return ent:GetClaimStatus(index)
        end)

    if not ok or not claim_status then
        return 0
    end

    return bit.band(claim_status, 0xFFFF)
end

local function is_party_claim(claim_id)

    if not claim_id or claim_id == 0 then
        return false
    end

    local p = party()

    if not p then
        return false
    end

    for i = 0, 17 do
        local member_server_id = p:GetMemberServerId(i)

        if p:GetMemberIsActive(i) == 1
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

local function request_retarget(reason)

    reason = reason or 'pull_failed'

    if state.force_retarget == true
    and state.force_retarget_reason == reason
    then
        return
    end

    if player_is_engaged()
    or post_pull_attack_target ~= 0
    or state.pull_completed == true
    then
        reset_pull_state(true)
        return
    end

    state.force_retarget = true
    state.force_retarget_reason = reason

    reset_pull_state()
end

local function get_spell_id(name)

    local wanted = normalize_name(name)

    if wanted == '' then
        return 0
    end

    local res = AshitaCore:GetResourceManager()

    if not res then
        return 0
    end

    for i = 0, 1024 do

        local spell = res:GetSpellById(i)

        local spell_name = nil

        if spell and spell.Name then
            spell_name = get_resource_name(spell.Name)
        end

        if spell_name
        and normalize_name(spell_name) == wanted
        then
            return i
        end
    end

    return 0
end

local function get_spell_recast(spell_id)

    if not spell_id or spell_id == 0 then
        return 0
    end

    local recast = AshitaCore:GetMemoryManager():GetRecast()

    if not recast then
        return 0
    end

    local ok, timer =
        pcall(function()
            return recast:GetSpellTimer(spell_id)
        end)

    if not ok or not timer then
        return 0
    end

    return timer
end

pull_spell_recast_started = function()

    if pull_spell_id == 0 then
        return false
    end

    local current =
        get_spell_recast(pull_spell_id)

    if pull_spell_recast_before <= 0 then
        return current > 0
    end

    -- An existing cooldown is not proof that this cast succeeded.
    return current > pull_spell_recast_before
end

schedule_tick = function(delay)

    if tick_scheduled then
        return
    end

    tick_scheduled = true

    ashita.tasks.once(
        delay or interval,
        function()

            tick_scheduled = false

            if running then
                tick()
            end
        end
    )
end

-------------------------------------------------
-- SETTINGS
-------------------------------------------------
function pulling.set_settings(cfg)
    settings = cfg
end

function pulling.set_modules(targeting)
    targeting_module = targeting
end

function pulling.handle_packet_out(e)
    if e
    and e.id == 0x01A
    and post_pull_attack_target ~= 0
    then
        local outgoing_category = read_u16(e.data, 0x0A + 1)
        if outgoing_category == 0x02 then
            local engaged_target = post_pull_attack_target
            post_pull_attack_target = 0
            post_pull_attack_attempts = 0
            post_pull_attack_generation = post_pull_attack_generation + 1
            local confirmation_generation = post_pull_attack_generation

            -- Idempotent confirmation pulse: /attack on cannot toggle combat
            -- off if the first accepted packet already engaged successfully.
            ashita.tasks.once(0.75, function()
                if engaged_target and engaged_target ~= 0
                and post_pull_attack_generation == confirmation_generation
                and state.pull_completed == true
                and state.pull_target_id == engaged_target
                and find_index_by_server_id(engaged_target) > 0
                then
                    set_target_by_server_id(engaged_target)
                    AshitaCore:GetChatManager():QueueCommand(0, '/attack on')
                end
            end)
        end
    end

    if state.pull_completed == true
    or not pull_action_sent
    or not is_spell_pull()
    or pull_spell_id == 0
    or not e
    or e.id ~= 0x01A
    then
        return
    end

    local category = read_u16(e.data, 0x0A + 1)
    local action_id = read_u16(e.data, 0x0C + 1)

    if category ~= 0x03
    or action_id ~= pull_spell_id
    then
        return
    end

    -- LuAshitaCast may reinject the same outgoing action packet after its
    -- precast processing. Track it once.
    if pull_spell_action_started and pull_spell_action_active then
        return
    end

    pull_spell_action_started = true
    pull_spell_action_active = true
    pull_spell_action_succeeded = false
    pull_spell_action_started_at = now()
end

function pulling.handle_packet_in(e)

    if not pull_spell_action_active
    or not e
    or e.id ~= 0x028
    then
        return
    end

    local actor_id = read_u32(e.data, 0x05 + 1)

    if actor_id ~= get_player_server_id() then
        return
    end

    local action_type = get_incoming_action_type(e)

    local action_param = get_incoming_action_param(e)
    if (action_type == 8 or action_type == 12)
    and action_param == 28787
    then
        pull_action_sent = false
        pull_action_sent_at = 0
        pull_spell_action_started = false
        pull_spell_action_active = false
        pull_spell_action_succeeded = false
        pull_spell_action_started_at = 0
        cancel_post_pull_engagement('spell_interrupted')
        pull_retry_not_before = now() + CAST_FAILURE_RETRY_DELAY

        if running then
            schedule_tick(0)
        end
    end
end

function pulling.handle_text(e)
    if not running
    or not is_spell_pull()
    or not e
    then
        return
    end

    local text = tostring(e.message or e.message_modified or '')
        :gsub('%c', '')
        :match('^%s*(.-)%s*$')
        :lower()
    local player_name = get_player_name():lower()
    local spell_name = normalize_name(settings.pulling.spell)

    if text == '' or player_name == '' or spell_name == '' then
        return
    end

    -- Ignore AutoBot's own chat output as a possible game action message.
    if text:find('[autobot]', 1, true) then
        return
    end

    local player_seen = text:find(player_name, 1, true) ~= nil
    local cast_started = text:find('starts casting ' .. spell_name .. ' on ', 1, true) ~= nil
    local cast_completed = text:find('casts ' .. spell_name, 1, true) ~= nil

    if player_seen and cast_started then
        pull_spell_action_started = true
        pull_spell_action_active = true
        pull_spell_action_succeeded = false
        pull_spell_action_started_at = now()
        return
    end

    if player_seen and cast_completed then
        complete_spell_pull('spell completion confirmed by chat')
        return
    end

    local failed = text:find('unable to cast spells at this time', 1, true)
        or text:find('is out of range', 1, true)
        or text:find('spell is interrupted', 1, true)
        or text:find('cannot cast', 1, true)

    if failed
    and state.pull_completed == true
    then
        return
    end

    if failed and (pull_spell_action_started or pull_spell_action_active) then
        pull_action_sent = false
        pull_action_sent_at = 0
        pull_spell_action_started = false
        pull_spell_action_active = false
        pull_spell_action_succeeded = false
        pull_spell_action_started_at = 0
        cancel_post_pull_engagement('spell_chat_failure')
        pull_retry_not_before = now() + CAST_FAILURE_RETRY_DELAY
        schedule_tick(0)
    end
end

-------------------------------------------------
-- VALID TARGET
-------------------------------------------------
local function is_valid_target(name)

    if not name or not settings then
        return false
    end

    local lower = normalize_name(name)

    for _, v in ipairs(settings.target_list or {}) do

        if lower == normalize_name(v) then
            return true
        end
    end

    return false
end

local function get_pull_timeout()

    if settings
    and settings.pulling
    and tonumber(settings.pulling.timeout)
    then
        return tonumber(settings.pulling.timeout)
    end

    return default_timeout
end

local function has_configured_pull_action()

    settings.pulling = settings.pulling or {}

    return (settings.pulling.use_spell and normalize_name(settings.pulling.spell) ~= '')
        or (settings.pulling.use_ability and normalize_name(settings.pulling.ability) ~= '')
        or settings.pulling.use_ranged == true
end

is_spell_pull = function()
    settings.pulling = settings.pulling or {}

    return settings.pulling.use_spell == true
        and normalize_name(settings.pulling.spell) ~= ''
end

local function send_pull_action()

    settings.pulling = settings.pulling or {}

    if now() < pull_retry_not_before then
        return false
    end

    settings.pulling.spell =
        normalize_name(settings.pulling.spell) ~= ''
        and settings.pulling.spell
        or ''

    settings.pulling.ability =
        normalize_name(settings.pulling.ability) ~= ''
        and settings.pulling.ability
        or ''

    if settings.pulling.use_spell
    and settings.pulling.spell ~= ''
    then
        pull_spell_action_started = false
        pull_spell_action_active = false
        pull_spell_action_succeeded = false
        pull_spell_action_started_at = 0
        pull_retry_not_before = 0

        pull_spell_id =
            get_spell_id(settings.pulling.spell)

        pull_spell_recast_before =
            get_spell_recast(pull_spell_id)

        cmd(string.format(
            '/ma "%s" <t>',
            settings.pulling.spell
        ))

        pull_action_sent_at = now()
        -- Timeout is per action attempt. Earlier failures/recovery delays must
        -- not consume the successful retry's completion window.
        state.pull_started_at = pull_action_sent_at

        return true

    elseif settings.pulling.use_ability
    and settings.pulling.ability ~= ''
    then
        cmd(string.format(
            '/ja "%s" <t>',
            settings.pulling.ability
        ))

        pull_action_sent_at = now()

        return true

    elseif settings.pulling.use_ranged then
        cmd('/ra <t>')

        pull_action_sent_at = now()

        return true

    end

    pull_action_sent_at = now()

    return true
end

local function pull_action_confirmed(status, hp, claim_id)

    if not has_configured_pull_action() then
        return true
    end

    if is_spell_pull() then
        return pull_spell_action_succeeded
    end

    return status == STATUS_ENGAGED
        or hp < 100
        or is_party_claim(claim_id)
end

read_u16 = function(data, offset)

    if type(data) ~= 'string' then
        return 0
    end

    local lo = data:byte(offset) or 0
    local hi = data:byte(offset + 1) or 0

    return lo + (hi * 0x100)
end

read_u32 = function(data, offset)

    if type(data) ~= 'string' then
        return 0
    end

    local b1 = data:byte(offset) or 0
    local b2 = data:byte(offset + 1) or 0
    local b3 = data:byte(offset + 2) or 0
    local b4 = data:byte(offset + 3) or 0

    return b1 + (b2 * 0x100) + (b3 * 0x10000) + (b4 * 0x1000000)
end

get_player_server_id = function()

    local p = party()

    if not p then
        return 0
    end

    local ok, server_id =
        pcall(function()
            return p:GetMemberServerId(0)
        end)

    return ok and server_id or 0
end

get_incoming_action_type = function(e)

    if not e then
        return 0
    end

    local ok, action_type =
        pcall(function()
            return ashita.bits.unpack_be(e.data_raw, 10, 2, 4)
        end)

    return ok and action_type or 0
end

get_incoming_action_param = function(e)

    if not e then
        return 0
    end

    local ok, param =
        pcall(function()
            return ashita.bits.unpack_be(e.data_raw, 10, 6, 16)
        end)

    return ok and param or 0
end

-------------------------------------------------
-- LOOP
-------------------------------------------------
tick = function()

    if not running then
        return
    end

    if state.mounted == true then
        schedule_tick(0.5)
        return
    end

    local ent = entity()

    if not ent or not settings then
        schedule_tick(0.5)
        return
    end

    if combat_settling() then
        reset_pull_state()
        schedule_tick(0.3)
        return
    end

    if player_is_engaged()
    and (
        state.pull_completed == true
        or state.pull_in_progress ~= true
    )
    then
        reset_pull_state(true)
        schedule_tick(0.5)
        return
    end

    -------------------------------------------------
    -- SAFE TARGET INDEX
    -------------------------------------------------
    local t_index = get_current_target_index()

    if not t_index or t_index <= 0 then

        reset_pull_state(true)
        schedule_tick(0.5)
        return
    end

    -------------------------------------------------
    -- TARGET INFO
    -------------------------------------------------
    local name = ent:GetName(t_index)

    if not name then

        reset_pull_state(true)
        schedule_tick(0.5)
        return
    end

    -------------------------------------------------
    -- VALID TARGET
    -------------------------------------------------
    if not is_valid_target(name) then

        reset_pull_state(true)
        schedule_tick(0.5)
        return
    end

    local server_id =
        ent:GetServerId(t_index) or 0

    if server_id == 0 then
        reset_pull_state(true)
        schedule_tick(0.5)
        return
    end

    -------------------------------------------------
    -- TARGETING OWNS TARGET SELECTION.
    -- After a forced retarget it clears target_server_id before selecting a
    -- replacement; do not recreate a pull from FFXI's stale visible target.
    -------------------------------------------------
    if state.target_server_id == 0
    or state.target_server_id ~= server_id
    then
        if current_pull_target ~= 0 then
        end
        reset_pull_state()
        schedule_tick(interval)
        return
    end

    local hp =
        ent:GetHPPercent(t_index)

    if not hp or hp <= 0 then
        reset_pull_state(true)
        schedule_tick(0.5)
        return
    end

    -------------------------------------------------
    -- TARGET STATUS
    -- Ashita entity status: 1 = idle, 2 = engaged.
    -------------------------------------------------
    local status = ent:GetStatus(t_index)
    local claim_id = get_claim_id(t_index)

    -------------------------------------------------
    -- SOMEONE ELSE CLAIMED IT WHILE WE WERE SETTING UP.
    -------------------------------------------------
    if claim_id ~= 0
    and not is_party_claim(claim_id)
    then
        request_retarget('claimed_by_other')
        schedule_tick(interval)
        return
    end

    -------------------------------------------------
    -- COMPLETION/HANDOFF WAS ALREADY STARTED BY THE SPELL CHAT HANDLER.
    -- Do not let the polling loop arm a second engagement after the first
    -- outgoing attack packet clears post_pull_attack_target.
    -------------------------------------------------
    if state.pull_completed == true
    or post_pull_attack_target ~= 0
    then
        schedule_tick(0.5)
        return
    end

    -------------------------------------------------
    -- FIGHT HAS STARTED OR TARGET HAS BEEN HIT.
    -- PULL IS COMPLETE; DO NOT CAST/SPAM AGAIN.
    -------------------------------------------------
    if pull_action_sent
    and pull_action_confirmed(status, hp, claim_id)
    then


        current_pull_target = server_id
        pull_action_sent = true

        state.pull_in_progress = false
        state.pull_target_id = server_id
        state.pull_completed = true

        start_attack_handoff(server_id, 'pull confirmed')

        schedule_tick(0.5)
        return
    end

    local spell_pull_ready = not is_spell_pull()
        or pull_spell_action_succeeded

    if spell_pull_ready
    and (
        hp < 100
        or is_party_claim(claim_id)
        or (pull_action_sent and status == STATUS_ENGAGED)
    )
    then


        current_pull_target = server_id
        pull_action_sent = true

        state.pull_in_progress = false
        state.pull_target_id = server_id
        state.pull_completed = true

        start_attack_handoff(server_id, 'pull target active')

        schedule_tick(0.5)
        return
    end

    -------------------------------------------------
    -- NEW TARGET: START A SINGLE PULL WINDOW
    -------------------------------------------------
    if current_pull_target ~= server_id then

        current_pull_target = server_id
        pull_action_sent = false
        pull_action_sent_at = 0
        pull_spell_action_started = false
        pull_spell_action_active = false
        pull_spell_action_succeeded = false
        pull_spell_action_started_at = 0
        pull_retry_not_before = 0

        state.pull_in_progress = true
        state.pull_target_id = server_id
        state.pull_started_at = now()
        state.pull_completed = false
    end

    -------------------------------------------------
    -- SEND THE CONFIGURED PULL ACTION BEFORE ATTACKING.
    -- This keeps fast job scripts/pet logic from interrupting spell pulls.
    -------------------------------------------------
    if not pull_action_sent then
        pull_action_sent =
            send_pull_action()
    end

    -------------------------------------------------
    -- SPELL PULL RETRY: IF THE CAST NEVER STARTED,
    -- TRY AGAIN INSTEAD OF STANDING WITH WEAPON OUT.
    -------------------------------------------------
    if pull_action_sent
    and is_spell_pull()
    and pull_spell_id ~= 0
    and not player_is_casting()
    and not pull_spell_recast_started()
    and (now() - pull_action_sent_at) >= CAST_COMMAND_ACCEPT_TIMEOUT
    and hp >= 100
    then
        post_pull_attack_target = 0
        post_pull_attack_attempts = 0
        post_pull_require_spell_start = false
        pull_spell_action_active = false
        pull_spell_action_succeeded = false
        pull_spell_action_started_at = 0
        pull_action_sent = false
        pull_action_sent_at = 0
        schedule_tick(0)
        return
    end

    -------------------------------------------------
    -- TIMEOUT: TARGET DID NOT PULL, ASK TARGETING
    -- TO DROP IT AND SELECT A NEW MOB.
    -------------------------------------------------
    if state.pull_started_at > 0
    and (now() - state.pull_started_at) >= get_pull_timeout()
    and not state.pull_completed
    and post_pull_attack_target == 0
    and not pull_spell_action_active
    and not player_is_casting()
    and now() >= pull_retry_not_before
    then
        request_retarget('pull_timeout')
    end

    schedule_tick(interval)
end

-------------------------------------------------
-- CONTROL
-------------------------------------------------
function pulling.start()

    if running then
        return
    end

    running = true

    schedule_tick(0)
end

function pulling.stop()

    running = false
    reset_pull_state()
end

return pulling
