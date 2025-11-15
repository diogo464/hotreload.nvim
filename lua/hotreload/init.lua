---@class Options
---@field interval integer Check interval in milliseconds
---@field silent boolean Suppress reload notifications (default: true)

---@class Module
---@field options Options
---@field timer unknown
local M = {}

---@type Options
local DEFAULT_OPTIONS = {
    interval = 500,
    silent = true,
}

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
    if not does_buffer_have_backing_file(buf) then
        return
    end

    if not is_buffer_modified(buf) then
        if silent then
            vim.cmd('silent! checktime')
        else
            vim.cmd('checktime')
        end
    end
end

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

    local timer = vim.uv.new_timer()
    vim.uv.timer_start(timer, M.options.interval, M.options.interval, vim.schedule_wrap(function()
        reload_visible_buffers(M.options.silent)
    end))

    vim.api.nvim_create_autocmd('BufEnter', {
        callback = function()
            local buf = vim.api.nvim_get_current_buf()
            reload_buffer_if_unmodified(buf, M.options.silent)
        end
    })

    vim.api.nvim_create_autocmd('WinEnter', {
        callback = function()
            local buf = vim.api.nvim_get_current_buf()
            reload_buffer_if_unmodified(buf, M.options.silent)
        end
    })
end

return M
