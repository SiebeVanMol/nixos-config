local map = vim.keymap.set

map("n", "<leader>w", "<cmd>write<cr>", {desc = "Write"})
map("n", "<leader>q", "<cmd>quit<cr>", {desc = "Quit"})
map("n", "<leader>h", "<cmd>nohlsearch<cr>", {desc = "Clear search highlight"})

-- File search without a fuzzy-finder plugin.
--
-- telescope/fzf-lua would be the obvious answer and would cost a plugin plus
-- `rg`; the picker Neovim already has does the same job at this scale, and the
-- school machine is short of space. `vim.ui.select` is also what a future
-- telescope install would hook into, so this mapping keeps working unchanged.
map("n", "<leader>ff", function()
  local files = vim.fs.find(function(name)
    return name:sub(1, 1) ~= "."
  end, {path = vim.uv.cwd(), type = "file", limit = 5000})

  if #files == 0 then
    vim.notify("no files under " .. vim.uv.cwd(), vim.log.levels.WARN)
    return
  end

  table.sort(files)
  vim.ui.select(files, {prompt = "file"}, function(choice)
    if choice then
      vim.cmd.edit(vim.fn.fnameescape(choice))
    end
  end)
end, {desc = "Find file"})

map("n", "<leader>fg", function()
  local pattern = vim.fn.input("grep > ")
  if pattern == "" then
    return
  end
  vim.cmd("silent grep! " .. vim.fn.escape(pattern, "\\\" "))
  vim.cmd("copen")
end, {desc = "Grep project"})

map("n", "<leader>fb", "<cmd>ls<cr>", {desc = "Buffers"})
map("n", "<leader>fc", "<cmd>close<cr>", {desc = "Close split"})

-- LSP: the keys Neovim 0.11+ does not map by itself.
map("n", "gd", vim.lsp.buf.definition, {desc = "Definition"})
map("n", "gD", vim.lsp.buf.declaration, {desc = "Declaration"})
map("n", "K", vim.lsp.buf.hover, {desc = "Hover"})
map("n", "<leader>rn", vim.lsp.buf.rename, {desc = "Rename"})
map("n", "<leader>ca", vim.lsp.buf.code_action, {desc = "Code action"})
map("n", "<leader>d", vim.diagnostic.open_float, {desc = "Diagnostic"})

map("n", "]d", function()
  vim.diagnostic.jump({count = 1})
end, {desc = "Next diagnostic"})
map("n", "[d", function()
  vim.diagnostic.jump({count = -1})
end, {desc = "Previous diagnostic"})

-- 42's norm checker, once norminette is installed on the machine.
map("n", "<leader>n", "<cmd>!norminette %<cr>", {desc = "norminette", silent = true})
