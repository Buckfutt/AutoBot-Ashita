local common = require('job_helpers.common')
local action_state = require('job_helpers.action_state')

local settings = nil
local active = false
local positioning = false
local last_position_command = 0
local position_status = 'Idle'

local REAR_CONE_COS = math.cos(math.rad(55))
local POSITION_INTERVAL = 0.5
local POSITION_DISTANCE = 2.8
local PARTY_LINE_WIDTH = 1.6
local TRICK_MEMBER_MAX_DISTANCE = 5.0
local POSITIONAL_ABILITY_MAX_DISTANCE = 5.0

local function queue(command)
    AshitaCore:GetChatManager():QueueCommand(1, command)
end

local function managers()
    local memory = AshitaCore:GetMemoryManager()
    return memory:GetParty(), memory:GetEntity(), memory:GetTarget()
end

local function get_position(entity, index)
    if not entity or not index or index <= 0 then
        return nil
    end

    local ok_x, x = pcall(function()
        return entity:GetLocalPositionX(index)
    end)
    local ok_y, y = pcall(function()
        return entity:GetLocalPositionY(index)
    end)

    if ok_x and ok_y and x and y then
        return { x = tonumber(x), y = tonumber(y) }
    end

    return nil
end

local function get_target_yaw(entity, index)
    for _, method in ipairs({ 'GetLocalPositionYaw', 'GetHeading' }) do
        local ok, yaw = pcall(function()
            return entity[method](entity, index)
        end)
        if ok and tonumber(yaw) then
            return tonumber(yaw)
        end
    end

    return nil
end

local function combat_geometry()
    local party, entity, target = managers()
    if not party or not entity or not target then
        return nil
    end

    local player_index = tonumber(party:GetMemberTargetIndex(0)) or 0
    local target_index = tonumber(target:GetTargetIndex(0)) or 0
    if player_index <= 0 or target_index <= 0 then
        return nil
    end

    local player_pos = get_position(entity, player_index)
    local target_pos = get_position(entity, target_index)
    if not player_pos or not target_pos then
        return nil
    end

    return {
        party = party,
        entity = entity,
        player_index = player_index,
        target_index = target_index,
        player = player_pos,
        target = target_pos,
        target_yaw = get_target_yaw(entity, target_index),
    }
end

local function normalize(x, y)
    local length = math.sqrt((x * x) + (y * y))
    if length < 0.001 then
        return nil, nil, 0
    end
    return x / length, y / length, length
end

local function is_behind_target(geometry)
    if not geometry or not geometry.target_yaw then
        return false
    end

    local px, py, distance = normalize(
        geometry.player.x - geometry.target.x,
        geometry.player.y - geometry.target.y
    )
    if not px or distance > POSITIONAL_ABILITY_MAX_DISTANCE then
        return false
    end

    local rear_x = -math.cos(geometry.target_yaw)
    local rear_y = math.sin(geometry.target_yaw)
    return ((px * rear_x) + (py * rear_y)) >= REAR_CONE_COS
end

local function point_is_behind_target(geometry, point)
    if not geometry or not geometry.target_yaw or not point then
        return false
    end

    local px, py = normalize(
        point.x - geometry.target.x,
        point.y - geometry.target.y
    )
    if not px then
        return false
    end

    local rear_x = -math.cos(geometry.target_yaw)
    local rear_y = math.sin(geometry.target_yaw)
    return ((px * rear_x) + (py * rear_y)) >= REAR_CONE_COS
end

