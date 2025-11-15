# hotreload.nvim

A Neovim plugin that automatically runs `:checktime` on visible and active buffers when they change on disk.
This is quite useful when working with cli based AI agents like claude code or aider since you can see the files changing in real time.

## Features

- Periodically checks visible buffers for file changes (default: every 500ms)
- Only reloads buffers that are currently visible in a window
- Runs `:checktime` when a buffer becomes visible or gets focus
- Only checks unmodified buffers to avoid conflicts with your work

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    'lanej/hotreload.nvim',
    opts = {
        -- Check interval in milliseconds (default: 500)
        interval = 500,
    }
}
```
