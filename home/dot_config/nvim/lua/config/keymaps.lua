-- Leader キー(プラグイン読み込み前に設定する必要あり)
vim.g.mapleader = " "
vim.g.maplocalleader = " "

local keymap = vim.keymap.set

-- 基本操作
keymap("n", "<leader>w", "<cmd>w<cr>", { desc = "保存" })
keymap("n", "<leader>q", "<cmd>confirm q<cr>", { desc = "終了(未保存時は確認)" })

-- ウィンドウ移動
keymap("n", "<C-h>", "<C-w>h", { desc = "左のウィンドウへ" })
keymap("n", "<C-j>", "<C-w>j", { desc = "下のウィンドウへ" })
keymap("n", "<C-k>", "<C-w>k", { desc = "上のウィンドウへ" })
keymap("n", "<C-l>", "<C-w>l", { desc = "右のウィンドウへ" })

-- ウィンドウ分割
keymap("n", "<leader>sv", "<cmd>vsplit<cr>", { desc = "縦分割" })
keymap("n", "<leader>sh", "<cmd>split<cr>", { desc = "横分割" })

-- バッファ移動
keymap("n", "<Tab>", "<cmd>bnext<cr>", { desc = "次のバッファ" })
keymap("n", "<S-Tab>", "<cmd>bprevious<cr>", { desc = "前のバッファ" })

-- Visual モードで行移動
keymap("v", "J", ":m '>+1<cr>gv=gv", { desc = "行を下に移動" })
keymap("v", "K", ":m '<-2<cr>gv=gv", { desc = "行を上に移動" })

-- Visual モードでインデント維持
keymap("v", "<", "<gv", { desc = "インデント減" })
keymap("v", ">", ">gv", { desc = "インデント増" })

-- 検索ハイライトクリア
keymap("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "ハイライトクリア" })

-- ファイルパスをクリップボードにコピー
keymap("n", "<leader>cp", function()
  local path = vim.fn.expand("%:p")
  vim.fn.setreg("+", path)
  vim.notify("Copied: " .. path)
end, { desc = "絶対パスをコピー" })

keymap("n", "<leader>cr", function()
  local path = vim.fn.expand("%")
  vim.fn.setreg("+", path)
  vim.notify("Copied: " .. path)
end, { desc = "相対パスをコピー" })

keymap("n", "<leader>cf", function()
  local name = vim.fn.expand("%:t")
  vim.fn.setreg("+", name)
  vim.notify("Copied: " .. name)
end, { desc = "ファイル名をコピー" })

-- 空行の挿入(insert に入らない)
keymap("n", "<leader>o", "o<Esc>", { desc = "下に空行を挿入" })
keymap("n", "<leader>O", "O<Esc>", { desc = "上に空行を挿入" })

-- 全選択
keymap("n", "<C-a>", "ggVG", { desc = "全選択" })

-- ヘルプ
keymap("n", "<leader>?", function() require("config.cheatsheet").open() end, { desc = "ヘルプ: 操作チートシート" })
