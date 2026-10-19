-- Options LazyVim does not already choose for us.
--
-- LazyVim sets its own defaults (numbers, sign column, termguicolors, per-filetype
-- indents), so this file holds only the differences, and all of them come from
-- the school machine: 4 GB of home.
--
-- LazyVim turns undo files on. That is one file per edited file, doubling the
-- size of everything touched and outliving the edit - on this home that is the
-- difference between room for projects and none. The history file is capped for
-- the same reason.
vim.opt.undofile = false
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.shada = "!,'100,<50,s10,h"

vim.opt.mouse = "a"
vim.opt.scrolloff = 8
vim.opt.clipboard = "unnamedplus"
