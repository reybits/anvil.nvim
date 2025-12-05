-------------------------------------------------------------------------------
-- A Neovim plugin to run Makefile targets or shell commands asynchronously.
--
-- Author: Andrey Ugolnik
-- License: MIT
-- GitHub: https://github.com/reybits/
--

local M = {}

---@public
---@class Options
---@field mode? string                          Mode to run the command in: "auto" or "term".
---@field log_to_qf? boolean                    Whether to log output to quickfix list.
---@field open_qf_on_success? boolean           Whether to open quickfix list on successful completion.
---@field open_qf_on_error? boolean             Whether to open quickfix list on error.
---@field close_on_success? boolean             Whether to close the terminal window on successful completion.
---@field close_on_error? boolean               Whether to close the terminal window on error.
---@field title? string                         Title for the notification.
---@field on_exit? fun(code:number, o?:Options) Optional callback function.
M.options = {
    mode = "term", -- "auto" | "term"
    log_to_qf = false,
    open_qf_on_success = false,
    open_qf_on_error = false,
    close_on_success = false,
    close_on_error = false,
    title = "Command",
    on_exit = function(code, o)
        local title = o.title or "Anvil"
        if code == 0 then
            vim.notify(title .. " completed successfully.", vim.log.levels.INFO)
            if o.open_qf_on_success then
                vim.cmd("copen")
            end
        else
            vim.notify(title .. " failed with exit code: " .. code, vim.log.levels.ERROR)
            if o.open_qf_on_error then
                vim.cmd("copen")
            end
        end
    end,
}

--------------------------------------------------------------------------------

---@private
---@type boolean Indicates whether a job is currently running.
local isRunning = false

---
function M.isRunning()
    return isRunning
end

---@private
---@class JobOptions
---@field pidfile string      Temporary file to write the exit code to.
---@field logfile string      Output file for logging.
---@field term_win number|nil Terminal window ID.
---@field term_buf number|nil Terminal buffer ID.
local JobOptions = {
    pidfile = "",
    logfile = "",
    term_win = nil,
    term_buf = nil,
}

---Wait for the job to finish by polling the temporary file for the exit code.
---@private
---@param job_opts JobOptions Options for waiting for the job.
---@param options Options     Plugin options.
local function wait_for_job(job_opts, options)
    local timer = vim.uv.new_timer()
    if timer ~= nil then
        local function check_job_finish()
            local f = io.open(job_opts.pidfile, "r")
            if f then
                -- read the exit code from the temporary file
                local code = tonumber(f:read("*a")) or 0
                f:close()

                -- remove the temporary file
                os.remove(job_opts.pidfile)

                -- stop and close the timer
                timer:stop()
                timer:close()

                -- forward the output to the quickfix list if needed
                if options.log_to_qf then
                    local o = io.open(job_opts.logfile, "r")
                    if o then
                        local lines = {}
                        for line in o:lines() do
                            table.insert(lines, line)
                        end
                        o:close()
                        os.remove(job_opts.logfile)

                        vim.fn.setqflist({}, "r", { title = "Make Output", lines = lines })
                    end
                end

                -- close the terminal window if the job succeeded
                if job_opts.term_win ~= nil and job_opts.term_buf ~= nil then
                    if
                        (code == 0 and options.close_on_success)
                        or (code ~= 0 and options.close_on_error)
                    then
                        if vim.bo[job_opts.term_buf].buftype == "terminal" then
                            vim.api.nvim_win_close(job_opts.term_win, true)
                            vim.api.nvim_buf_delete(job_opts.term_buf, { force = true })
                        end
                    end
                end

                -- notify the user of the exit code
                options.on_exit(code, options)

                isRunning = false
            end
        end

        timer:start(500, 500, vim.schedule_wrap(check_job_finish))
    end
end

--------------------------------------------------------------------------------

M.shouldUseTmux = function(options)
    if options.mode == "auto" then
        return os.getenv("TMUX") ~= nil
    elseif options.mode == "term" then
        return false
    end

    return false
end

--------------------------------------------------------------------------------

local function runInTmux(cmd, job_opts)
    -- FIXME: Investigate how to grab user command exit code (not tee or shell) reliably in tmux pane.
    local tmux_cmd = string.format(
        "tmux split-window -v -l 30%% \"sh -c '{ %s 2>&1; echo $? >&3; } 3>%s | tee %s'\"; tmux select-pane -U",
        cmd,
        job_opts.pidfile,
        job_opts.logfile
    )
    -- vim.notify("CMD: " .. tmux_cmd, vim.log.levels.INFO)

    vim.fn.jobstart(tmux_cmd, { shell = true })
end

local function runInTerm(cmd, job_opts)
    local prev_win = vim.api.nvim_get_current_win()

    local term_cmd = string.format(
        "terminal sh -c '{ %s 2>&1; echo $? >&3; } 3>%s | tee %s'",
        cmd,
        job_opts.pidfile,
        job_opts.logfile
    )
    -- vim.notify("CMD: " .. term_cmd, vim.log.levels.INFO)

    -- make split for terminal window and run terminal command
    vim.cmd("split | " .. term_cmd)
    job_opts.term_buf = vim.api.nvim_get_current_buf()
    job_opts.term_win = vim.api.nvim_get_current_win()

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

--------------------------------------------------------------------------------

---Run a Makefile rule asynchronously.
---@param cmd string|nil   The command or Make target to run. If nil, defaults to "make".
---@param options? Options Optional table of options, e.g. { log_to_qf = true, mode = "auto", on_exit = funciton(code:number,title?:string) }.
M.run = function(cmd, options)
    -- default command is "make"
    cmd = cmd or "make"
    -- vim.notify("'" .. vim.inspect(cmd) .. "'", vim.log.levels.INFO)
    -- vim.print(vim.inspect(cmd))

    options = vim.tbl_deep_extend("force", {}, M.options, options or {})
    -- vim.notify("'" .. vim.inspect(options) .. "'", vim.log.levels.INFO)
    -- vim.print(vim.inspect(options))

    if isRunning then
        vim.notify("A command is already running.", vim.log.levels.WARN)
        return
    end

    local use_tmux = M.shouldUseTmux(options)

    local job_opts = {
        -- pidfile = vim.env.HOME .. "/out.pid",
        -- logfile = vim.env.HOME .. "/out.log",
        pidfile = vim.fn.tempname() .. ".pid",
        logfile = vim.fn.tempname() .. ".log",
    }

    os.remove(job_opts.pidfile)
    if options.log_to_qf then
        os.remove(job_opts.logfile)
    end

    isRunning = true

    if use_tmux then
        runInTmux(cmd, job_opts)
    else
        runInTerm(cmd, job_opts)
    end

    -- wait for the command to finish
    wait_for_job(job_opts, options)
end

--------------------------------------------------------------------------------

--- Setup the plugin.
function M.setup(options)
    M.options = vim.tbl_deep_extend("force", M.options, options or {})

    -- bind commands to our lua functions
    vim.api.nvim_create_user_command("Anvil", function(opts)
        -- treat all arguments as a command and its arguments
        local cmd = nil
        if #opts.fargs ~= 0 then
            cmd = table.concat(opts.fargs, " ")
        end

        M.run(cmd, M.options)
    end, { nargs = "*", desc = "Run a command" })
end

return M
