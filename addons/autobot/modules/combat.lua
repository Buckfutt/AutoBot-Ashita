local combat = {}

local settings = nil
local approaching = false
local approach_moving = false
local face_loop_active = false
local movement_autoface_enabled = false
local last_movement_autoface_command = 0
local last_navface_command = 0
local shutting_down = false
local last_face_error = 0
local last_auto_assist_attempt = 0
local auto_assist_pending = false
local last_auto_engage_attempt = 0
local last_heal_command = 0
local rest_resume_at = 0
local turn_key_down = nil
local MELEE_RANGE = 2.5
local AUTO_ASSIST_COOLDOWN = 3.0
local AUTO_ENGAGE_COOLDOWN = 0.75
local pull_state = require('modules.state')
local STATUS_ENGAGED = 2
local STATUS_RESTING = 33
local get_player_status
local player_is_engaged
local pull_in_progress

local ffi_ok, ffi = pcall(require, 'ffi')
local user32 = nil

if ffi_ok then
    pcall(function()
        ffi.cdef[[
            void __stdcall keybd_event(unsigned char bVk, unsigned char bScan, unsigned long dwFlags, uintptr_t dwExtraInfo);
        ]]
        user32 = ffi.load('user32')
    end)
end

local VK_LEFT = 0x25
local VK_RIGHT = 0x27
local KEYEVENTF_KEYUP = 0x0002

-------------------------------------------------
-- HELPERS
-------------------------------------------------
local function cmd(str)
    AshitaCore:GetChatManager():QueueCommand(1, str)
end

local function face_debug(message)
    if pull_state.debug ~= true then
        return
    end

    if (os.clock() - last_face_error) < 3 then
        return
    end

    last_face_error = os.clock()
    cmd('/echo [AutoBot] Auto-face: ' .. tostring(message))
end

local function set_movement_autoface(enabled, force)
    local now = os.clock()
    local should_refresh = enabled and ((now - last_movement_autoface_command) >= 1.0)

    if not force and not should_refresh and movement_autoface_enabled == enabled then
        return
    end

    movement_autoface_enabled = enabled
    last_movement_autoface_command = now
    cmd(enabled and '/movement navautoface on' or '/movement navautoface off')
end

local function get_player()
    return AshitaCore:GetMemoryManager():GetPlayer()
end

local function get_entity()
    return AshitaCore:GetMemoryManager():GetEntity()
end

local function get_player_entity(player_index)
    local ok_global, global_entity =
        pcall(function()
            if type(GetPlayerEntity) == 'function' then
                return GetPlayerEntity()
            end

            return nil
        end)

    if ok_global and global_entity then
        return global_entity
    end

    if player_index and player_index > 0 then
        local ok_index, indexed =
            pcall(function()
                if type(GetEntity) == 'function' then
                    return GetEntity(player_index)
                end

                return nil
            end)

        if ok_index and indexed then
            return indexed
        end
    end

    return nil
end

local function get_party()
    return AshitaCore:GetMemoryManager():GetParty()
end

local function get_target_manager()
    return AshitaCore:GetMemoryManager():GetTarget()
end

local function is_chat_input_open()
    local ok, state =
        pcall(function()
            return AshitaCore:GetChatManager():IsInputOpen()
        end)

    return ok and state and state ~= 0
end

local function key_event(vk, down)
    if not user32 then
        return false
    end

    local ok =
        pcall(function()
            user32.keybd_event(vk, 0, down and 0 or KEYEVENTF_KEYUP, 0)
        end)

    return ok
end

local function release_turn_keys()
    key_event(VK_LEFT, false)
    key_event(VK_RIGHT, false)
    turn_key_down = nil
end

local function pulse_turn_key(direction)
    local vk = direction == 'right' and VK_RIGHT or VK_LEFT

    if turn_key_down and turn_key_down ~= vk then
        key_event(turn_key_down, false)
    end

    if not key_event(vk, true) then
        return false
    end

    turn_key_down = vk

    ashita.tasks.once(0.05, function()
        if turn_key_down == vk then
            key_event(vk, false)
            turn_key_down = nil
        end
    end)

    return true
end

