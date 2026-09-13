local jobs = {}
local shared_state = require('modules.state')

local config = nil
local save = nil

local loaded = {}
local status = {
    main = {},
    sub = {},
}
local scheduled = {}

local job_names = {
    [1] = 'WAR', [2] = 'MNK', [3] = 'WHM', [4] = 'BLM', [5] = 'RDM', [6] = 'THF',
    [7] = 'PLD', [8] = 'DRK', [9] = 'BST', [10] = 'BRD', [11] = 'RNG', [12] = 'SAM',
    [13] = 'NIN', [14] = 'DRG', [15] = 'SMN', [16] = 'BLU', [17] = 'COR', [18] = 'PUP',
    [19] = 'DNC', [20] = 'SCH', [21] = 'GEO', [22] = 'RUN',
}

local last_key = ''
local normalize_job
local player

local function install_compat()
    package.loaded.config = package.loaded.config or {
        save = function()
            if save then
                save()
            end
        end,
    }

    package.loaded.resources = package.loaded.resources or {
        buffs = {},
        job_abilities = {
            with = function()
                return nil
            end,
        },
    }

    _G.windower = _G.windower or {}
    coroutine.schedule = coroutine.schedule or function(fn, delay)
        if type(fn) ~= 'function' then
            return
        end

        table.insert(scheduled, {
            due = os.clock() + (tonumber(delay) or 0),
            fn = fn,
        })
    end

    windower.add_to_chat = windower.add_to_chat or function(_, message)
        AshitaCore:GetChatManager():QueueCommand(1, '/echo ' .. tostring(message))
    end
    windower.send_command = windower.send_command or function(command)
        command = tostring(command or '')
        command = command:gsub('^input%s+', '')
        AshitaCore:GetChatManager():QueueCommand(1, command)
    end

    windower.ffxi = windower.ffxi or {}
    windower.ffxi.get_player = windower.ffxi.get_player or function()
        local p = player()
        if not p then
            return nil
        end

        local function call(method)
            local ok, value = pcall(function()
                return p[method](p)
            end)
            return ok and value or nil
        end

        local buffs = {}
        local ok_buffs, raw_buffs = pcall(function()
            return p:GetBuffs()
        end)
        if not ok_buffs or not raw_buffs then
            ok_buffs, raw_buffs = pcall(function()
                return p:GetStatusIcons()
            end)
        end
        if ok_buffs and raw_buffs then
            for i = 0, 31 do
                local ok_buff, buff = pcall(function()
                    return raw_buffs[i]
                end)
                if ok_buff and tonumber(buff) and tonumber(buff) > 0 then
                    table.insert(buffs, tonumber(buff))
                end
            end
        end

        local party = AshitaCore:GetMemoryManager():GetParty()
        local function party_call(method)
            if not party then
                return nil
            end

            local ok, value = pcall(function()
                return party[method](party, 0)
            end)

            return ok and value or nil
        end

        local status = tonumber(call('GetStatus')) or 0
        local entity = AshitaCore:GetMemoryManager():GetEntity()
        local player_index = tonumber(party_call('GetMemberTargetIndex')) or 0
        if entity and player_index > 0 then
            local ok_status, entity_status = pcall(function()
                return entity:GetStatus(player_index)
            end)
            if ok_status and entity_status ~= nil then
                status = tonumber(entity_status) or status
            end
        end

        return {
            status = status,
            main_job = normalize_job(call('GetMainJob')),
            sub_job = normalize_job(call('GetSubJob')),
            main_job_level = tonumber(call('GetMainJobLevel')) or 0,
            sub_job_level = tonumber(call('GetSubJobLevel')) or 0,
            buffs = buffs,
            vitals = {
                tp = tonumber(party_call('GetMemberTP')) or tonumber(call('GetTP')) or 0,
                hp = tonumber(party_call('GetMemberHP')) or tonumber(call('GetHP')) or 0,
                max_hp = tonumber(party_call('GetMemberMaxHP')) or tonumber(call('GetMaxHP')) or 0,
                mp = tonumber(party_call('GetMemberMP')) or tonumber(call('GetMP')) or 0,
                max_mp = tonumber(party_call('GetMemberMaxMP')) or tonumber(call('GetMaxMP')) or 0,
                hpp = tonumber(party_call('GetMemberHPPercent')) or 100,
                mpp = tonumber(party_call('GetMemberMPPercent')) or 100,
            },
        }
    end
    windower.ffxi.get_ability_recasts = windower.ffxi.get_ability_recasts or function()
        return setmetatable({}, {
            __index = function(_, timer_id)
                local ok, recast = pcall(function()
                    return AshitaCore:GetMemoryManager():GetRecast()
                end)

                if ok
                and recast
                and recast.GetAbilityTimerId
                and recast.GetAbilityTimer
                then
                    timer_id = tonumber(timer_id)

                    for slot = 0, 31 do
                        local ok_id, slot_timer_id = pcall(function()
                            return recast:GetAbilityTimerId(slot)
                        end)

                        if ok_id and tonumber(slot_timer_id) == timer_id then
                            local ok_timer, timer = pcall(function()
                                return recast:GetAbilityTimer(slot)
                            end)

                            if ok_timer then
                                return tonumber(timer) or 0
                            end
                        end
                    end
                end

                return 0
            end,
        })
    end
    windower.ffxi.get_party = windower.ffxi.get_party or function()
        local party = AshitaCore:GetMemoryManager():GetParty()
        local result = { party1_count = 0 }
        if not party then
            return result
        end

        local function party_call(method, index)
            local ok, value = pcall(function()
                return party[method](party, index)
            end)
            return ok and value or nil
        end

        local function member_buffs(index)
            local buffs = {}
            for _, method in ipairs({ 'GetMemberBuffs', 'GetMemberStatusIcons' }) do
                local raw = party_call(method, index)
                if raw then
                    for i = 0, 31 do
                        local ok_buff, buff = pcall(function()
                            return raw[i]
                        end)
                        if ok_buff and tonumber(buff) and tonumber(buff) > 0 then
                            table.insert(buffs, tonumber(buff))
                        end
                    end
                    if #buffs > 0 then
                        return buffs
                    end
                end
            end

            if index == 0 then
                local p = windower.ffxi.get_player()
                return p and p.buffs or buffs
            end

            return buffs
        end

        for i = 0, 5 do
            local active = 0
            pcall(function()
                active = party:GetMemberIsActive(i)
            end)

            if active == true or tonumber(active) == 1 then
                result.party1_count = result.party1_count + 1
                result['p' .. tostring(i)] = {
                    name = party_call('GetMemberName', i),
                    hp = tonumber(party_call('GetMemberHP', i)) or 0,
                    max_hp = tonumber(party_call('GetMemberMaxHP', i)) or 0,
                    mp = tonumber(party_call('GetMemberMP', i)) or 0,
                    max_mp = tonumber(party_call('GetMemberMaxMP', i)) or 0,
                    hpp = tonumber(party_call('GetMemberHPPercent', i)) or 0,
                    mpp = tonumber(party_call('GetMemberMPPercent', i)) or 0,
                    buffs = member_buffs(i),
                    index = tonumber(party_call('GetMemberTargetIndex', i)) or 0,
                }
            end
        end

        return result
    end
    windower.ffxi.get_mob_by_target = windower.ffxi.get_mob_by_target or function()
        return nil
    end

