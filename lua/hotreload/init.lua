---@class Options
---@field interval integer|nil Check interval in milliseconds (nil to disable polling, use fs_event only)
---@field silent boolean Suppress reload notifications (default: true)

---@class Module
---@field options Options
---@field timer unknown
---@field watchers table<integer, unknown>
local M = {}

---@type Options
local DEFAULT_OPTIONS = {
    interval = nil,  -- Use fs_event by default, no polling
    silent = true,
}

-- Track fs_event watchers per buffer
local watchers = {}

---@param tbl table
---@return Options
local function options_from_table(tbl)
    assert(tbl == nil or type(tbl) == "table", "options value should be nil or a table")
    local opts = vim.deepcopy(DEFAULT_OPTIONS, true)
    local function merge(lhs, rhs)
        assert(type(lhs) == "table")
        if rhs == nil then return lhs end
        for key, value in pairs(rhs) do
            if type(value) == "table" and type(lhs[key]) == "table" then
                merge(lhs[key], value)
            else
                lhs[key] = value
            end
        end
    end
    merge(opts, tbl)
    return opts
end

---@param buf integer
---@return boolean
local function does_buffer_have_backing_file(buf)
    local file = vim.api.nvim_buf_get_name(buf)
    return file ~= ''
end

---@param buf integer
---@return boolean
local function is_buffer_modified(buf)
    return vim.api.nvim_get_option_value('modified', { buf = buf })
end

---@param buf integer
---@param silent boolean
---@return nil
local function reload_buffer_if_unmodified(buf, silent)
    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end

    if not does_buffer_have_backing_file(buf) then
        return
    end

    if not is_buffer_modified(buf) then
        if silent then
            -- Temporarily ignore FileChangedShell events to suppress messages
            local old_eventignore = vim.o.eventignore
            -- Append to existing eventignore instead of replacing
            if old_eventignore == '' then
                vim.o.eventignore = 'FileChangedShell'
            else
                vim.o.eventignore = old_eventignore .. ',FileChangedShell'
            end

            -- Wrap in pcall to handle buffer becoming invalid
            pcall(vim.api.nvim_buf_call, buf, function()
                vim.cmd('silent! checktime')
            end)

            vim.o.eventignore = old_eventignore
        else
            vim.cmd('checktime')
        end
    end
end

---Stop watching a buffer
---@param buf integer
local function stop_watching_buffer(buf)
    local w = watchers[buf]
    if w then
        pcall(function()
            w:stop()
        end)
        watchers[buf] = nil
    end
end

---Start watching a buffer for file system changes
---@param buf integer
---@param silent boolean
local function start_watching_buffer(buf, silent)
    -- If already watching, don't create another watcher
    if watchers[buf] then
        return
    end

    if not vim.api.nvim_buf_is_valid(buf) then
        return
    end

    local file = vim.api.nvim_buf_get_name(buf)
    if file == '' then
        return
    end

    local w = vim.uv.new_fs_event()
    if not w then
        -- Only warn once per session to avoid spam
        if not M._fs_event_warned then
            vim.notify('hotreload.nvim: Failed to create fs_event watcher. Falling back to polling if enabled.', vim.log.levels.WARN)
            M._fs_event_warned = true
        end
        return
    end

    local function on_change(err, fname, status)
        if err then
            -- Stop watching on error
            vim.schedule(function()
                stop_watching_buffer(buf)
            end)
            return
        end

        vim.schedule(function()
            reload_buffer_if_unmodified(buf, silent)
        end)
    end

    local ok, err = pcall(function()
        w:start(file, {}, vim.schedule_wrap(on_change))
    end)

    if ok then
        watchers[buf] = w
    else
        -- Log watcher start failure
        if not M._fs_event_start_warned then
            vim.notify('hotreload.nvim: Failed to start fs_event watcher: ' .. tostring(err), vim.log.levels.WARN)
            M._fs_event_start_warned = true
        end
    end
end

---Update watchers to match currently loaded buffers
local function update_watchers()
    -- Get all loaded buffers with backing files
    local loaded_buffers = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) and does_buffer_have_backing_file(buf) then
            loaded_buffers[buf] = true
        end
    end

    -- Stop watching buffers that are no longer loaded or valid
    for buf, _ in pairs(watchers) do
        if not loaded_buffers[buf] or not vim.api.nvim_buf_is_valid(buf) then
            stop_watching_buffer(buf)
        end
    end

    -- Start watching newly loaded buffers
    for buf, _ in pairs(loaded_buffers) do
        local was_not_watching = not watchers[buf]
        start_watching_buffer(buf, M.options.silent)
        -- If we just started watching this buffer, check if it was modified while not watched
        if was_not_watching then
            reload_buffer_if_unmodified(buf, M.options.silent)
        end
    end
end

---Reload all visible buffers (used for polling fallback)
---@param silent boolean
local function reload_visible_buffers(silent)
    -- Get all visible buffers by iterating through windows
    local visible_buffers = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        visible_buffers[buf] = true
    end

    -- Only reload buffers that are currently visible
    for buf, _ in pairs(visible_buffers) do
        reload_buffer_if_unmodified(buf, silent)
    end
end

---Setup the hotreload plugin
---@param opts table
---@return nil
function M.setup(opts)
    M.options = options_from_table(opts)

    -- Validate options
    if M.options.interval ~= nil then
        assert(type(M.options.interval) == 'number', 'hotreload.nvim: interval must be a number or nil')
        assert(M.options.interval > 0, 'hotreload.nvim: interval must be positive')
    end
    assert(type(M.options.silent) == 'boolean', 'hotreload.nvim: silent must be a boolean')

    -- Set up fs_event watchers for all loaded buffers
    -- BufEnter: When entering any buffer
    -- BufAdd: When a buffer is added to the buffer list
    -- FocusGained: When Neovim gains focus (e.g., switching tmux panes)
    vim.api.nvim_create_autocmd({'BufEnter', 'BufAdd', 'FocusGained'}, {
        callback = function()
            update_watchers()
        end
    })

    -- Clean up watchers when buffers are deleted
    vim.api.nvim_create_autocmd('BufDelete', {
        callback = function(args)
            stop_watching_buffer(args.buf)
        end
    })

    -- Clean up all watchers on exit
    vim.api.nvim_create_autocmd('VimLeavePre', {
        callback = function()
            for buf, _ in pairs(watchers) do
                stop_watching_buffer(buf)
            end
        end
    })

    -- Optional: Set up polling timer if interval is specified
    if M.options.interval and M.options.interval > 0 then
        local timer = vim.uv.new_timer()
        vim.uv.timer_start(timer, M.options.interval, M.options.interval, vim.schedule_wrap(function()
            reload_visible_buffers(M.options.silent)
        end))
        M.timer = timer
    end

    -- Initialize watchers for currently visible buffers
    update_watchers()
end

return M