local function get_player_index()
    local party = get_party()

    if not party then
        return -1
    end

    local ok, index =
        pcall(function()
            return party:GetMemberTargetIndex(0)
        end)

    if not ok or not index then
        return -1
    end

    return index
end

local function get_current_target_index()
    local target = get_target_manager()
    local ent = get_entity()
    local player_index = get_player_index()

    local function valid_target(index)
        return index and index > 0 and index ~= player_index
    end

    if target then
        local ok_active, active =
            pcall(function()
                return target:GetIsSubTargetActive()
            end)

        local slot = (ok_active and active == 1) and 1 or 0
        local ok, index =
            pcall(function()
                return target:GetTargetIndex(slot)
            end)

        if ok and valid_target(index) then
            return index
        end

        ok, index =
            pcall(function()
                return target:GetTargetIndex(0)
            end)

        if ok and valid_target(index) then
            return index
        end

        ok, index =
            pcall(function()
                return target:GetTargetIndex(1)
            end)

        if ok and valid_target(index) then
            return index
        end

        ok, index =
            pcall(function()
                return target:GetFocusTargetIndex()
            end)

        if ok and valid_target(index) then
            return index
        end

        ok, index =
            pcall(function()
                return target:GetLastTargetIndex()
            end)

        if ok and valid_target(index) then
            return index
        end
    end

    if ent and player_index > 0 then
        local ok_entity_target, entity_target_index =
            pcall(function()
                return ent:GetTargetIndex(player_index)
            end)

        if ok_entity_target and valid_target(entity_target_index) then
            return entity_target_index
        end
    end

    return -1
end

local function get_entity_by_index(index)
    local ent = get_entity()

    if not ent or not index or index <= 0 then
        return nil
    end

    local ok_entity, value =
        pcall(function()
            return ent:GetEntity(index)
        end)

    if ok_entity and value then
        return value
    end

    local ok_index, indexed =
        pcall(function()
            return ent[index]
        end)

    if ok_index and indexed then
        return indexed
    end

    return nil
end

local function get_position(index)
    local ent = get_entity()

    if not ent or not index or index <= 0 then
        return nil
    end

    local ok_x, x =
        pcall(function()
            return ent:GetLocalPositionX(index)
        end)

    local ok_y, y =
        pcall(function()
            return ent:GetLocalPositionY(index)
        end)

    if ok_x and ok_y and x and y then
        return { X = x, Z = y }
    end

    local ok_z, z =
        pcall(function()
            return ent:GetLocalPositionZ(index)
        end)

    if ok_x and ok_z and x and z then
        return { X = x, Z = z }
    end

    local entity = get_entity_by_index(index)

    if entity and entity.Movement and entity.Movement.LocalPosition then
        local pos = entity.Movement.LocalPosition

        if pos.X and pos.Z then
            return { X = pos.X, Z = pos.Z }
        end
    end

    if entity and entity.Pos and entity.Pos.X then
        if entity.Pos.Z then
            return { X = entity.Pos.X, Z = entity.Pos.Z }
        elseif entity.Pos.Y then
            return { X = entity.Pos.X, Z = entity.Pos.Y }
        end
    end

    return nil
end

-------------------------------------------------
-- SETTINGS
-------------------------------------------------
function combat.set_settings(cfg)
    shutting_down = false
    settings = cfg

    settings.combat = settings.combat or {}
    settings.combat.approach = settings.combat.approach or false
    settings.combat.auto_face = settings.combat.auto_face or false
    settings.combat.auto_assist = settings.combat.auto_assist == true
    settings.combat.assist_target = settings.combat.assist_target or ''
    settings.combat.face_reverse = settings.combat.face_reverse == true
    settings.combat.manage_hp = settings.combat.manage_hp == true
    settings.combat.hp_minimum = tonumber(settings.combat.hp_minimum) or 0
    settings.combat.hp_maximum = tonumber(settings.combat.hp_maximum) or 100
    settings.combat.manage_mp = settings.combat.manage_mp == true
    settings.combat.mp_minimum = tonumber(settings.combat.mp_minimum) or 0
    settings.combat.mp_maximum = tonumber(settings.combat.mp_maximum) or 100
