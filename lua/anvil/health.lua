local M = {}

local function bool_s(b)
    if b then
        return "true"
    end
    return "false"
end

M.check = function()
    local anvil = require("anvil")
    -- vim.health.info("anvil: " .. vim.inspect(anvil))

    vim.health.start("configuration")
    vim.health.info("mode:                  '" .. anvil.options.mode .. "'")
    vim.health.info("is tmux enabled:       `" .. bool_s(anvil.shouldUseTmux(anvil.options)) .. "`")
    vim.health.info("notification title:    '" .. anvil.options.title .. "'")
    vim.health.info("log to qf:             `" .. bool_s(anvil.options.log_to_qf) .. "`")
    vim.health.info("open qfix on success:  `" .. bool_s(anvil.open_qf_on_success) .. "`")
    vim.health.info("open qfix on error:    `" .. bool_s(anvil.open_qf_on_error) .. "`")
    vim.health.info("close term on success: `" .. bool_s(anvil.close_on_success) .. "`")
    vim.health.info("close term on error:   `" .. bool_s(anvil.close_on_error) .. "`")

    vim.health.start("tmux server")
    local out = vim.fn.systemlist("tmux list-sessions")
    if vim.v.shell_error ~= 0 then
        if vim.v.shell_error == 1 then
            vim.health.info("Start tmux server to enable tmux integration.")
        elseif vim.v.shell_error == 127 then
            vim.health.info("Install tmux to enable tmux integration.")
        end
    else
        vim.health.info("tmux server running")
        vim.health.info("sessions: " .. vim.inspect(out))
    end

    vim.health.start("job state")
    if anvil.isRunning() then
        vim.health.warn("job is currently running")
    else
        vim.health.ok("no job running")
    end
end

return M
