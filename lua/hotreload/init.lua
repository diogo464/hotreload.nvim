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
            -- Capture and discard output to fully suppress messages
            vim.fn.execute('checktime', 'silent')
        else
            vim.cmd('checktime')
        end
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

---Update watchers to match currently visible buffers
local function update_watchers()
    -- Get all visible buffers
    local visible_buffers = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_is_valid(buf) and does_buffer_have_backing_file(buf) then
            visible_buffers[buf] = true
        end
    end

    -- Stop watching buffers that are no longer visible
    for buf, _ in pairs(watchers) do
        if not visible_buffers[buf] or not vim.api.nvim_buf_is_valid(buf) then
            stop_watching_buffer(buf)
        end
    end

    -- Start watching newly visible buffers
    for buf, _ in pairs(visible_buffers) do
        start_watching_buffer(buf, M.options.silent)
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

    -- Set up fs_event watchers on buffer/window changes
    vim.api.nvim_create_autocmd({'BufEnter', 'WinEnter'}, {
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
