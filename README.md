# hotreload.nvim

A Neovim plugin that automatically runs `:checktime` on visible buffers when they change on disk.

## Features

- Periodically checks for file changes (default: every 500ms)
- Runs `:checktime` when a buffer becomes visible or gets focus
- Only checks unmodified buffers to avoid conflicts with your work

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    'diogo464/hotreload.nvim',
    opts = {
        -- Check interval in milliseconds (default: 500)
        interval = 500,
    }
}
```
