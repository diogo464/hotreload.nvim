# hotreload.nvim

A Neovim plugin that automatically runs `:checktime` on visible buffers when they change on disk using efficient file system event watchers.
This is quite useful when working with cli based AI agents like claude code or aider since you can see the files changing in real time.

## Features

- Uses native file system event watchers (inotify/FSEvents/etc.) for instant, efficient reloading
- Only watches buffers that are currently visible in a window
- Automatically adds/removes watchers as buffers become visible/hidden
- Runs `:checktime` when a buffer becomes visible or gets focus
- Only checks unmodified buffers to avoid conflicts with your work
- Silent by default - no notifications when files are reloaded
- Optional polling fallback for compatibility

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    'lanej/hotreload.nvim',
    opts = {}  -- Uses fs_event watchers by default
}
```

## Configuration Options

- `interval` (number|nil): Optional polling interval in milliseconds. Default: `nil` (disabled)
  - When `nil`, uses efficient fs_event watchers (recommended)
  - Set to a number (e.g., `500`) to enable polling fallback
  - Polling uses more CPU but may be more compatible in some environments
- `silent` (boolean): Suppress file reload notifications. Default: `true`
  - Set to `false` if you want to see notifications when files are reloaded

### Example: Enable polling (legacy mode)

If you experience issues with fs_event watchers, you can enable polling:

```lua
{
    'lanej/hotreload.nvim',
    opts = {
        interval = 500,  -- Poll every 500ms
        silent = true,
    }
}
```

## How It Works

The plugin uses Neovim's `vim.uv.new_fs_event()` API to watch visible buffer files for changes:

1. When you open or switch to a buffer, the plugin creates a file system watcher for that file
2. The watcher uses the OS's native notification system (inotify on Linux, FSEvents on macOS, etc.)
3. When the file changes on disk, the watcher immediately triggers `:checktime` to reload the buffer
4. When you close or hide a buffer, the watcher is automatically removed to free resources
5. Only unmodified buffers are reloaded to avoid overwriting your work

This approach is much more efficient than polling because:
- Zero CPU usage when files aren't changing
- Instant response to file changes (no polling delay)
- Scales to many open buffers without performance impact

## Platform Notes

**Linux users**: If you have many files open, you may need to increase the inotify watch limit:

```bash
# Temporarily increase limit
sudo sysctl fs.inotify.max_user_watches=524288

# Permanently increase limit
echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```
