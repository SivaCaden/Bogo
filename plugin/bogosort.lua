if vim.g.loaded_bogosort then return end
vim.g.loaded_bogosort = true

vim.api.nvim_create_user_command("BogoSort", function()
  require("bogosort").start()
end, { desc = "Start BogoSort visualizer" })
