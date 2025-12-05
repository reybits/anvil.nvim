# Neovim Make Wrapper Plugin

Anvil.nvim is a Neovim plugin that runs external commands asynchronously.
It can execute builds either inside Neovim's integrated terminal or in an external tmux pane.
The plugin provides a smooth workflow for compiling, running, and monitoring build results without blocking the editor.


## Features:

- ~Detect TMUX environment and open a new TMUX window for make command.~
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
    log_to_qf = true,           -- Log output to quickfix list.
    open_qf_on_success = false, -- Open quickfix window on success.
    open_qf_on_error = true,    -- Open quickfix window on error.
    close_on_success = true,    -- Close the terminal/tmux window on successful completion.
    close_on_error = true,      -- Close the terminal/tmux window on error.

    on_exit = function(code, o)
        if code == 0 then
            vim.notify("Command completed successfully.", vim.log.levels.INFO)
            if o.open_qf_on_succes then
                vim.cmd("copen")
            end
        else
            vim.notify("Command failed with exit code: " .. code, vim.log.levels.ERROR)
            if o.open_qf_on_error then
                vim.cmd("copen")
            end
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
require('anvil').run("ls", { log_to_qf = true })
```

#### Equivalent to `:make rule` with opening.

```
require('anvil').run("make rule",
     on_error = function(code, 0)
         vim.notify("Result id: " .. code, vim.log.levels.INFO)
         if code ~= 0 then
             vim.cmd("copen")
         end
     end,
     log_to_qf = true })
```

## License

[MIT License](LICENSE)

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.
