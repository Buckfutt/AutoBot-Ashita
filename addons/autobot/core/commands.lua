local commands = {}
local directional_move_id = 0
local directional_move_restore = nil

-------------------------------------------------
-- HELPERS
-------------------------------------------------
local function print(msg)
    AshitaCore:GetChatManager():QueueCommand(1, '/echo [AutoBot] ' .. tostring(msg))
end

local function join_args(args, start)
    local t = {}
    for i = start or 1, #args do
        table.insert(t, args[i])
    end
    return table.concat(t, ' ')
end

local function is_roman_numeral(value)
    value = tostring(value or ''):upper()
    return value == 'I'
        or value == 'II'
        or value == 'III'
        or value == 'IV'
        or value == 'V'
        or value == 'VI'
        or value == 'VII'
        or value == 'VIII'
        or value == 'IX'
        or value == 'X'
end

local function parse_action_name_and_target(args, start_index)
    local raw = join_args(args, start_index)
    local target = '<me>'

    raw = tostring(raw or ''):match('^%s*(.-)%s*$')
    if raw == '' then
        return '', target
    end

    local angle_target = raw:match('%s+(<[^>]+>)%s*$') or raw:match('^(<[^>]+>)%s*$')
    if angle_target then
        target = angle_target
        raw = raw:gsub('%s*<[^>]+>%s*$', ''):match('^%s*(.-)%s*$')
    end

    local chunk, rest = raw:match('^%s*(%b{})%s*(.-)%s*$')
    if not chunk then
        chunk, rest = raw:match('^%s*(%b())%s*(.-)%s*$')
    end

    if chunk then
        local action_parts = { chunk }
        local target_parts = {}
        local assigning_target = false

        for token in tostring(rest or ''):gmatch('%S+') do
            if not assigning_target and is_roman_numeral(token) then
                table.insert(action_parts, token)
            else
                assigning_target = true
                table.insert(target_parts, token)
            end
        end

        if #target_parts > 0 and target == '<me>' then
            target = table.concat(target_parts, ' ')
        end

        return table.concat(action_parts, ' '), target
    end

    local tokens = {}
    for token in raw:gmatch('%S+') do
        table.insert(tokens, token)
    end

    if target == '<me>'
    and #tokens >= 3
    and is_roman_numeral(tokens[#tokens - 1])
    and not is_roman_numeral(tokens[#tokens])
    then
        target = tokens[#tokens]
        table.remove(tokens, #tokens)
        return table.concat(tokens, ' '), target
    end

    return raw, target
end

local function contains(tbl, val)
    for _, v in ipairs(tbl or {}) do
        if v == val then return true end
    end
    return false
end

local function parse_toggle(value, current)
    value = value and tostring(value):lower() or 'toggle'

    if value == 'on' or value == 'start' or value == 'enable' or value == 'enabled' or value == 'true' or value == '1' then
        return true
    end

    if value == 'off' or value == 'stop' or value == 'disable' or value == 'disabled' or value == 'false' or value == '0' then
        return false
    end

    return not current
end

local function refresh_module_settings(scripts, config)
    if scripts.combat and scripts.combat.set_settings then
        scripts.combat.set_settings(config)
    end
    if scripts.autows and scripts.autows.set_settings then
        scripts.autows.set_settings(config)
    end
    if scripts.items and scripts.items.set_config then
        scripts.items.set_config(config, scripts.save)
    end
end

-------------------------------------------------
-- MAIN HANDLER
-------------------------------------------------
commands.handle = function(args, context)

    local config  = context.config
    local scripts = context.scripts
    local save    = context.save
    local ui      = context.ui

    local cmd = args[1] and args[1]:lower() or nil

    -------------------------------------------------
    -- HELP / BASE
    -------------------------------------------------
    if not cmd or cmd == 'help' then
        print('Core Commands:')
        print('/ab ui')
        print('/ab save')
        print('/ab load|reload (remote: !load or !reload)')
        print('/ab debug on|off')
        print('/ab stop|resume')
        print('/ab module <name> on|off|toggle')
        print('/ab target start|stop|add|remove|list [name]')
        print('/ab pull start|stop|method|timeout')
        print('/ab autows on|off|ws|tp|aftermathtp|cooldown|aftermath|sc|open|close|chain|closews')
        print('/ab item on|off|toggle|food|delay|use')
        print('/ab combat autoengage|approach|autoface|autoassist|assisttarget')
        print('/ab whitelist add|remove|list [name]')
        print('/ab follow <name>')
        print('/ab stopfollow')
        print('/ab attack|assist|disengage')
        print('/ab cast <spell> [target]')
        print('/ab ability|abil <ability> [target]')
        print('/ab move <yalms> <direction>')
        print('/ab rest|join|leave|disband|invite|passleader')
        print('/ab mount|mountup|mountlist|dismount|warpring|trade|accepttrade|canceltrade|tradeallgil')
        print('/ab trust save|summon|random|create|add|remove|delete|release|releaseall|list')
        print('/ab job main|sub|<job> start|stop|enable|disable|toggle|...')
        print('/ab warp|warpto <type> <location> [index] - forwards to UberWarp')
        print('/ab nav record|start|pause|resume|stop|loop|reverse|bounce|list|details|setdetails|delete')
        print('/ab face <degrees>')
        print('/ab facecheck')
        print('Remote: whitelisted party/tell users may use !<command> or bot <command>.')
        return
    end

    -------------------------------------------------
    -- SAVE ALL CHARACTER SETTINGS
    -------------------------------------------------
    if cmd == 'save' then
        local saved, result = save()
        if saved then
            print('All settings saved: ' .. tostring(result))
        else
            print('Save failed: ' .. tostring(result or 'unknown error'))
        end
        return
    end

    -------------------------------------------------
    -- RELOAD ACTIVE CHARACTER SETTINGS
    -------------------------------------------------
    if cmd == 'load' or cmd == 'reload' then
        if not scripts.reload_profile then
            print('Load failed: character profile loader is unavailable')
            return
        end

        local loaded, result = scripts.reload_profile()
        if not loaded then
            print('Load failed: ' .. tostring(result or 'unknown error'))
        end
        return
    end

    if cmd == 'debug' then
        config.debug = parse_toggle(args[2], config.debug)
        save()
        print('Debug Mode: ' .. (config.debug and 'ON' or 'OFF'))
        return
    end

    if cmd == 'resume' then
        if scripts.resume_automation then
            scripts.resume_automation()
        end
        return
    end

    if cmd == 'stop' or cmd == 'fullstop' then
        if scripts.full_stop then
            scripts.full_stop()
        end
        return
    end

    -------------------------------------------------
    -- UI
    -------------------------------------------------
    if cmd == 'ui' then
        ui.toggle()
        return
    end

    -------------------------------------------------
    -- MODULE TOGGLE (kept from original)
    -------------------------------------------------
    if cmd == 'toggle' or cmd == 'set' or cmd == 'module' then
        local mod = args[2] and args[2]:lower()
        if not mod or config.modules[mod] == nil then
            print('Invalid module.')
            return
        end

        config.modules[mod] = parse_toggle(args[3], config.modules[mod])
        save()
        print(mod .. ': ' .. (config.modules[mod] and 'ON' or 'OFF'))
        return
    end

    -------------------------------------------------
    -- SHOW SETTINGS
    -------------------------------------------------
    if cmd == 'settings' then
        for k, v in pairs(config.modules) do
            print(string.format('%s: %s', k, v and 'ON' or 'OFF'))
        end
        return
    end

    -------------------------------------------------
    -- ✅ TARGETING (UPDATED)
    -------------------------------------------------
    if cmd == 'target' then
        local sub = args[2] and args[2]:lower()
        local name = join_args(args, 3):lower()

        -- ✅ NEW CONTROL
        if sub == 'start' or sub == 'on' then
            config.runtime = config.runtime or {}
            if not config.modules.targeting then
                print('[Targeting] Enable the module first.')
                return
            end
            config.runtime.targeting = true
            print('[Targeting] Started')
            return
        elseif sub == 'stop' or sub == 'off' then
            config.runtime = config.runtime or {}
            config.runtime.targeting = false
            scripts.targeting.stop()
            print('[Targeting] Stopped')
            return
        end

        -- ✅ LIST MANAGEMENT (original behavior)
        if sub == 'add' and name ~= '' then
            if not contains(config.target_list, name) then
                table.insert(config.target_list, name)
                save()
                print('Added target: ' .. name)
            end
        elseif sub == 'remove' and name ~= '' then
            for i, v in ipairs(config.target_list) do
                if v == name then
                    table.remove(config.target_list, i)
                    save()
                    print('Removed target: ' .. name)
                    break
                end
            end
        elseif sub == 'list' then
            for _, v in ipairs(config.target_list) do
                print('- ' .. v)
            end
        else
            print('Usage: /ab target start|stop|add|remove|list [name]')
        end

        return
    end

    -------------------------------------------------
    -- ✅ PULLING (UPDATED)
    -------------------------------------------------
    if cmd == 'pull' then
        local sub = args[2] and args[2]:lower()

        if sub == 'start' or sub == 'on' then
            config.runtime = config.runtime or {}
            if not config.modules.pulling then
                print('[Pulling] Enable the module first.')
                return
            end
            config.runtime.pulling = true
            print('[Pulling] Started')
            return

        elseif sub == 'stop' or sub == 'off' then
            config.runtime = config.runtime or {}
            config.runtime.pulling = false
            scripts.pulling.stop()
            print('[Pulling] Stopped')
            return

        -- ✅ METHOD (from original Windower)
        elseif sub == 'method' then
            local mtype = args[3] and args[3]:lower()
            local action = join_args(args, 4)

            config.pulling = config.pulling or {}

            if mtype == 'spell' and action ~= '' then
                config.pulling.use_spell = true
                config.pulling.use_ability = false
                config.pulling.use_ranged = false
                config.pulling.spell = action

                print('[Pulling] Spell: ' .. action)

            elseif mtype == 'ability' and action ~= '' then
                config.pulling.use_spell = false
                config.pulling.use_ability = true
                config.pulling.use_ranged = false
                config.pulling.ability = action

                print('[Pulling] Ability: ' .. action)

            elseif mtype == 'ranged' then
                config.pulling.use_spell = false
                config.pulling.use_ability = false
                config.pulling.use_ranged = true

                print('[Pulling] Ranged Attack')
            else
                print('Usage: /ab pull method spell|ability|ranged "action"')
            end

            save()
            return

        elseif sub == 'timeout' then
            local seconds = tonumber(args[3])

            if seconds and seconds >= 2 then
                config.pulling = config.pulling or {}
                config.pulling.timeout = math.floor((seconds * 10) + 0.5) / 10
                save()
                print('[Pulling] Timeout: ' .. config.pulling.timeout .. 's')
            else
                print('Usage: /ab pull timeout <seconds>')
            end

            return
        end

        print('Usage: /ab pull start|stop|method|timeout')
        return
    end

    -------------------------------------------------
    -- ITEMS / FOOD
    -------------------------------------------------
    if cmd == 'item' or cmd == 'items' or cmd == 'food' then
        config.items = config.items or {}
        config.items.food = config.items.food or {}

        local sub = args[2] and args[2]:lower() or nil
        local forwarded = {}

        if cmd == 'food' then
            if not sub then
                sub = 'toggle'
            elseif sub == 'on' or sub == 'off' or sub == 'toggle' or sub == 'start' or sub == 'stop' or sub == 'enable' or sub == 'disable' or sub == 'use' or sub == 'eat' then
                -- keep the verb as-is
            elseif sub == 'delay' or sub == 'retry' then
                if args[3] then
                    table.insert(forwarded, args[3])
                end
            else
                sub = 'food'
                for i = 2, #args do
                    table.insert(forwarded, args[i])
                end
            end
        else
            for i = 3, #args do
                table.insert(forwarded, args[i])
            end
        end

        if not scripts.items or not scripts.items.command then
            print('[Items] Module is unavailable.')
            return
        end

        local ok, err = scripts.items.command(sub, forwarded)
        if not ok and err then
            print('[Items] ' .. tostring(err))
        end
        return
    end

    -------------------------------------------------
    -- AUTOWS
    -------------------------------------------------
    if cmd == 'autows' or cmd == 'autotp' then
        local sub = args[2] and args[2]:lower()
        config.autows = config.autows or {}

        if sub == 'on' or sub == 'start' then
            config.autows.enabled = true
            save()
            print('[AutoWS] Enabled')
        elseif sub == 'off' or sub == 'stop' then
            config.autows.enabled = false
            save()
            print('[AutoWS] Disabled')
        elseif sub == 'toggle' then
            config.autows.enabled = not config.autows.enabled
            save()
            print('[AutoWS] ' .. (config.autows.enabled and 'Enabled' or 'Disabled'))
        elseif sub == 'ws' then
            local ws = join_args(args, 3)
            if ws ~= '' then
                config.autows.weaponskill = ws
                save()
                print('[AutoWS] Weaponskill: ' .. ws)
            else
                print('Usage: /ab autows ws "Weapon Skill"')
            end
        elseif sub == 'tp' then
            local amount = tonumber(args[3])
            if amount then
                config.autows.tp_amount = math.max(1000, math.min(3000, math.floor(amount)))
                save()
                print('[AutoWS] TP: ' .. config.autows.tp_amount)
            else
                print('Usage: /ab autows tp <1000-3000>')
            end
        elseif sub == 'am3tp' or sub == 'aftermathtp' then
            local amount = tonumber(args[3])
            if amount then
                config.autows.aftermath_tp_amount = math.max(1000, math.min(3000, math.floor(amount)))
                save()
                print('[AutoWS] Aftermath TP: ' .. config.autows.aftermath_tp_amount)
            else
                print('Usage: /ab autows aftermathtp <1000-3000>')
            end
        elseif sub == 'cooldown' then
            local seconds = tonumber(args[3])
            if seconds then
                config.autows.cooldown = math.max(1.5, math.min(15, seconds))
                save()
                print('[AutoWS] Cooldown: ' .. config.autows.cooldown .. 's')
            else
                print('Usage: /ab autows cooldown <seconds>')
            end
        elseif sub == 'am3' or sub == 'aftermath' then
            local value = args[3] and args[3]:lower()
            config.autows.use_aftermath = value ~= 'off' and value ~= 'false' and value ~= '0'
            config.autows.use_am3 = nil
            save()
            print('[AutoWS] Maintain Aftermath: ' .. (config.autows.use_aftermath and 'ON' or 'OFF'))
        elseif sub == 'sc' or sub == 'skillchains' then
            local value = args[3] and args[3]:lower()
            config.autows.skillchains_enabled = value ~= 'off' and value ~= 'false' and value ~= '0'
            save()
            print('[AutoWS] Skillchain Helper: ' .. (config.autows.skillchains_enabled and 'ON' or 'OFF'))
        elseif sub == 'open' then
            local value = args[3] and args[3]:lower()
            config.autows.open_skillchains = value ~= 'off' and value ~= 'false' and value ~= '0'
            save()
            print('[AutoWS] Open Skillchains: ' .. (config.autows.open_skillchains and 'ON' or 'OFF'))
        elseif sub == 'close' then
            local value = args[3] and args[3]:lower()
            config.autows.close_skillchains = value ~= 'off' and value ~= 'false' and value ~= '0'
            save()
            print('[AutoWS] Close Skillchains: ' .. (config.autows.close_skillchains and 'ON' or 'OFF'))
        elseif sub == 'opener' then
            local ws = join_args(args, 3)
            config.autows.open_weaponskill = ws
            save()
            print('[AutoWS] Opener Weaponskill: ' .. (ws ~= '' and ws or '(default AutoWS WS)'))
        elseif sub == 'opentp' then
            local amount = tonumber(args[3])
            if amount then
                config.autows.open_tp_amount = math.max(1000, math.min(3000, math.floor(amount)))
                save()
                print('[AutoWS] Open TP: ' .. config.autows.open_tp_amount)
            else
                print('Usage: /ab autows opentp <1000-3000>')
            end
        elseif sub == 'closetp' then
            local amount = tonumber(args[3])
            if amount then
                config.autows.close_tp_amount = math.max(1000, math.min(3000, math.floor(amount)))
                save()
                print('[AutoWS] Close TP: ' .. config.autows.close_tp_amount)
            else
                print('Usage: /ab autows closetp <1000-3000>')
            end
        elseif sub == 'priority' then
            local priority = join_args(args, 3)
            if priority ~= '' then
                config.autows.level_priority = priority
                save()
                print('[AutoWS] Skillchain Level Priority: ' .. priority)
            else
                print('Usage: /ab autows priority 4,3,2,1')
            end
        elseif sub == 'chain' or sub == 'chainpriority' then
            local chain = join_args(args, 3)
            config.autows.chain_priority = chain
            save()
            print('[AutoWS] Chain Priority: ' .. (chain ~= '' and chain or '(none)'))
        elseif sub == 'closews' or sub == 'closewspriority' then
            local ws = join_args(args, 3)
            config.autows.close_ws_priority = ws
            save()
            print('[AutoWS] Close WS Priority: ' .. (ws ~= '' and ws or '(AutoWS WS)'))
        elseif sub == 'blacklist' then
            local list = join_args(args, 3)
            config.autows.blacklist = list
            save()
            print('[AutoWS] Skillchain Blacklist: ' .. (list ~= '' and list or '(empty)'))
        elseif sub == 'status' or sub == 'debug' then
            if scripts.autows and scripts.autows.get_status then
                local status = scripts.autows.get_status() or {}
                print('[AutoWS] TP=' .. tostring(status.tp or 0)
                    .. ' Threshold=' .. tostring(status.threshold or 0)
                    .. ' Aftermath=' .. tostring(status.has_aftermath)
                    .. '(' .. tostring(status.aftermath_buff_id or 0) .. ')'
                    .. ' PlayerStatus=' .. tostring(status.player_status or 0)
                    .. ' Target=' .. tostring(status.target_index or -1)
                    .. ' State=' .. tostring(status.reason or 'Unknown'))
            else
                print('[AutoWS] Status unavailable.')
            end
        else
            print('Usage: /ab autows on|off|toggle|ws|tp|aftermathtp|cooldown|aftermath|sc|open|close|opener|opentp|closetp|priority|chain|closews|blacklist|status')
        end

        if scripts.autows and scripts.autows.set_settings then
            scripts.autows.set_settings(config)
        end
        return
    end

    -------------------------------------------------
    -- WHITELIST
    -------------------------------------------------
    if cmd == 'whitelist' then
        local sub = args[2] and args[2]:lower()
        local name = args[3] and args[3]:lower()

        if sub == 'add' and name then
            if not contains(config.whitelist, name) then
                table.insert(config.whitelist, name)
                save()
                print('Added: ' .. name)
            end
        elseif sub == 'remove' and name then
            for i, v in ipairs(config.whitelist) do
                if v == name then
                    table.remove(config.whitelist, i)
                    save()
                    print('Removed: ' .. name)
                    break
                end
            end
        elseif sub == 'list' then
            for _, v in ipairs(config.whitelist) do
                print('- ' .. v)
            end
        else
            print('Usage: /ab whitelist add|remove|list [name]')
        end

        return
    end

    -------------------------------------------------
    -- FOLLOW
    -------------------------------------------------
    if cmd == 'follow' and args[2] then
        if config.modules.follow then
            scripts.follow.start_follow(args[2])
        end
        return

    elseif cmd == 'followme' then
        local player = AshitaCore:GetMemoryManager():GetPlayer():GetName()
        scripts.follow.start_follow(player)
        return

    elseif cmd == 'stopfollow' then
        scripts.follow.stop_follow()
        return
    end

    -------------------------------------------------
    -- GENERAL / UTILITY
    -------------------------------------------------
    if cmd == 'rest' then
        scripts.general.rest()
        return
    elseif cmd == 'join' then
        scripts.general.join()
        return
    elseif cmd == 'leave' then
        scripts.general.leave()
        return
    elseif cmd == 'disband' then
        scripts.general.disband()
        return
    elseif cmd == 'invite' then
        if args[2] then
            scripts.general.invite(args[2])
        else
            print('Usage: /ab invite <name>')
        end
        return
    elseif cmd == 'leader' or cmd == 'passleader' then
        if args[2] then
            scripts.general.passleader(args[2])
        else
            print('Usage: /ab passleader <name>')
        end
        return
    elseif cmd == 'mount' then
        local mount = join_args(args, 2)
        if mount ~= '' then
            scripts.general.mount(mount)
        else
            scripts.general.mountup()
        end
        return
    elseif cmd == 'mountup' then
        local ok, result = scripts.general.random_mount()
        if ok then
            print('[Mount] Selected: ' .. tostring(result))
        else
            print('[Mount] ' .. tostring(result))
        end
        return
    elseif cmd == 'mountlist' then
        local mounts = scripts.general.get_available_mounts and scripts.general.get_available_mounts() or {}
        if #mounts == 0 then
            print('[Mount] No available mounts detected.')
        else
            print('[Mount] Available: ' .. table.concat(mounts, ', '))
        end
        return
    elseif cmd == 'dismount' then
        scripts.general.dismount()
        return
    elseif cmd == 'warpring' then
        scripts.general.usewarpring()
        return
    elseif cmd == 'trademe' or cmd == 'trade' then
        scripts.general.trade(args[2])
        return
    elseif cmd == 'accepttrade' then
        scripts.general.accept_trade()
        return
    elseif cmd == 'canceltrade' then
        scripts.general.cancel_trade()
        return
    elseif cmd == 'tradeallgil' then
        scripts.general.trade_all_gil()
        return
    end

    -------------------------------------------------
    -- INTERACTION
    -------------------------------------------------
    if cmd == 'npc' or cmd == 'tnpc' or cmd == 'targetnpc' then
        local name = join_args(args, 2)
        if name ~= '' then
            scripts.interaction.target_npc(name)
        else
            print('Usage: /ab tnpc <npc name>')
        end
        return
    elseif cmd == 'key' or cmd == 'press' then
        if args[2] then
            scripts.interaction.press_key(args[2])
        end
        return
    end

    -------------------------------------------------
    -- TRUSTS
    -------------------------------------------------
    if cmd == 'trust' or cmd == 'trusts' then
        local sub = args[2] and args[2]:lower()
        local name = join_args(args, 3)

        if sub == 'save' then
            if name ~= '' then
                scripts.trusts.save_set(name)
            else
                print('Usage: /ab trust save <set name>')
            end
        elseif sub == 'random' then
            scripts.trusts.summon_random()
        elseif sub == 'create' then
            if args[3] and args[4] then
                local set_name = args[3]
                local members = {}
                for i = 4, #args do
                    table.insert(members, args[i])
                end
                local ok, err = scripts.trusts.create_set(set_name, members)
                if not ok then
                    print('[Trusts] ' .. tostring(err))
                end
            else
                print('Usage: /ab trust create <set> <trusts...>')
            end
        elseif sub == 'add' then
            if args[3] and args[4] then
                local ok, err = scripts.trusts.add_to_set(args[3], join_args(args, 4))
                if not ok then
                    print('[Trusts] ' .. tostring(err))
                end
            else
                print('Usage: /ab trust add <set> <trust>')
            end
        elseif sub == 'remove' then
            if args[3] and tonumber(args[4]) then
                scripts.trusts.remove_from_set(args[3], tonumber(args[4]))
            else
                print('Usage: /ab trust remove <set> <index>')
            end
        elseif sub == 'delete' or sub == 'del' then
            if name ~= '' then
                scripts.trusts.delete_set(name)
            else
                print('Usage: /ab trust delete <set>')
            end
        elseif sub == 'summon' or sub == 'load' then
            if name ~= '' then
                scripts.trusts.summon_set(name)
            else
                print('Usage: /ab trust summon <set>')
            end
        elseif sub == 'release' then
            if name ~= '' then
                scripts.trusts.release(name)
            else
                print('Usage: /ab trust release <trust>')
            end
        elseif sub == 'releaseall' or sub == 'retrall' then
            scripts.trusts.release_all()
        elseif sub == 'list' then
            scripts.trusts.echo_sets()
        elseif sub then
            scripts.trusts.summon_set(join_args(args, 2))
        else
            scripts.trusts.summon_set('default')
        end

        return
    end

    -------------------------------------------------
    -- WARPING
    -------------------------------------------------
    if cmd == 'warp' or cmd == 'warpto' or cmd == 'uw' or cmd == 'uberwarp' or cmd == 'superwarp' then
        local wtype = args[2]
        local index = tonumber(args[#args])
        local last_location_arg = index and (#args - 1) or #args
        local location_parts = {}

        for i = 3, last_location_arg do
            table.insert(location_parts, args[i])
        end

        local location = table.concat(location_parts, ' ')

        if wtype and location ~= '' and scripts.uberwarp then
            scripts.uberwarp(wtype, location, index or 1)
        else
            print("Usage: /ab warp <type> <location> [index]  (example: /ab warp hp Southern San d'Oria 2)")
        end

        return
    end

    -------------------------------------------------
    -- NAVIGATION
    -------------------------------------------------
    if cmd == 'nav' then
        local sub = args[2] and args[2]:lower()

        if sub == 'record' then
            local path = join_args(args, 3)
            if path ~= '' then
                scripts.navigation.start_record(path)
            else
                print('Usage: /ab nav record <path>')
            end
        elseif sub == 'stop' then
            scripts.navigation.stop_record()
            scripts.navigation.stop_playback()
        elseif sub == 'start' then
            local path = join_args(args, 3)
            if path ~= '' then
                scripts.navigation.start_playback(path)
            else
                print('Usage: /ab nav start <path>')
            end
        elseif sub == 'pause' then
            scripts.navigation.pause_playback()
        elseif sub == 'resume' then
            scripts.navigation.resume_playback()
        elseif sub == 'loop' then
            if args[3] then
                scripts.navigation.set_loop(parse_toggle(args[3], false))
            else
                scripts.navigation.toggle_loop()
            end
        elseif sub == 'reverse' then
            if args[3] then
                scripts.navigation.set_reverse(parse_toggle(args[3], false))
            else
                scripts.navigation.toggle_reverse()
            end
        elseif sub == 'bounce' then
            if args[3] then
                scripts.navigation.set_bounce(parse_toggle(args[3], false))
            else
                scripts.navigation.toggle_bounce()
            end
        elseif sub == 'list' then
            local paths = scripts.navigation.list_paths and scripts.navigation.list_paths() or {}
            if #paths == 0 then
                print('[Navigation] No saved paths.')
            else
                print('[Navigation] Paths: ' .. table.concat(paths, ', '))
            end
        elseif sub == 'delete' and args[3] then
            scripts.navigation.delete_path(join_args(args, 3))
        elseif sub == 'details' and args[3] then
            local path = join_args(args, 3)
            local details = scripts.navigation.get_path_details(path)
            if details then
                print(string.format(
                    '[Navigation] %s: %s points, zone=%s, details=%s',
                    path,
                    tostring(details.point_count or 0),
                    tostring(details.zone_name or ''),
                    tostring(details.details or '')
                ))
            else
                print('[Navigation] Path not found: ' .. tostring(path))
            end
        elseif sub == 'setdetails' and args[3] then
            local path = args[3]
            local zone = args[4] or ''
            local details = join_args(args, 5)
            scripts.navigation.update_path_details(path, zone, details)
        else
            print('Usage: /ab nav record|start|pause|resume|stop|loop|reverse|bounce|list|details|setdetails|delete')
        end

        return
    end

    -------------------------------------------------
    -- COMBAT
    -------------------------------------------------
    if cmd == 'combat' then
        local sub = args[2] and args[2]:lower()
        config.combat = config.combat or {}

        if sub == 'autoengage' or sub == 'engage' then
            config.combat.auto_engage = parse_toggle(args[3], config.combat.auto_engage)
            save()
            print('[Combat] Auto Engage: ' .. (config.combat.auto_engage and 'ON' or 'OFF'))
        elseif sub == 'approach' then
            config.combat.approach = parse_toggle(args[3], config.combat.approach)
            save()
            print('[Combat] Approach: ' .. (config.combat.approach and 'ON' or 'OFF'))
        elseif sub == 'autoface' or sub == 'face' then
            config.combat.auto_face = parse_toggle(args[3], config.combat.auto_face)
            save()
            print('[Combat] Auto Face: ' .. (config.combat.auto_face and 'ON' or 'OFF'))
            if scripts.combat then
                if config.combat.auto_face and scripts.combat.start_face_loop then
                    scripts.combat.start_face_loop()
                elseif not config.combat.auto_face and scripts.combat.stop_face_loop then
                    scripts.combat.stop_face_loop()
                end
            end
        elseif sub == 'autoassist' or sub == 'assist' then
            config.combat.auto_assist = parse_toggle(args[3], config.combat.auto_assist)
            save()
            print('[Combat] Auto Assist: ' .. (config.combat.auto_assist and 'ON' or 'OFF'))
        elseif sub == 'assisttarget' or sub == 'assist_target' then
            local target = join_args(args, 3)
            if target ~= '' then
                config.combat.assist_target = target
                save()
                print('[Combat] Assist Target: ' .. target)
            else
                print('Usage: /ab combat assisttarget <name>')
            end
        else
            print('Usage: /ab combat autoengage|approach|autoface|autoassist|assisttarget')
        end

        refresh_module_settings(scripts, config)
        return
    end

    if cmd == 'move' then
        local distance
        local direction

        if tonumber(args[2]) then
            distance = tonumber(args[2])
            direction = args[3] and args[3]:lower()
        elseif tonumber(args[3]) then
            direction = args[2] and args[2]:lower()
            distance = tonumber(args[3])
        end

        if not distance or not direction then
            print('Usage: /ab move <yalms> <direction> or /ab move <direction> <yalms>')
            return
        end

        if config.modules.navigation ~= true then
            config.modules.navigation = true
            save()
        end

        -- A second command can arrive during the short lock-on release delay.
        -- Restore that pending maneuver before the new one captures settings.
        if directional_move_restore then
            config.combat.approach = directional_move_restore.approach
            config.combat.auto_face = directional_move_restore.auto_face
            refresh_module_settings(scripts, config)
            directional_move_restore = nil
        end

        -- Finish any prior path or relative maneuver first so its temporary
        -- combat settings are restored before this move captures them.
        scripts.navigation.stop_playback()

        directional_move_id = directional_move_id + 1
        local this_move_id = directional_move_id
        local engaged = false
        pcall(function()
            local player = AshitaCore:GetMemoryManager():GetPlayer()
            engaged = player and tonumber(player:GetStatus()) == 1 or false
        end)

        local restore_approach = false
        local restore_auto_face = false
        local function finish_combat_move()
            if this_move_id ~= directional_move_id or not engaged then
                return
            end

            config.combat.approach = restore_approach
            config.combat.auto_face = restore_auto_face
            directional_move_restore = nil
            refresh_module_settings(scripts, config)
            AshitaCore:GetChatManager():QueueCommand(1, '/lockon on')

            ashita.tasks.once(0.25, function()
                if this_move_id ~= directional_move_id then
                    return
                end

                local player_engaged = false
                pcall(function()
                    local player = AshitaCore:GetMemoryManager():GetPlayer()
                    player_engaged = player and tonumber(player:GetStatus()) == 1 or false
                end)

                if not player_engaged and config.combat.auto_engage == true then
                    AshitaCore:GetChatManager():QueueCommand(0, '/attack on')
                end

                if config.combat.auto_face == true and scripts.combat.start_face_loop then
                    scripts.combat.start_face_loop()
                end

                if config.combat.approach == true and scripts.combat.approach_target then
                    ashita.tasks.once(player_engaged and 0 or 0.5, function()
                        if this_move_id == directional_move_id then
                            scripts.combat.approach_target()
                        end
                    end)
                end
            end)
        end

        if engaged then
            config.combat = config.combat or {}
            restore_approach = config.combat.approach == true
            restore_auto_face = config.combat.auto_face == true
            directional_move_restore = {
                approach = restore_approach,
                auto_face = restore_auto_face,
            }
            config.combat.approach = false
            config.combat.auto_face = false
            refresh_module_settings(scripts, config)
            if scripts.combat.suspend_approach then
                scripts.combat.suspend_approach()
            end
            if scripts.combat.stop_face_loop then
                scripts.combat.stop_face_loop()
            end
            AshitaCore:GetChatManager():QueueCommand(1, '/movement navautoface off')
            AshitaCore:GetChatManager():QueueCommand(1, '/lockon off')
        end

        local function start_directional_move()
            if this_move_id ~= directional_move_id then
                return
            end

            if not scripts.navigation.move_relative(distance, direction, finish_combat_move) then
                finish_combat_move()
                print('[Navigation] Could not start directional movement. Check distance and direction.')
            end
        end

        if engaged then
            ashita.tasks.once(0.20, start_directional_move)
        else
            start_directional_move()
        end
        return
    end

    if cmd == 'attack' then
        scripts.combat.attack()
        return
    elseif cmd == 'assist' then
        local target = args[2] or AshitaCore:GetMemoryManager():GetPlayer():GetName()
        scripts.combat.assist(target)
        return
    elseif cmd == 'disengage' then
        scripts.combat.disengage()
        return
    elseif cmd == 'face' then
        local degrees = tonumber(args[2])

        if not degrees then
            print('Usage: /ab face <degrees>')
            return
        end

        local ok, err = scripts.combat.set_rotation_degrees(degrees)

        if ok then
            print(string.format('[Combat] Rotation set to %.1f degrees.', degrees))
        else
            print('[Combat] Rotation failed: ' .. tostring(err))
        end

        return
    elseif cmd == 'facecheck' then
        local ok, message = scripts.combat.facecheck()
        local status = ok and 'OK' or 'FAILED'

        if type(message) == 'table' then
            for i, line in ipairs(message) do
                if line then
                    local prefix = i == 1 and ('[Combat] Facecheck ' .. status .. ': ') or '[Combat] '
                    print(prefix .. tostring(line))
                end
            end
        else
            print('[Combat] Facecheck ' .. status .. ': ' .. tostring(message))
        end

        return
    end

    -------------------------------------------------
    -- JOB MODULES
    -------------------------------------------------
    if cmd == 'job' then
        if not scripts.jobs or not scripts.jobs.command then
            print('[Jobs] Job module controller is not loaded.')
            return
        end

        local job = args[2]
        local subcmd = args[3] and args[3]:lower() or 'status'
        local forwarded = {}
        for i = 4, #args do
            table.insert(forwarded, args[i])
        end

        if job and (job:lower() == 'main' or job:lower() == 'sub') and scripts.jobs.get_job_info then
            local info = scripts.jobs.get_job_info()
            job = info[job:lower()] and info[job:lower()].job or nil
        end

        if subcmd == 'status' then
            local status = scripts.jobs.get_status and scripts.jobs.get_status() or {}
            for role, detail in pairs(status) do
                print(string.format('[Jobs] %s: %s %s - %s',
                    role,
                    tostring(detail.job or 'none'),
                    tostring(detail.level or 0),
                    tostring(detail.message or (detail.running and 'Running' or 'Stopped'))))
            end
            return
        end

        local ok, err = scripts.jobs.command(job, subcmd, forwarded)
        if not ok then
            print('[Jobs] ' .. tostring(err or 'command failed'))
        end
        return
    end

    -------------------------------------------------
    -- CASTING
    -------------------------------------------------
    if cmd == 'cast' then
        local spell, target = parse_action_name_and_target(args, 2)
        if spell == '' or not scripts.casting.cast_spell(spell, target) then
            print('Usage: /ab cast <spell name> [target]')
        end
        return
    elseif cmd == 'ability' or cmd == 'abil' then
        local ability, target = parse_action_name_and_target(args, 2)
        if ability == '' or not scripts.casting.use_ability(ability, target) then
            print('Usage: /ab ability <ability name> [target]')
        end
        return
    elseif cmd == 'stopcasting' then
        scripts.casting.stop_casting()
        return
    end

    -------------------------------------------------
    -- FALLBACK
    -------------------------------------------------
    print('Unknown command.')
end

return commands
