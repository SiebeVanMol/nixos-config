local opt = vim.opt

opt.number = true
opt.relativenumber = true
opt.signcolumn = "yes"
opt.cursorline = true
opt.termguicolors = true
opt.mouse = "a"

-- Nothing here writes state that grows without bound. On a 4 GB home the undo
-- file per edited file is the quiet one: it doubles the size of everything you
-- touch and outlives the edit. Swap files are off for the same reason, and the
-- history file is capped rather than left at its default size.
opt.undofile = false
opt.swapfile = false
opt.backup = false
opt.writebackup = false
opt.shada = "!,'100,<50,s10,h"

opt.expandtab = true
opt.tabstop = 4
opt.softtabstop = 4
opt.shiftwidth = 4
opt.smartindent = true
opt.wrap = false

opt.splitright = true
opt.splitbelow = true
opt.ignorecase = true
opt.smartcase = true
opt.updatetime = 250
opt.scrolloff = 8

-- `rg` when it is there (the bootstrap script puts it in ~/.local/bin), plain
-- grep otherwise, so <leader>fg works on a machine nobody has prepared.
if vim.fn.executable("rg") == 1 then
  opt.grepprg = "rg --vimgrep --smart-case --no-heading"
  opt.grepformat = "%f:%l:%c:%m"
end

vim.diagnostic.config({
  virtual_text = true,
  severity_sort = true,
  float = {border = "rounded"},
})

vim.lsp.inlay_hint.enable(true)