end

local function echo(message)
    AshitaCore:GetChatManager():QueueCommand(1, '/echo [AutoBot] Jobs: ' .. tostring(message))
end

normalize_job = function(value)
    if type(value) == 'string' then
        value = value:upper()
        return value ~= '' and value or nil
    end

    return job_names[tonumber(value or 0)]
end

player = function()
    local ok, p = pcall(function()
        return AshitaCore:GetMemoryManager():GetPlayer()
    end)

    return ok and p or nil
end

local function read_job_info()
    local p = player()
    if not p then
        return {
            main = { job = nil, level = 0 },
            sub = { job = nil, level = 0 },
        }
    end

    local function call(method)
        local ok, value = pcall(function()
            return p[method](p)
        end)

        return ok and value or nil
    end

    return {
        main = {
            job = normalize_job(call('GetMainJob') or call('GetMainJobId')),
            level = tonumber(call('GetMainJobLevel')) or 0,
        },
        sub = {
            job = normalize_job(call('GetSubJob') or call('GetSubJobId')),
            level = tonumber(call('GetSubJobLevel')) or 0,
        },
    }
end

local function ensure_settings(job)
    config.job_modules = config.job_modules or {}
    config.job_modules[job] = config.job_modules[job] or {}
    config.job_modules[job].enabled = config.job_modules[job].enabled == true
    return config.job_modules[job]
