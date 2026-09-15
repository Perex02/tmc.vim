-- lua/tmc/whichkey.lua
--
-- Registers the <leader>t group with which-key, so it shows as "tmc" with an
-- icon instead of "+3 keymaps". The individual entries need nothing from here:
-- which-key reads their labels from each mapping's `desc`, which plugin/tmc.vim
-- sets via nvim_set_keymap.

local M = {}

M.icon = "󰙨" -- nf-md-test_tube (U+F0668)

---@return table
local function spec()
  return {
    {
      "<leader>t",
      group = "tmc",
      icon = { icon = M.icon, color = "green" },
    },
  }
end

-- which-key's add() only queues the spec, so calling it early is cheap and the
-- ordering against its own setup does not matter.
local function try_add()
  local wk = package.loaded["which-key"]
  if not wk or type(wk.add) ~= "function" then
    return false
  end
  local ok = pcall(wk.add, spec())
  return ok
end

--- Register the group, now if which-key is loaded, otherwise once it is.
---
--- Deliberately does NOT `require("which-key")`: that would load it eagerly and
--- defeat the lazy-loading most configs set up. Instead it only uses which-key
--- if something else has already loaded it, and otherwise waits for startup to
--- settle. A no-op when which-key is not installed at all.
function M.register()
  if vim.g.tmc_disable_which_key == 1 then
    return
  end
  if try_add() then
    return
  end

  local group = vim.api.nvim_create_augroup("TmcWhichKey", { clear = true })
  -- VeryLazy is when lazy.nvim-based configs have loaded which-key; VimEnter
  -- covers everyone else. Whichever fires first wins, then both are torn down.
  vim.api.nvim_create_autocmd({ "User", "VimEnter" }, {
    group = group,
    pattern = "*",
    callback = function(ev)
      if ev.event == "User" and ev.match ~= "VeryLazy" then
        return
      end
      -- Give the triggering plugin a moment to finish loading which-key.
      vim.schedule(function()
        if try_add() then
          pcall(vim.api.nvim_del_augroup_by_id, group)
        end
      end)
    end,
  })
end

return M