end

local function get_player_resource_percentages()
    local party = get_party()
    if not party then
        return nil, nil
    end

    local ok_hp, hp = pcall(function()
        return party:GetMemberHPPercent(0)
    end)
    local ok_mp, mp = pcall(function()
        return party:GetMemberMPPercent(0)
    end)

    return ok_hp and tonumber(hp) or nil, ok_mp and tonumber(mp) or nil
end

local function resource_below_minimum(value, enabled, minimum)
    return enabled and value ~= nil and value <= minimum
end

local function resource_at_maximum(value, enabled, maximum)
    return not enabled or (value ~= nil and value >= maximum)
end

local function resting_tick()
    local now = os.clock()

    if pull_state.zone_in_progress == true
    or now < (tonumber(pull_state.resource_settle_until) or 0)
    then
        pull_state.player_resting = false
        rest_resume_at = 0
        return false
    end

    local hp, mp = get_player_resource_percentages()
    local combat_settings = settings.combat

    if pull_state.player_resting == true then
        if rest_resume_at > 0 then
            if now >= rest_resume_at then
                pull_state.player_resting = false
                rest_resume_at = 0
            end
            return true
        end

        local hp_ready = resource_at_maximum(
            hp, combat_settings.manage_hp, combat_settings.hp_maximum)
        local mp_ready = resource_at_maximum(
            mp, combat_settings.manage_mp, combat_settings.mp_maximum)
        local player_status = get_player_status()

        if hp_ready
        and mp_ready
        and player_status == STATUS_RESTING
        and (now - last_heal_command) >= 1.0
        then
            last_heal_command = now
            rest_resume_at = now + 3.0
            cmd('/heal')
        elseif hp_ready
        and mp_ready
        and player_status ~= STATUS_RESTING
        and (now - last_heal_command) >= 1.0
        then
            -- The original /heal can be ignored during login or another
            -- transition. Do not send a second command that would sit down.
            pull_state.player_resting = false
        elseif not hp_ready
        or not mp_ready
        then
            -- Retry the initial sit command if the game has not entered its
            -- resting status yet.
            if player_status ~= STATUS_RESTING
            and (now - last_heal_command) >= 3.0
            then
                last_heal_command = now
                cmd('/heal')
            end
        end
        return true
    end

    local needs_rest =
        resource_below_minimum(
            hp, combat_settings.manage_hp, combat_settings.hp_minimum)
        or resource_below_minimum(
            mp, combat_settings.manage_mp, combat_settings.mp_minimum)

    if needs_rest
    and not player_is_engaged()
    and not pull_in_progress()
    and (now - last_heal_command) >= 1.0
    then
        pull_state.player_resting = true
        last_heal_command = now
        combat.suspend_approach()
        cmd('/heal')
        return true
    end

    return false
end

local function trim(value)
    return (value and tostring(value):match('^%s*(.-)%s*$')) or ''
end

get_player_status = function()
    local player_status = nil
    local player = get_player()
    if player then
        local ok_player, value =
            pcall(function()
                return player:GetStatus()
            end)

        if ok_player and value ~= nil then
            player_status = tonumber(value)
        end
    end

    local ent = get_entity()
    local player_index = get_player_index()
    local entity_status = nil

    if ent and player_index > 0 then
        local ok, value =
            pcall(function()
                return ent:GetStatus(player_index)
            end)

        if ok and value ~= nil then
            entity_status = tonumber(value)
        end
    end

    -- Either interface may lag by a frame. Engagement is authoritative if
    -- either reports weapon-drawn status 1.
    if player_status == 1 or entity_status == 1 then
        return 1
    end

    return entity_status or player_status or 0
end

local function find_entity_index_by_name(name)
    local ent = get_entity()
    local wanted = trim(name):lower()

    if not ent or wanted == '' then
        return -1
    end

    for i = 0, 2048 do
        local ok, entity_name =
            pcall(function()
                return ent:GetName(i)
            end)

        if ok and entity_name and entity_name ~= '' and entity_name:lower() == wanted then
            return i
        end
    end

    return -1
end