local function party_member_between(geometry)
    if not geometry then
        return false, nil
    end

    local line_x = geometry.target.x - geometry.player.x
    local line_y = geometry.target.y - geometry.player.y
    local length_sq = (line_x * line_x) + (line_y * line_y)
    if length_sq < 0.01 then
        return false, nil
    end

    local best = nil
    local best_width = math.huge

    for slot = 1, 5 do
        local active_ok, member_active = pcall(function()
            return geometry.party:GetMemberIsActive(slot)
        end)
        local index_ok, member_index = pcall(function()
            return geometry.party:GetMemberTargetIndex(slot)
        end)

        member_index = index_ok and tonumber(member_index) or 0
        if active_ok and member_active == 1 and member_index > 0 then
            local member = get_position(geometry.entity, member_index)
            if member then
                local rel_x = member.x - geometry.player.x
                local rel_y = member.y - geometry.player.y
                local projection = ((rel_x * line_x) + (rel_y * line_y)) / length_sq

                if projection > 0.08 and projection < 0.95 then
                    local closest_x = geometry.player.x + (line_x * projection)
                    local closest_y = geometry.player.y + (line_y * projection)
                    local width = math.sqrt(
                        ((member.x - closest_x) ^ 2) + ((member.y - closest_y) ^ 2)
                    )

                    if width <= PARTY_LINE_WIDTH and width < best_width then
                        best = member
                        best_width = width
                    end
                end
            end
        end
    end

    return best ~= nil, best
end

local function sneak_condition()
    return is_behind_target(combat_geometry())
end

local function player_has_buff(player, buff_id)
    for _, buff in ipairs((player and player.buffs) or {}) do
        if tonumber(buff) == tonumber(buff_id) then
            return true
        end
    end
    return false
end

local function trick_condition(player)
    local geometry = combat_geometry()
    if not geometry then
        return false
    end

    local _, _, target_distance = normalize(
        geometry.player.x - geometry.target.x,
        geometry.player.y - geometry.target.y
    )
    if target_distance > POSITIONAL_ABILITY_MAX_DISTANCE then
        return false
    end

    local aligned = party_member_between(geometry)
    if not aligned then
        return false
    end

    -- Never stack Trick Attack onto an active Sneak Attack unless both
    -- positional requirements are simultaneously true.
    if player_has_buff(player, 65) then
        return is_behind_target(geometry)
    end

    return true
end

local THF = common.create_ability_job({
    job = 'THF',
    cooldown = 3,
    abilities = {
        { key='Perfect_Dodge', name='Perfect Dodge', timer=0, level=1 },
        { key='Steal', name='Steal', timer=65, level=5, target='<t>' },
        { key='Sneak_Attack', name='Sneak Attack', timer=62, buff=65, level=15, condition=sneak_condition },
        { key='Flee', name='Flee', timer=64, buff=32, level=25 },
        { key='Trick_Attack', name='Trick Attack', timer=63, buff=87, level=30, condition=trick_condition },
        { key='Mug', name='Mug', timer=66, level=35, target='<t>' },
        { key='Hide', name='Hide', timer=67, level=45 },
        { key='Assassins_Charge', name="Assassin's Charge", timer=68, level=75 },
        { key='Feint', name='Feint', timer=69, level=75 },
        { key='Despoil', name='Despoil', timer=181, level=77, target='<t>' },
        { key='Conspirator', name='Conspirator', timer=40, level=87 },
        { key='Bully', name='Bully', timer=240, level=93, target='<t>' },
        { key='Larceny', name='Larceny', timer=254, level=96, target='<t>' },
    },
})

local function trick_position(geometry, require_mob_rear)
    local closest = nil
    local closest_distance = math.huge

    for slot = 1, 5 do
        local active_ok, member_active = pcall(function()
            return geometry.party:GetMemberIsActive(slot)
        end)
        local index_ok, member_index = pcall(function()
            return geometry.party:GetMemberTargetIndex(slot)
        end)

        member_index = index_ok and tonumber(member_index) or 0
        if active_ok and member_active == 1 and member_index > 0 then
            local member = get_position(geometry.entity, member_index)
            if member then
                local tx, ty, target_distance = normalize(
                    member.x - geometry.target.x,
                    member.y - geometry.target.y
                )

                if tx and target_distance <= TRICK_MEMBER_MAX_DISTANCE then
                    local candidate = {
                        x = member.x + (tx * 1.4),
                        y = member.y + (ty * 1.4),
                    }

                    if (not require_mob_rear or point_is_behind_target(geometry, candidate))
                    and target_distance < closest_distance
                    then
                        candidate.label = require_mob_rear
                            and 'Positioning Sneak + Trick Attack'
                            or 'Moving behind nearby party member'
                        closest = candidate
                        closest_distance = target_distance
                    end
                end
            end
        end
    end

    return closest