end

local function load_module(job)
    if not job or job == '' then
        return nil, 'No Job Script Found...'
    end

    if loaded[job] ~= nil then
        return loaded[job].module, loaded[job].error
    end

    local path = string.format('%saddons/autobot/jobs/%s.lua', AshitaCore:GetInstallPath(), job)
    local f = io.open(path, 'r')
    if not f then
        loaded[job] = {
            module = nil,
            error = 'No Job Script Found...',
            initialized = false,
            running = false,
        }
        return nil, loaded[job].error
    end
    f:close()

    install_compat()

    local ok, module = pcall(require, 'jobs.' .. job)
    loaded[job] = {
        module = ok and type(module) == 'table' and module or nil,
        error = nil,
        initialized = false,
        running = false,
    }

    if not ok then
        loaded[job].error = 'Load error: ' .. tostring(module)
        return nil, loaded[job].error
    end

    if type(module) ~= 'table' then
        loaded[job].error = 'Job script did not return a module table.'
        return nil, loaded[job].error
    end

    return loaded[job].module, nil
end

local function init_module(job)
    local module, err = load_module(job)
    local state = loaded[job]

    if not module or not state then
        return false, err or 'No Job Script Found...'
    end

    if state.initialized then
        return true
    end

    if type(module.init) == 'function' then
        local ok, init_err = pcall(function()
            module.init(ensure_settings(job))
        end)

        if not ok then
            state.error = tostring(init_err)
            return false, state.error
        end
    end

    state.initialized = true
    state.error = nil
    return true
end

local function stop_job(job, force)
    local state = job and loaded[job] or nil
    if not state or not state.module then
        return false
    end

    if state.running ~= true and force ~= true then
        return false
    end

    if type(state.module.stop) == 'function' then
        pcall(function()
            state.module.stop()
        end)
    end

    state.running = false
    return true
end

local function start_job(job)
    local ok, err = init_module(job)
    if not ok then
        return false, err
    end

    local state = loaded[job]
    if not state or not state.module then
        return false, 'job module unavailable'
    end

    if type(state.module.tick) ~= 'function' then
        return false, 'Loaded; no Ashita tick handler yet.'
    end

    if type(state.module.start) == 'function' then
        local start_ok, start_err = pcall(function()
            state.module.start()
        end)

        if not start_ok then
            state.error = tostring(start_err)
            return false, state.error
        end
    end

    state.running = true
    state.error = nil
    return true
end

local function process_scheduled()
    local now = os.clock()

    for i = #scheduled, 1, -1 do
        local task = scheduled[i]
        if task.due <= now then
            table.remove(scheduled, i)
            local ok, err = pcall(task.fn)
            if not ok then
                if shared_state.debug == true then
                    echo('Scheduled job task failed: ' .. tostring(err))
                end
            end
        end
    end
end

local function sync_role(role, info)
    local job = info and info.job or nil
    status[role] = {
        job = job,
        level = info and info.level or 0,
        loaded = false,
        running = false,
        message = 'No Job Script Found...',
    }

    if not job then
        return
    end

    local ok, err = init_module(job)
    local state = loaded[job]

    status[role].loaded = ok
    status[role].message = ok and 'Loaded' or (err or 'No Job Script Found...')

    if not ok or not state or not state.module then
        return
    end

    local settings = ensure_settings(job)
    if settings.enabled then
        if type(state.module.tick) ~= 'function' then
            status[role].message = 'Loaded; no Ashita tick handler yet.'
            return
        end

        if not state.running and type(state.module.start) == 'function' then
            local start_ok, start_err = pcall(function()
                state.module.start()
            end)
            if not start_ok then
                status[role].message = tostring(start_err)
                return
            end
        end
        state.running = true
    else
        stop_job(job)
    end

    status[role].running = state.running == true
end

function jobs.set_config(cfg, save_func)
    config = cfg
    save = save_func
    config.job_modules = config.job_modules or {}

    -- Job automation is session-dormant by design. Never honor a persisted
    -- enabled state during addon load; the user must explicitly enable the
    -- desired job module after loading into a safe area.
    local changed = false
    for _, settings in pairs(config.job_modules) do
        if type(settings) == 'table' and settings.enabled == true then
            settings.enabled = false
            changed = true
        end
    end
    scheduled = {}

    if changed and save then
        save()
    end
end

function jobs.get_job_info()
    return read_job_info()