local function get_entity_status(index)
    local ent = get_entity()

    if not ent or not index or index <= 0 then
        return 0
    end

    local ok, status =
        pcall(function()
            return ent:GetStatus(index)
        end)

    if ok and status then
        return status
    end

    return 0
end

local function is_engaged_status(status)
    return status == 1
        or status == STATUS_ENGAGED
end

player_is_engaged = function()
    return get_player_status() == 1
end

local function is_targetable_enemy(index)
    local ent = get_entity()

    if not ent or not index or index <= 0 or index == get_player_index() then
        return false
    end

    local ok_sid, server_id =
        pcall(function()
            return ent:GetServerId(index)
        end)

    if not ok_sid or not server_id or server_id == 0 then
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

local function get_entity_target_index(index)
    local ent = get_entity()

    if not ent or not index or index <= 0 then
        return -1
    end

    local ok, target_index =
        pcall(function()
            return ent:GetTargetIndex(index)
        end)

    if ok and target_index and target_index > 0 then
        return target_index
    end

    return -1
end

local function get_target_status()
    local ent = get_entity()
    local target_index = get_current_target_index()

    if not ent or target_index <= 0 then
        return 0
    end

    local ok, status =
        pcall(function()
            return ent:GetStatus(target_index)
        end)

    if not ok or not status then
        return 0
    end

    return status
end

local function is_combat_active()
    return player_is_engaged()
        or is_engaged_status(get_target_status())
end

pull_in_progress = function()
    return pull_state
        and pull_state.pull_in_progress == true
        and pull_state.pull_completed ~= true
end

local function normalize_rotation(rotation)
    local full = math.pi * 2
    rotation = rotation % full

    if rotation < 0 then
        rotation = rotation + full
    end

    return rotation
end

local function normalize_signed_rotation(rotation)
    rotation = normalize_rotation(rotation)

    if rotation > math.pi then
        rotation = rotation - (math.pi * 2)
    end

    return rotation
end

local function rotation_difference(a, b)
    local full = math.pi * 2
    local diff = (normalize_rotation(a) - normalize_rotation(b) + math.pi) % full - math.pi

    return math.abs(diff)
end

local function signed_rotation_delta(target, current)
    local full = math.pi * 2

    return (normalize_rotation(target) - normalize_rotation(current) + math.pi) % full - math.pi
end

local function atan2(y, x)
    if math.atan2 then
        return math.atan2(y, x)
    end

    if x > 0 then
        return math.atan(y / x)
    elseif x < 0 and y >= 0 then
        return math.atan(y / x) + math.pi
    elseif x < 0 and y < 0 then
        return math.atan(y / x) - math.pi
    elseif x == 0 and y > 0 then
        return math.pi / 2
    elseif x == 0 and y < 0 then
        return -math.pi / 2
    end

    return 0
end

local function calculate_rotation(dx, dz)
    return normalize_signed_rotation(atan2(dx, dz) - (math.pi / 2))
end

local function read_rotation_state(player_index)
    local state = {}
    local ent = get_entity()
    local player_entity = get_player_entity(player_index)

    if player_entity then
        if player_entity.Movement then
            if player_entity.Movement.LocalPosition then
                state.local_yaw = player_entity.Movement.LocalPosition.Yaw
            end

            if player_entity.Movement.LastPosition then
                state.last_yaw = player_entity.Movement.LastPosition.Yaw
            end

            if player_entity.Movement.Move then
                state.move_delta_yaw = player_entity.Movement.Move.DeltaYaw
            end
        end

        state.heading = player_entity.Heading
    end

    if ent and player_index and player_index > 0 then
        local ok_local, local_yaw =
            pcall(function()
                return ent:GetLocalPositionYaw(player_index)
            end)

        if ok_local and local_yaw then
            state.entity_local_yaw = local_yaw
        end

        local ok_last, last_yaw =
            pcall(function()
                return ent:GetLastPositionYaw(player_index)
            end)

        if ok_last and last_yaw then
            state.entity_last_yaw = last_yaw
        end

        local ok_delta, delta_yaw =
            pcall(function()
                return ent:GetMoveDeltaYaw(player_index)
            end)

        if ok_delta and delta_yaw then
            state.entity_move_delta_yaw = delta_yaw
        end

        local ok_heading, heading =
            pcall(function()
                return ent:GetHeading(player_index)
            end)

        if ok_heading and heading then
            state.entity_heading = heading
        end
    end

    return state
