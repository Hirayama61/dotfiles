-- バッファ型ファイラー(Oil.nvim)

return {
  "stevearc/oil.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  lazy = false,    -- 起動時に load して `-` keymap を即時有効化
  init = function()
    -- 標準 Netrw を無効化(oil と `-` 等の binding が衝突するため)
    vim.g.loaded_netrw = 1
    vim.g.loaded_netrwPlugin = 1
  end,
  config = function()
    local oil = require("oil")

    -- git 管理外のときの「プロジェクトルート」判定に使う起動時 cwd
    local start_cwd = vim.fn.getcwd()
    vim.api.nvim_create_autocmd("VimEnter", {
      callback = function() start_cwd = vim.fn.getcwd() end,
    })

    local uv = vim.uv or vim.loop
    local function canon(p)
      if not p then return nil end
      return uv.fs_realpath(p) or vim.fs.normalize(p)
    end

    local function at_root()
      local dir = canon(oil.get_current_dir(0))
      if not dir then return false end
      local gitdir = vim.fs.find(".git", { path = dir, upward = true })[1]
      local root = canon(gitdir and vim.fs.dirname(gitdir) or start_cwd)
      return dir == root
    end

    -- open_preview は entry 不在時に notify(ERROR) する仕様。カレント窓が
    -- oil を表示し、カーソル下に entry がある時だけ呼ぶ。窓は再利用される。
    local function show_preview()
      if vim.bo.filetype ~= "oil" then return end
      if not oil.get_cursor_entry() then return end
      oil.open_preview()
    end

    oil.setup({
      view_options = {
        show_hidden = true,
      },
      -- oil は `-` をバッファローカルに張る(既定 actions.parent)。グローバル
      -- keymap だと oil バッファ内で上書きされるため keymaps 経由で差し替える。
      keymaps = {
        ["-"] = {
          mode = "n",
          desc = "親ディレクトリを開く(プロジェクトルートなら nvim 終了)",
          callback = function()
            if at_root() then
              vim.cmd("qa")
            else
              oil.open()
            end
          end,
        },
      },
    })

    local grp = vim.api.nvim_create_augroup("OilDefaultPreview", { clear = true })
    vim.api.nvim_create_autocmd("User", {
      group = grp,
      pattern = "OilEnter",
      callback = function(args)
        if vim.api.nvim_get_current_buf() ~= args.data.buf then return end
        vim.schedule(show_preview)
      end,
    })
    vim.api.nvim_create_autocmd("CursorMoved", {
      group = grp,
      callback = show_preview,
    })
  end,
}