end

local function desired_position(geometry, sneak_ready, trick_ready, sneak_ok, trick_ok, sneak_buff)
    local stacking = trick_ready and (sneak_ready or sneak_buff)
    if stacking and (not sneak_ok or not trick_ok) then
        local combined = trick_position(geometry, true)
        if combined then
            return combined
        end
    end

    if sneak_ready and not sneak_ok and geometry.target_yaw then
        local rear_x = -math.cos(geometry.target_yaw)
        local rear_y = math.sin(geometry.target_yaw)
        return {
            x = geometry.target.x + (rear_x * POSITION_DISTANCE),
            y = geometry.target.y + (rear_y * POSITION_DISTANCE),
            label = 'Moving behind target for Sneak Attack',
        }
    end

    if trick_ready and not trick_ok and not sneak_buff then
        return trick_position(geometry, false)
    end

    return nil
end

local base_init = THF.init
local base_start = THF.start
local base_stop = THF.stop
local base_tick = THF.tick
local base_render_ui = THF.render_ui

function THF.init(job_settings)
    settings = job_settings or {}
    settings.autoPosition = settings.autoPosition == true
    base_init(settings)
end

function THF.start()
    active = true
    return base_start()
end

function THF.stop()
    active = false
    if positioning then
        queue('/movement navstop')
    end
    positioning = false
    position_status = 'Idle'
    return base_stop()
end

function THF.tick()
    if active and settings and settings.autoPosition and not action_state.is_busy() then
        local geometry = combat_geometry()
        local player = windower.ffxi.get_player()

        if geometry and player and player.status == 1 then
            local sneak_ready = THF.is_ability_ready('Sneak Attack')
            local trick_ready = THF.is_ability_ready('Trick Attack')
            local sneak_ok = is_behind_target(geometry)
            local trick_aligned = party_member_between(geometry)
            local sneak_buff = player_has_buff(player, 65)
            local trick_ok = trick_aligned and (not sneak_buff or sneak_ok)
            position_status = string.format(
                'SA ready: %s | Behind: %s | TA line: %s',
                sneak_ready and 'Yes' or 'No',
                sneak_ok and 'Yes' or 'No',
                trick_aligned and 'Yes' or 'No'
            )
            local destination = desired_position(
                geometry,
                sneak_ready,
                trick_ready,
                sneak_ok,
                trick_ok,
                sneak_buff
            )

            if destination then
                position_status = destination.label
                positioning = true
                if (os.clock() - last_position_command) >= POSITION_INTERVAL then
                    queue(string.format('/movement navgoto %.3f %.3f', destination.x, destination.y))
                    last_position_command = os.clock()
                end
                return
            end
        end
    end

    if positioning then
        queue('/movement navstop')
        positioning = false
    end
    base_tick()
end

function THF.render_ui(imgui, ui_settings, ctx)
    settings = ui_settings or settings or {}
    settings.autoPosition = settings.autoPosition == true

    local changed = base_render_ui(imgui, settings, ctx)
    imgui.Separator()
    imgui.Text('Positional Abilities')
    local auto_position = { settings.autoPosition == true }
    if imgui.Checkbox('Auto-Position for Sneak/Trick Attack##THF_auto_position' .. tostring((ctx or {}).id or ''), auto_position) then
        settings.autoPosition = auto_position[1]
        changed = true
        if not settings.autoPosition and positioning then
            queue('/movement navstop')
            positioning = false
        end
    end
    imgui.TextDisabled(position_status)
    return changed
end

return THF