end

local function first_rotation_value(state)
    return state.local_yaw
        or state.entity_local_yaw
        or state.heading
        or state.entity_heading
        or state.last_yaw
        or state.entity_last_yaw
end

local function set_player_rotation(player_index, rotation)
    local player = get_player()
    local ent = get_entity()
    local player_entity = get_player_entity(player_index)

    if not player and not ent and not player_entity then
        return false, 'missing player/entity'
    end

    local errors = {}
    local changed = false
    local before = read_rotation_state(player_index)

    local function try_set(label, fn)
        local ok, err = pcall(fn)

        if ok then
            changed = true
            return
        end

        errors[#errors + 1] = label .. ': ' .. tostring(err)
    end

    if player_entity then
        try_set('GetPlayerEntity().Movement.LocalPosition.Yaw', function()
            if player_entity.Movement and player_entity.Movement.LocalPosition then
                player_entity.Movement.LocalPosition.Yaw = rotation
                return
            end

            error('missing player entity movement')
        end)

        try_set('GetPlayerEntity().Movement.LastPosition.Yaw', function()
            if player_entity.Movement and player_entity.Movement.LastPosition then
                player_entity.Movement.LastPosition.Yaw = rotation
                return
            end

            error('missing player entity last movement')
        end)

        try_set('GetPlayerEntity().Movement.Move.DeltaYaw', function()
            if player_entity.Movement and player_entity.Movement.Move then
                player_entity.Movement.Move.DeltaYaw = rotation
                return
            end

            error('missing player entity move delta')
        end)

        try_set('GetPlayerEntity().Heading', function()
            player_entity.Heading = rotation
        end)
    end

    if ent and player_index and player_index > 0 then
        try_set('Entity:SetLocalPositionYaw', function()
            ent:SetLocalPositionYaw(player_index, rotation)
        end)

        try_set('Entity:SetLastPositionYaw', function()
            ent:SetLastPositionYaw(player_index, rotation)
        end)

        try_set('Entity:SetMoveDeltaYaw', function()
            ent:SetMoveDeltaYaw(player_index, rotation)
        end)

        try_set('Entity:SetHeading', function()
            ent:SetHeading(player_index, rotation)
        end)

        try_set('Entity:SetIsDirty', function()
            ent:SetIsDirty(player_index, 1)
        end)

        try_set('Entity:SetModelUpdateFlags', function()
            local ok_flags, flags =
                pcall(function()
                    return ent:GetModelUpdateFlags(player_index)
                end)

            ent:SetModelUpdateFlags(player_index, ok_flags and flags or 1)
        end)

        try_set('Entity:SetUpdateMask', function()
            local ok_mask, mask =
                pcall(function()
                    return ent:GetUpdateMask(player_index)
                end)

            ent:SetUpdateMask(player_index, ok_mask and mask or 1)
        end)
    end

    if player then
        try_set('Player:SetRotation', function()
            player:SetRotation(rotation)
        end)

        try_set('Player raw Movement.LocalPosition.Yaw', function()
            local raw = player

            if player.GetRawStructure then
                raw = player:GetRawStructure()
            end

            if raw and raw.Movement and raw.Movement.LocalPosition then
                raw.Movement.LocalPosition.Yaw = rotation
                return
            end

            error('missing player raw movement')
        end)
    end

    local after = read_rotation_state(player_index)

    if changed then
        return true, nil, before, after
    end

    return false, table.concat(errors, ' | '), before, after
end

local function get_player_yaw(player_index)
    local state = read_rotation_state(player_index)

    return first_rotation_value(state)
end

function combat.set_rotation(rotation)
    local player_index = get_player_index()

    if not rotation then
        return false, 'missing rotation'
    end

    return set_player_rotation(player_index, normalize_signed_rotation(rotation))
end

function combat.set_rotation_degrees(degrees)
    local n = tonumber(degrees)

    if not n then
        return false, 'invalid degrees'
    end

    return combat.set_rotation(math.rad(n))
end

local function fmt_num(value)
    if value == nil then
        return 'nil'
    end

    return string.format('%.3f', value)
end

local function describe_rotation_state(state)
    return string.format(
        'local=%s entlocal=%s heading=%s entheading=%s last=%s delta=%s',
        fmt_num(state.local_yaw),
        fmt_num(state.entity_local_yaw),
        fmt_num(state.heading),
        fmt_num(state.entity_heading),
        fmt_num(state.last_yaw),
        fmt_num(state.move_delta_yaw)
    )
end

function combat.facecheck()
    local player_index = get_player_index()
    local target_index = get_current_target_index()

    if player_index <= 0 then
        return false, 'missing player index'
    end

    if target_index <= 0 then
        return false, 'missing target index'
    end

    local player_pos = get_position(player_index)
    local target_pos = get_position(target_index)

    if not player_pos or not target_pos then
        return false, 'missing player or target position'
    end

    local dx = target_pos.X - player_pos.X
    local dz = target_pos.Z - player_pos.Z
    local rotation = calculate_rotation(dx, dz)
    local ok, err, before, after = set_player_rotation(player_index, rotation)

    return ok, {
        string.format('p=%d t=%d dx=%.2f dz=%.2f desired=%.3f', player_index, target_index, dx, dz, rotation),
        'before ' .. describe_rotation_state(before or {}),
        'after  ' .. describe_rotation_state(after or {}),
        err and ('err ' .. tostring(err)) or nil
    }
end

local function steer_to_rotation(player_index, rotation)
    if not user32 then
        return set_player_rotation(player_index, rotation)
    end

    if is_chat_input_open() then
        release_turn_keys()
        return false, 'chat input open'
    end

    local yaw = get_player_yaw(player_index)

    if not yaw then
        return set_player_rotation(player_index, rotation)
    end

    local delta = signed_rotation_delta(rotation, yaw)

    if math.abs(delta) <= 0.08 then
        release_turn_keys()
        return true
    end

    local direction = delta > 0 and 'right' or 'left'

    if settings and settings.combat and settings.combat.face_reverse then
        direction = direction == 'right' and 'left' or 'right'
    end

    if not pulse_turn_key(direction) then
        return false, 'key pulse failed'
    end

    return true
end

function combat.toggle_face_reverse()
    if not settings then
        return false
    end

    settings.combat = settings.combat or {}
    settings.combat.face_reverse = not settings.combat.face_reverse

    return settings.combat.face_reverse
end

function combat.pulse_face_key(direction)
    direction = direction == 'right' and 'right' or 'left'

    return pulse_turn_key(direction)
end

function combat.face_target(force)
    if not settings or not settings.combat or not settings.combat.auto_face then
        set_movement_autoface(false, force)
        return false
    end

    local target_index = get_current_target_index()
    if not player_is_engaged() or not is_targetable_enemy(target_index) then
        set_movement_autoface(false, force)
        return false
    end

    set_movement_autoface(true, force)
    return true
end

local function face_target_lua()
    local player_index = get_player_index()
    local target_index = get_current_target_index()

    if player_index <= 0 or target_index <= 0 then
        return false
    end

    if not is_combat_active() or not is_targetable_enemy(target_index) then
        return false
    end

    local player_pos = get_position(player_index)
    local target_pos = get_position(target_index)

    if not player_pos or not target_pos then
        face_debug('missing player or target position')
        return false
    end

    local dx = target_pos.X - player_pos.X
    local dz = target_pos.Z - player_pos.Z

    if dx == 0 and dz == 0 then
        return false
    end

    local rotation = calculate_rotation(dx, dz)

    local ok, err =
        steer_to_rotation(player_index, rotation)

    if not ok then
        face_debug('turn failed: ' .. tostring(err))
        return false
    end

    local yaw = get_player_yaw(player_index)

    if yaw and rotation_difference(yaw, rotation) > 0.01 then
        face_debug(string.format('yaw readback mismatch %.3f -> %.3f', yaw, rotation))
    end

    return ok
end

function combat.start_face_loop()
    if shutting_down then
        return
    end

    if face_loop_active then
        return
    end

    face_loop_active = true
    combat.face_target(true)

    local function loop()
        if not face_loop_active then
            set_movement_autoface(false)
            return
        end

        if shutting_down
        or not settings
        or not settings.combat
        or not settings.combat.auto_face
        then
            face_loop_active = false
            set_movement_autoface(false)
            return
        end

        if pull_state.mounted == true then
            set_movement_autoface(false)
        else
            combat.face_target(false)
        end

        ashita.tasks.once(1.0, loop)
    end

    loop()
end

function combat.stop_face_loop()
    face_loop_active = false
    set_movement_autoface(false)
    release_turn_keys()
end

function combat.shutdown()
    if pull_state.player_resting == true
    and rest_resume_at == 0
    and get_player_status() == STATUS_RESTING
    then
        cmd('/heal')
    end
    pull_state.player_resting = false
    rest_resume_at = 0
    shutting_down = true
    face_loop_active = false
    set_movement_autoface(false)
    approaching = false
    approach_moving = false
    auto_assist_pending = false
    pull_state.auto_assist_active = false
    release_turn_keys()

    cmd('/movement navstop')
end

-------------------------------------------------
-- AUTO ASSIST
-------------------------------------------------
local function auto_assist_tick()
    local enabled = not shutting_down
        and settings
        and settings.combat
        and settings.combat.auto_assist == true

    if not enabled then
        pull_state.auto_assist_active = false
        return
    end

    local assist_target = trim(settings.combat.assist_target)

    if assist_target == '' then
        pull_state.auto_assist_active = false
        return
    end

    local assist_index = find_entity_index_by_name(assist_target)
    local assist_engaged = assist_index > 0
        and assist_index ~= get_player_index()
        and is_engaged_status(get_entity_status(assist_index))

    pull_state.auto_assist_active =
        player_is_engaged() or auto_assist_pending or assist_engaged

    if pull_in_progress()
    or player_is_engaged()
    or auto_assist_pending
    then
        return
    end

    local now = os.clock()

    if (now - last_auto_assist_attempt) < AUTO_ASSIST_COOLDOWN then
        return
    end

    if assist_index <= 0 or assist_index == get_player_index() then
        return
    end

    if not is_engaged_status(get_entity_status(assist_index)) then
        return
    end

    last_auto_assist_attempt = now
    auto_assist_pending = true
    cmd('/assist ' .. assist_target)

    local assist_started = now
    local last_attack_attempt = 0
    local function finish_assist()
        if shutting_down
        or not settings
        or not settings.combat
        or settings.combat.auto_assist ~= true
        or pull_state.mounted == true
        then
            auto_assist_pending = false
            return
        end

        if player_is_engaged() then
            auto_assist_pending = false
            return
        end

        local elapsed = os.clock() - assist_started

        -- The assist target was already verified as engaged, so let the game
        -- validate the selected target. Entity render flags can lag behind
        -- the visible /assist target change and previously blocked this.
        if elapsed >= 0.20 and (os.clock() - last_attack_attempt) >= 0.25 then
            last_attack_attempt = os.clock()
            AshitaCore:GetChatManager():QueueCommand(0, '/attack on')
        end

        if elapsed < 1.50 then
            ashita.tasks.once(0.10, finish_assist)
        else
            auto_assist_pending = false
        end
    end

    ashita.tasks.once(0.20, finish_assist)
end

function combat.tick()
    if shutting_down
    or not settings
    or not settings.combat
    or pull_state.mounted == true
    then
        return
    end

    if resting_tick() then
        return
    end

    auto_assist_tick()

    local target_index = get_current_target_index()
    local valid_target = is_targetable_enemy(target_index)

    if settings.combat.auto_engage == true
    and not pull_in_progress()
    and not player_is_engaged()
    and valid_target
    and (os.clock() - last_auto_engage_attempt) >= AUTO_ENGAGE_COOLDOWN
    then
        last_auto_engage_attempt = os.clock()
        AshitaCore:GetChatManager():QueueCommand(0, '/attack on')
    end

    if settings.combat.auto_face == true
    and player_is_engaged()
    and valid_target
    then
        combat.face_target(false)
    elseif movement_autoface_enabled then
        set_movement_autoface(false)
    end

    if settings.combat.approach == true and player_is_engaged() and valid_target then
        combat.approach_target()
    end
end

-------------------------------------------------
-- APPROACH SYSTEM
-------------------------------------------------
function combat.approach_target()
    if shutting_down then return end
    if not settings or not settings.combat or not settings.combat.approach then return end
    if pull_in_progress() then return end
    if approaching then return end
    if not player_is_engaged() or not is_targetable_enemy(get_current_target_index()) then return end

    approaching = true

    local function loop()
        if shutting_down
        or not approaching
        or pull_in_progress()
        or pull_state.mounted == true
        or not settings
        or not settings.combat
        or settings.combat.approach ~= true
        then
            if approach_moving then
                cmd('/movement navstop')
                approach_moving = false
            end
            approaching = false
            return
        end

        local entity = get_entity()
        local player_pos = get_position(get_player_index())
        local target_index = get_current_target_index()
        local target_pos = get_position(target_index)

        if not player_pos or not target_pos or not is_targetable_enemy(target_index) then
            if approach_moving then
                cmd('/movement navstop')
                approach_moving = false
            end
            approaching = false
            return
        end

        local dx = target_pos.X - player_pos.X
        local dy = target_pos.Z - player_pos.Z
        local distance = math.sqrt(dx * dx + dy * dy)

        if distance > MELEE_RANGE then
            local vx = dx / distance
            local vy = dy / distance
            cmd(string.format('/movement navvec %.3f %.3f', vx, vy))
            approach_moving = true
            ashita.tasks.once(0.10, loop)
            return
        end

        if approach_moving then
            cmd('/movement navstop')
            approach_moving = false
        end
        approaching = false
    end

    loop()
end

function combat.suspend_approach()
    approaching = false

    if approach_moving then
        cmd('/movement navstop')
        approach_moving = false
    end
end

-------------------------------------------------
-- EVENT: STATUS CHANGE
-------------------------------------------------
ashita.events.register('status_change', 'combat_status', function(e)
    if shutting_down or not settings then return end

    -- engaged
    if e.new == 1 then
        if settings.combat.auto_face then
            combat.start_face_loop()
        end

        if settings.combat.approach then
            ashita.tasks.once(0.2, function()
                combat.approach_target()
            end)
        end
    end
end)

-------------------------------------------------
-- COMMANDS
-------------------------------------------------
function combat.assist(target)
    if shutting_down then return end

    if not target then
        cmd('/p Error: No assist target.')
        return
    end

    cmd('/assist ' .. target)

    ashita.tasks.once(1.5, function()
        if shutting_down then return end

        local player = get_player()
        if player and player:GetTargetIndex() then
            cmd('/p Target Locked - Engaging Combat.')
            combat.attack()
        else
            cmd('/p Error: No valid target.')
        end
    end)
end

function combat.attack()
    if shutting_down then return end

    if not is_targetable_enemy(get_current_target_index()) then
        cmd('/echo [AutoBot] Combat: current target is not a valid enemy.')
        combat.stop_face_loop()
        return
    end

    cmd('/p Engaging Target.')
    cmd('/attack on')

    ashita.tasks.once(0.5, function()
        if shutting_down then return end

        combat.start_face_loop()
        combat.approach_target()
    end)
end

function combat.turn()
    if shutting_down then return end

    local entity = get_entity()
    local player_index = get_player_index()
    if not entity or player_index <= 0 then return end

    local ok, heading = pcall(function()
        return entity:GetLocalPositionYaw(player_index)
    end)
    if not ok or heading == nil then return end

    cmd('/p Turning Around!')
    local backward_x = -math.cos(heading)
    local backward_y = math.sin(heading)
    cmd(string.format('/movement auto %.3f %.3f 0.5', backward_x, backward_y))
end

function combat.disengage()
    if shutting_down then return end

    local player = get_player()

    if player and player:GetStatus() == 1 then
        cmd('/p Disengaging Target.')
        cmd('/attack off')
    else
        cmd('/p Not engaged.')
    end
end

return combat
