-- LazyVim's own keymap set is the point of using it, so this file only adds
-- what it does not carry.
local map = vim.keymap.set

-- 42's norm checker, once norminette is installed on the machine.
map("n", "<leader>n", "<cmd>!norminette %<cr>", {desc = "norminette", silent = true})
