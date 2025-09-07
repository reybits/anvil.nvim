# Neovim Make Wrapper Plugin

Anvil.nvim is a Neovim plugin that runs external commands asynchronously.
It can execute builds either inside Neovim's integrated terminal or in an external tmux pane.
The plugin provides a smooth workflow for compiling, running, and monitoring build results without blocking the editor.


## Features:

- Detect TMUX environment and open a new TMUX window for make command.
- Write output to a quickfix list for easy navigation.

## Installation

To install this plugin, you can use your favorite Neovim package manager. For example:

### [Lazy](https://github.com/folke/lazy.nvim)

```lua
{
    "reybits/anvil.nvim",
    lazy = true,
    keys = {
        { "<leader>r", "<cmd>Anvil make<cr>", desc = "Execute 'make'" },
    },
    cmd = {
        "Anvil",
    },
    opts = {
    },
}
```

### Configuring

The default configuration options are listed below:

```lua
opts = {
    log_to_qf = false, -- Log output to quickfix list.

    on_exit = function(code)
        if code == 0 then
            vim.notify("Command completed successfully.", vim.log.levels.INFO)
        else
            vim.notify("Command failed with exit code: " .. code, vim.log.levels.ERROR)
            vim.cmd("copen")
        end
    end,
}
```

## Usage

### Commands

The plugin provides two commands:

- `:Anvil` or `:Anvil make`— Executes default Makefile rule.

### Lua Functions

You can also use the plugin's Lua functions directly.

#### Equivalent to `:make`

```
require('anvil').run()
```

#### Equivalent to `:!ls`

```
require('anvil').run("ls", nil, { log_to_qf = true })
```

#### Equivalent to `:make rule` with opening.

```
require('anvil').run("make rule",
     function(code)
         vim.notify("Result id: " .. code, vim.log.levels.INFO)
         if code ~= 0 then
             vim.cmd("copen")
         end
     end,
     { log_to_qf = true })
```

## License

[MIT License](LICENSE)

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.
