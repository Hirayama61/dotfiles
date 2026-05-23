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

    -- 選択エントリの絶対パスを組み立てる(ディレクトリは末尾に `/` を付ける)。
    -- oil バッファ内では % が oil:// URL になるため、API でパスを構築する。
    local function entry_abs_path()
      local entry = oil.get_cursor_entry()
      local dir = oil.get_current_dir()
      if not entry or not dir then return nil end
      local name = entry.name
      if entry.type == "directory" then name = name .. "/" end
      return dir .. name
    end

    -- 既存 <leader>c*(keymaps.lua)と同じく `+`(システムクリップボード)へ
    -- 入れて、何をコピーしたか notify する。
    local function copy_to_clipboard(value)
      vim.fn.setreg("+", value)
      vim.notify("Copied: " .. value)
    end

    oil.setup({
      view_options = {
        show_hidden = true,
      },
      -- oil は `-` をバッファローカルに張る(既定 actions.parent)。グローバル
      -- keymap だと oil バッファ内で上書きされるため keymaps 経由で差し替える。
      -- <leader>c* も同様にバッファローカルで張り、通常バッファ側(keymaps.lua)と
      -- 操作系を揃える。
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
        ["<leader>cp"] = {
          mode = "n",
          desc = "選択エントリの絶対パスをコピー",
          callback = function()
            local abs = entry_abs_path()
            if not abs then return end
            -- realpath で正規化(取得失敗時はそのまま)
            copy_to_clipboard(canon(abs) or abs)
          end,
        },
        ["<leader>cr"] = {
          mode = "n",
          desc = "選択エントリの相対パスをコピー(cwd 基準)",
          callback = function()
            local abs = entry_abs_path()
            if not abs then return end
            copy_to_clipboard(vim.fn.fnamemodify(abs, ":."))
          end,
        },
        ["<leader>cf"] = {
          mode = "n",
          desc = "選択エントリのファイル名をコピー",
          callback = function()
            local entry = oil.get_cursor_entry()
            if not entry then return end
            copy_to_clipboard(entry.name)
          end,
        },
      },
    })

    -- 通常バッファからも `-` で oil を開けるようグローバルに張る。oil バッファ
    -- 内では setup.keymaps 側(バッファローカル)が優先され、ルートでの nvim
    -- 終了挙動はそのまま維持される。
    local function dash()
      if vim.bo.filetype == "oil" then
        if at_root() then
          vim.cmd("qa")
        else
          oil.open()
        end
      else
        oil.open()
      end
    end
    vim.keymap.set("n", "-", dash, { desc = "親ディレクトリを開く(oil)" })

    -- oil は preview_win.update_on_cursor_moved(既定 true)で「プレビュー窓が既に
    -- 在る時」のカーソル追従更新を内蔵する。最初の1枚は自前で開く必要があるため、
    -- OilEnter で窓が無い時だけ1回 open_preview する。以降の追従は oil 内蔵に委ね、
    -- 自前 CursorMoved は張らない(二重発火による preview 窓の二重化を防ぐ)。
    local oil_util = require("oil.util")
    local grp = vim.api.nvim_create_augroup("OilDefaultPreview", { clear = true })
    vim.api.nvim_create_autocmd("User", {
      group = grp,
      pattern = "OilEnter",
      callback = function(args)
        if vim.api.nvim_get_current_buf() ~= args.data.buf then return end
        vim.schedule(function()
          if vim.bo.filetype ~= "oil" then return end
          if oil_util.get_preview_win() then return end
          if not oil.get_cursor_entry() then return end
          oil.open_preview()
        end)
      end,
    })
  end,
}
