-------------------------------------------------------------------------------
-- A Neovim plugin to run Makefile targets or shell commands asynchronously.
--
-- Author: Andrey Ugolnik
-- License: MIT
-- GitHub: https://github.com/reybits/
--

local M = {}

---@class MakerunOpts
---@field pidfile string                Temporary file to write the exit code to
---@field logfile string                Output file for logging
---@field log_to_qf boolean             Whether to log output to quickfix list
---@field on_exit fun(code:number)|nil  Optional callback function
local MakerunOpts = {
    pidfile = "",
    logfile = "",
    log_to_qf = false,
    on_exit = nil,
}

---@private
---@type boolean Indicates whether a job is currently running.
local isRunning = false

---Wait for the job to finish by polling the temporary file for the exit code.
---@param opts MakerunOpts Options for waiting for the job
local function wait_for_job(opts)
    local timer = vim.uv.new_timer()
    if timer ~= nil then
        timer:start(
            500,
            500,
            vim.schedule_wrap(function()
                local f = io.open(opts.pidfile, "r")
                if f then
                    -- Read the exit code from the temporary file.
                    local code = tonumber(f:read("*a")) or 0
                    f:close()

                    -- Remove the temporary file.
                    os.remove(opts.pidfile)

                    -- Stop and close the timer.
                    timer:stop()
                    timer:close()

                    -- Forward the output to the quickfix list if needed.
                    if opts.log_to_qf then
                        local o = io.open(opts.logfile, "r")
                        if o then
                            local lines = {}
                            for line in o:lines() do
                                table.insert(lines, line)
                            end
                            o:close()
                            os.remove(opts.logfile)

                            vim.fn.setqflist({}, "r", { title = "Make Output", lines = lines })
                        end
                    end

                    -- Notify the user of the exit code.
                    opts.on_exit(code)

                    isRunning = false
                end
            end)
        )
    end
end

--------------------------------------------------------------------------------

---Make a terminal command string.
---@param cmd string        Command to run
---@param logfile string    Output file for logging
---@param pidfile string    Temporary file to write exit code to
---@param log_to_qf boolean Whether to log output to quickfix list
---@return string
local function makeTmuxCommand(cmd, logfile, pidfile, log_to_qf)
    if log_to_qf == false then
        return string.format(
            "tmux split-window -v -l 30%% '%s; echo $? > %s || exec $SHELL'; tmux select-pane -U",
            cmd,
            pidfile
        )
    end

    return string.format(
        "tmux split-window -v -l 30%% '(%s 2>&1 | tee %s); echo $? > %s || exec $SHELL'; tmux select-pane -U",
        cmd,
        logfile,
        pidfile
    )
end

---Make a terminal command string.
---@param cmd string        Command to run
---@param logfile string    Output file for logging
---@param pidfile string    Temporary file to write exit code to
---@param log_to_qf boolean Whether to log output to quickfix list
---@return string
local function makeTermCommand(cmd, logfile, pidfile, log_to_qf)
    if log_to_qf == false then
        return string.format("terminal %s; echo $? > %s", cmd, pidfile)
    end

    return string.format("terminal (%s 2>&1 | tee %s); echo $? > %s", cmd, logfile, pidfile)
end

--------------------------------------------------------------------------------

---Run a Makefile rule asynchronously.
---@param cmd string|nil               The command or Make target to run. If nil, defaults to "make".
---@param on_exit fun(code:number)|nil Optional callback function called when the command exits. Receives the exit code as an argument.
---@param flags table|nil              Optional table of flags, e.g. { qf = true, open = false }.
M.run = function(cmd, on_exit, flags)
    -- Default command is "make"
    cmd = cmd or "make"

    on_exit = on_exit
        or function(code)
            if code == 0 then
                vim.notify("Command completed successfully.", vim.log.levels.INFO)
            else
                vim.notify("Command failed with exit code: " .. code, vim.log.levels.ERROR)
                vim.cmd("copen")
            end
        end

    -- vim.notify("'" .. vim.inspect(cmd) .. "'", vim.log.levels.INFO)
    flags = flags or {}
    -- vim.print(vim.inspect(cmd))
    -- vim.print(vim.inspect(flags))

    if isRunning then
        vim.notify("A command is already running.", vim.log.levels.WARN)
        return
    end

    isRunning = true

    local pidfile = vim.fn.tempname() .. ".ret"
    os.remove(pidfile)

    local logfile = vim.fn.tempname() .. ".log"
    if flags.log_to_qf then
        os.remove(logfile)
    end

    if os.getenv("TMUX") then
        local tmux_cmd = makeTmuxCommand(cmd, logfile, pidfile, flags.log_to_qf)
        -- vim.notify("CMD: " .. tmux_cmd, vim.log.levels.INFO)
        vim.fn.jobstart(tmux_cmd, { shell = true })
    else
        vim.api.nvim_create_autocmd("TermClose", {
            group = vim.api.nvim_create_augroup("scratch_close_term_buffer", { clear = true }),
            callback = function()
                for _, win in ipairs(vim.api.nvim_list_wins()) do
                    local buf = vim.api.nvim_win_get_buf(win)
                    if vim.bo[buf].buftype == "terminal" then
                        vim.api.nvim_win_close(win, true)
                        vim.api.nvim_buf_delete(buf, { force = true })
                        return
                    end
                end
            end,
        })

        local prev_win = vim.api.nvim_get_current_win()

        -- make split for terminal window and run terminal command
        local term_cmd = makeTermCommand(cmd, logfile, pidfile, flags.log_to_qf)
        -- vim.notify("CMD: " .. term_cmd, vim.log.levels.INFO)
        vim.cmd("split | " .. term_cmd)

        -- scroll to the bottom
        vim.cmd("normal G")

        -- move terminal window to the bottom
        vim.cmd("wincmd J")

        -- reseize terminal window to fixed height
        local height = math.floor(0.3 * vim.o.lines)
        vim.cmd("resize " .. height)

        -- return focus to previous window
        if vim.api.nvim_win_is_valid(prev_win) then
            vim.api.nvim_set_current_win(prev_win)
        end
    end

    -- Wait for the command to finish
    wait_for_job({
        pidfile = pidfile,
        logfile = logfile,
        log_to_qf = flags.log_to_qf,
        on_exit = on_exit,
    })
end

--- Setup the plugin
function M.setup(config)
    config = config or {}

    -- Bind commands to our lua functions
    vim.api.nvim_create_user_command("Anvil", function(opts)
        local targets = {}
        local flags = {
            log_to_qf = config.log_to_qf,
        }

        -- Parse arguments into targets and flags.
        for _, arg in ipairs(opts.fargs) do
            if arg:match("=") then
                local k, v = arg:match("^([^=]+)=([^=]+)$")
                if k and v then
                    flags[k] = v
                end
            else
                table.insert(targets, arg)
            end
        end

        local cmd = nil
        if #targets ~= 0 then
            cmd = table.concat(targets, " ")
        end

        M.run(cmd, config.on_exit, flags)
    end, { nargs = "*", desc = "Run a command" })
end

return M