end

function jobs.get_status()
    return status
end

function jobs.get_module(job)
    job = normalize_job(job)
    if not job then
        return nil
    end

    local ok = init_module(job)
    if not ok then
        return nil
    end

    return loaded[job] and loaded[job].module or nil
end

function jobs.tick()
    if not config or not config.modules or config.modules.jobs ~= true then
        return
    end


    -- Do not consume the action lock during the pull cast or before the
    -- post-pull attack handoff has engaged. Once engaged, job automation
    -- can safely resume even if Pulling has not cleared its completion flag.
    local current_player = player()
    local player_status = nil
    local entity_status = nil
    if current_player then
        pcall(function()
            player_status = tonumber(current_player:GetStatus())
        end)
    end

    local party = AshitaCore:GetMemoryManager():GetParty()
    local entity = AshitaCore:GetMemoryManager():GetEntity()
    if party and entity then
        pcall(function()
            local player_index = tonumber(party:GetMemberTargetIndex(0)) or 0
            if player_index > 0 then
                entity_status = tonumber(entity:GetStatus(player_index))
            end
        end)
    end

    local player_engaged = player_status == 1 or entity_status == 1

    local pull_blocks_jobs = shared_state.pull_in_progress == true
        or (shared_state.pull_completed == true and not player_engaged)

    process_scheduled()

    local info = read_job_info()
    local key = tostring(info.main.job or '') .. ':' .. tostring(info.main.level or 0)
        .. '/' .. tostring(info.sub.job or '') .. ':' .. tostring(info.sub.level or 0)

    if key ~= last_key then
        jobs.stop_all()
        last_key = key
    end

    sync_role('main', info.main)
    sync_role('sub', info.sub)

    for job, state in pairs(loaded) do
        if state.module
        and state.running
        and type(state.module.tick) == 'function'
        and (not pull_blocks_jobs or job == 'RDM')
        then
            local ok, err = pcall(function()
                state.module.tick()
            end)
            if not ok then
                state.error = tostring(err)
                state.running = false
            end
        end
    end
end

function jobs.stop_all(reason, disable)
    local stopped = false
    scheduled = {}

    if disable and config then
        config.job_modules = config.job_modules or {}
        for job, settings in pairs(config.job_modules) do
            if type(settings) == 'table' and settings.enabled == true then
                settings.enabled = false
                stopped = true
            end
        end
    end

    for job, _ in pairs(loaded) do
        if stop_job(job, disable == true) then
            stopped = true
        end
    end

    if reason and stopped then
        if shared_state.debug == true then
            echo('Stopped job modules: ' .. tostring(reason))
        end
    end

    if stopped and disable and save then
        save()
    end
end

function jobs.command(job, subcmd, args)
    job = normalize_job(job)
    if not job then
        return false, 'missing job'
    end

    subcmd = tostring(subcmd or 'status'):lower()
    local settings = ensure_settings(job)

    if subcmd == 'stop' or subcmd == 'off' or subcmd == 'disable' or subcmd == 'disabled' then
        settings.enabled = false
        stop_job(job, true)
        if save then
            save()
        end
        echo(job .. ' disabled.')
        return true
    end

    if subcmd == 'start' or subcmd == 'on' or subcmd == 'enable' or subcmd == 'enabled' then
        settings.enabled = true
        local start_ok, start_err = start_job(job)
        if save then
            save()
        end
        if start_ok then
            echo(job .. ' enabled.')
        end
        return start_ok, start_err
    end

    if subcmd == 'toggle' then
        if settings.enabled then
            settings.enabled = false
            stop_job(job, true)
            if save then
                save()
            end
            echo(job .. ' disabled.')
            return true
        end

        settings.enabled = true
        local start_ok, start_err = start_job(job)
        if save then
            save()
        end
        if start_ok then
            echo(job .. ' enabled.')
        end
        return start_ok, start_err
    end

    local ok, err = init_module(job)
    if not ok then
        return false, err
    end

    if subcmd == 'status' then
        return true
    end

    local module = loaded[job] and loaded[job].module
    if not module or type(module.command) ~= 'function' then
        return false, 'job module has no command handler'
    end

    local cmd_ok, cmd_err = pcall(function()
        module.command(subcmd, args or {})
    end)

    if cmd_ok and save then
        save()
    end

    return cmd_ok, cmd_ok and nil or tostring(cmd_err)
end

return jobs
