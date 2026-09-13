local remote = {}

-------------------------------------------------
-- CONFIG
-------------------------------------------------
remote.prefix = 'bot'     -- "bot followme"
remote.bang   = true      -- "!followme" support

local PARTY_MODES = { [13] = true, [215] = true }
local TELL_MODES = { [3] = true, [4] = true }

-- Basic rate limiting (per sender)
local last_exec = {}
local RATE_LIMIT = 0.5 -- seconds
local last_exec_prune = 0

-------------------------------------------------
-- HELPERS
-------------------------------------------------
local function split(input)
    local t = {}
    local current = ''
    local quote = nil
    local i = 1

    while i <= #input do
        local ch = input:sub(i, i)

        if quote then
            if ch == quote then
                quote = nil
            elseif ch == '\\' and i < #input and input:sub(i + 1, i + 1) == quote then
                current = current .. quote
                i = i + 1
            else
                current = current .. ch
            end
        elseif (ch == '"' or ch == "'") and current == '' then
            quote = ch
        elseif ch:match('%s') then
            if current ~= '' then
                table.insert(t, current)
                current = ''
            end
        else
            current = current .. ch
        end

        i = i + 1
    end

    if current ~= '' then
        table.insert(t, current)
    end

    return t
end

local function trim(value)
    return (value and tostring(value):match('^%s*(.-)%s*$')) or ''
end

local function clean_message(value)
    local text = tostring(value or '')
    text = text:gsub('\x1E.', ''):gsub('\x1F.', '')
    text = text:gsub('^%s*|%d+|%s*', '')
    text = text:gsub('^%s*%[%d%d:%d%d:?%d?%d?%]%s*', '')
    return trim(text:gsub('%c', ''))
end

local function mode_byte(value)
    local n = tonumber(value) or 0
    return n % 256
end

local function party_sender_from_index(index)
    if not index or type(index) ~= 'number' then
        return nil
    end

    local ok, name =
        pcall(function()
            local party = AshitaCore:GetMemoryManager():GetParty()

            if party and party:GetMemberIsActive(index) == 1 then
                return party:GetMemberName(index)
            end

            return nil
        end)

    if ok and name and name ~= '' then
        return name
    end

    return nil
end

local function parse_sender_message(raw, mode, sender_index)
    raw = clean_message(raw)

    if raw == '' then
        return nil, nil, nil
    end

    if PARTY_MODES[mode] then
        local sender = party_sender_from_index(sender_index)
        local text_sender, text = raw:match('^%s*<([%a][%w_%-]+)>%s*(.+)$')

        if text_sender and text then
            return text_sender, trim(text), 'party'
        end

        text_sender, text = raw:match('^%s*([%w_%-]+)%s*:%s*(.+)$')

        if text_sender and text then
            return text_sender, trim(text), 'party'
        end

        text_sender, text = raw:match('^%s*%(([%w_%-]+)%)%s*(.+)$')
        if text_sender and text then
            return text_sender, trim(text), 'party'
        end

        if sender then
            return sender, raw, 'party'
        end

        return nil, nil, nil
    end

    if TELL_MODES[mode] then
        local text_sender, text = raw:match('^%s*<([%a][%w_%-]+)>%s*(.+)$')

        if text_sender and text then
            return text_sender, trim(text), 'tell'
        end

        text_sender, text = raw:match('^%s*([%w_%-]+)%s*>>%s*(.+)$')

        if text_sender and text then
            return text_sender, trim(text), 'tell'
        end

        text_sender, text = raw:match('^%s*%[Tell%]%s*([%w_%-]+)%s*:%s*(.+)$')
        if text_sender and text then
            return text_sender, trim(text), 'tell'
        end

        text_sender, text = raw:match('^%s*>>%s*([%w_%-]+)%s*:%s*(.+)$')
        if text_sender and text then
            return text_sender, trim(text), 'tell'
        end

        text_sender, text = raw:match('^%s*Tell from%s+([%w_%-]+)%s*:%s*(.+)$')
        if text_sender and text then
            return text_sender, trim(text), 'tell'
        end

        text_sender, text = raw:match('^%s*([%w_%-]+)%s+tells you,?%s*(.+)$')
        if text_sender and text then
            return text_sender, trim(text), 'tell'
        end
    end

    return nil, nil, nil
end

local function parse_unknown_tell(raw)
    raw = clean_message(raw)

    -- Ashita builds differ in the mode assigned to tells. Only accept an
    -- unknown-mode line when it has an incoming sender shape and begins with
    -- an explicit AutoBot command.
    local sender, message = raw:match('^%s*<([%a][%w_%-]+)>%s*(.+)$')
    if not sender then
        sender, message = raw:match('^%s*([%a][%w_%-]+)%s*>>%s*(.+)$')
    end
    if not sender then
        sender, message = raw:match('^%s*%[Tell%]%s*([%a][%w_%-]+)%s*:%s*(.+)$')
    end
    if not sender then
        sender, message = raw:match('^%s*Tell from%s+([%a][%w_%-]+)%s*:%s*(.+)$')
    end
    if not sender then
        sender, message = raw:match('^%s*([%a][%w_%-]+)%s+tells you,?%s*(.+)$')
    end

    message = trim(message)
    if not sender or not (
        message:lower():match('^bot%s+[%w_%-]+')
        or message:match('^![%w_%-]+')
    ) then
        return nil, nil, nil
    end

    return sender, message, 'tell'
end

local function event_to_remote(e)
    if not e then
        return nil, nil, nil
    end

    local raw = clean_message(e.message_modified or e.message or '')
    local mode = mode_byte(e.mode_modified or e.mode or 0)

    -- Outgoing tells are echoed locally as ">> Name : message". They must
    -- never be interpreted as commands received by this character.
    if raw:match('^%s*>>') then
        return nil, nil, nil
    end

    if e.sender and (e.message_modified or e.message) then
        -- When Ashita supplies sender separately, e.message is normally the
        -- command body while e.message_modified may include "<Sender>".
        local message = clean_message(e.message or e.message_modified)
        if PARTY_MODES[mode] then
            return e.sender, message, 'party'
        end
        if TELL_MODES[mode] then
            return e.sender, message, 'tell'
        end
        if message:lower():match('^bot%s+[%w_%-]+')
        or message:match('^![%w_%-]+')
        then
            return e.sender, message, 'tell'
        end
    end

    if not PARTY_MODES[mode] and not TELL_MODES[mode] then
        return parse_unknown_tell(raw)
    end

    return parse_sender_message(raw, mode, e.sender_index)
end

local function now()
    return os.clock()
end

local function can_execute(sender)
    local t = now()

    if (t - last_exec_prune) >= 300 then
        last_exec_prune = t
        for name, executed_at in pairs(last_exec) do
            if (t - executed_at) >= 600 then
                last_exec[name] = nil
            end
        end
    end

    if not last_exec[sender] then
        last_exec[sender] = t
        return true
    end

    if (t - last_exec[sender]) < RATE_LIMIT then
        return false
    end

    last_exec[sender] = t
    return true
end

-------------------------------------------------
-- MAIN HANDLER
-------------------------------------------------
remote.handle_message = function(sender, message, source, context)
    local whitelist = context.whitelist
    local execute   = context.execute
    local handle_args = context.handle_args
    local respond = context.respond

    if not message or not sender then return end

    sender = trim(sender)
    message = trim(message)

    if sender == '' or message == '' then return end

    -------------------------------------------------
    -- SECURITY: WHITELIST
    -------------------------------------------------
    if not whitelist(sender) then
        return
    end

    -------------------------------------------------
    -- RATE LIMIT
    -------------------------------------------------
    if not can_execute(sender) then
        return
    end

    -------------------------------------------------
    -- PARSE MESSAGE
    -------------------------------------------------
    local args = split(message)
    if #args == 0 then return end

    local command = nil
    local start_index = 2

    -- "bot command"
    if args[1]:lower() == remote.prefix then
        command = args[2] and args[2]:lower()
        start_index = 3
    end

    -- "!command"
    if not command and remote.bang and args[1]:sub(1,1) == '!' then
        command = args[1]:sub(2):lower()
        start_index = 2
    end

    if not command then
        return
    end

    if respond then
        respond(source, sender, command)
    end

    -------------------------------------------------
    -- RAW CHAT COMMAND
    -------------------------------------------------
    if command == 'command' then
        local raw_command

        if args[1]:lower() == remote.prefix then
            raw_command = message:match('^%s*%S+%s+%S+%s+(.+)$')
        else
            raw_command = message:match('^%s*%S+%s+(.+)$')
        end

        raw_command = trim(raw_command)
        if raw_command ~= '' and execute then
            execute(raw_command)
        end
        return
    end

    -------------------------------------------------
    -- BUILD FINAL COMMAND STRING
    -------------------------------------------------
    local final_args = { command }

    for i = start_index, #args do
        table.insert(final_args, args[i])
    end

    -------------------------------------------------
    -- SPECIAL HANDLING (OPTIONAL SHORTCUTS)
    -------------------------------------------------

    -- followme → auto insert sender
    if command == 'followme' then
        final_args = { 'follow', sender }
    end

    -- trademe → auto insert sender
    if command == 'trademe' then
        final_args = { 'trademe', sender }
    end

    -- inviteme → invite the remote-command sender
    if command == 'inviteme' then
        final_args = { 'invite', sender }
    end

    -- A bare passleader command defaults to the remote-command sender.
    if command == 'passleader' and #final_args == 1 then
        final_args = { 'passleader', sender }
    end

    -- A bare assist command assists the remote-command sender.
    if command == 'assist' and #final_args == 1 then
        final_args = { 'assist', sender }
    end

    -------------------------------------------------
    -- EXECUTE
    -------------------------------------------------
    if handle_args then
        handle_args(final_args, sender, source)
        return
    end

    if execute then
        execute('/autobot ' .. table.concat(final_args, ' '))
    end
end

remote.handle = function(e, context)
    local sender, message, source = event_to_remote(e)
    remote.handle_message(sender, message, source, context)
end

return remote
