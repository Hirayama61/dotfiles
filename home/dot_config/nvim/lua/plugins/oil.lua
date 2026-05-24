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

    ----------------------------------------------------------------------
    -- VSCode 風 git ステータス着色
    --
    -- 設計:
    --  * oil ディレクトリ単位で `git status --porcelain` を 1 回だけ叩き、
    --    パス(realpath 正規化)→ 状態のキャッシュを作る。highlight_filename は
    --    キャッシュ参照のみ(per-entry で git を叩かない)。
    --  * highlight_filename はレンダ中(同期)に呼ばれるのに対し User OilEnter は
    --    レンダ完了後に発火するため、「OilEnter でキャッシュ構築」だけだと初回レンダに
    --    間に合わない。そこで参照時にキャッシュが無ければその場で同期取得する遅延ロードに
    --    し、OilEnter ではキャッシュを破棄して次回再取得させる(oil 内の作成/削除/
    --    リネーム後も OilEnter を通るため、これで git 状態の変化に追従する)。
    ----------------------------------------------------------------------

    -- panda パレットに寄せた専用ハイライト。colorscheme.lua の panda 適用後や
    -- :colorscheme 切替で消えないよう、ColorScheme でも再適用する。
    --
    -- 隠しファイル(ドット始まり)の薄グレー表示は廃止する。見たいのは「git 管理
    -- されているか否か」であって、ドット始まりは見れば分かるため。oil は hidden 用に
    -- ベースグループ名へ "Hidden" を付けた変種(view.lua:770,831,837)を使うので、
    -- 各 *Hidden を対応する非 hidden グループへ link し直し、隠しファイルでも通常色で
    -- 表示する(show_hidden=true は維持し、色だけ通常へ戻す)。
    local oil_hidden_links = {
      OilFileHidden = "OilFile",
      OilDirHidden = "OilDir",
      OilLinkHidden = "OilLink",
      OilLinkTargetHidden = "OilLinkTarget",
      OilOrphanLinkHidden = "OilOrphanLink",
      OilOrphanLinkTargetHidden = "OilOrphanLinkTarget",
      OilSocketHidden = "OilSocket",
    }
    local function setup_git_hl()
      -- tracked の通常色より dim だが背景 #242526 上で読みやすい中間グレー。
      vim.api.nvim_set_hl(0, "OilGitUntracked", { fg = "#828a9a" })
      vim.api.nvim_set_hl(0, "OilGitModified", { fg = "#ffb86c" })  -- ゴールド
      vim.api.nvim_set_hl(0, "OilGitAdded", { fg = "#19f9d8" })     -- 緑(シアン寄り)
      -- deleted と conflict は同色(赤)。別グループに分けない。
      vim.api.nvim_set_hl(0, "OilGitDeleted", { fg = "#ff2c6d" })
      -- 隠しファイルを通常色へ戻す(薄グレー廃止)。
      for hidden, base in pairs(oil_hidden_links) do
        vim.api.nvim_set_hl(0, hidden, { link = base })
      end
    end
    setup_git_hl()
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = vim.api.nvim_create_augroup("OilGitHl", { clear = true }),
      callback = setup_git_hl,
    })

    -- git status の XY コードを内部カテゴリへ落とす。
    -- 戻り値: "untracked" | "modified" | "added" | "deleted" | nil
    local function classify(x, y)
      if x == "?" or x == "!" then return "untracked" end  -- ?? untracked / !! ignored
      -- どちらかの軸に U(unmerged)があれば conflict → deleted と同色扱い
      if x == "U" or y == "U" or (x == "A" and y == "A") or (x == "D" and y == "D") then
        return "deleted"
      end
      if x == "D" or y == "D" then return "deleted" end
      if x == "A" then return "added" end
      if x == "M" or x == "T" or x == "R" or x == "C"
        or y == "M" or y == "T" or y == "R" or y == "C" then
        return "modified"
      end
      return nil
    end

    local STATE_HL = {
      untracked = "OilGitUntracked",
      modified = "OilGitModified",
      added = "OilGitAdded",
      deleted = "OilGitDeleted",
    }

    -- oil ディレクトリ単位のキャッシュ。oil は基本 1 ディレクトリ表示なので
    -- oil_dir(canon 済)をキーに保持する。
    -- git_cache[oil_dir] = { files = { [abspath]=state }, ancestors = { [dir]=true } }
    -- または false(= git リポ外。再試行しないためのマーカー)。
    local git_cache = {}

    -- <oil_dir> 配下の git 状態を取得してキャッシュを構築する。git リポ外なら false。
    local function build_git_cache(oil_dir)
      local top = vim.system(
        { "git", "-C", oil_dir, "rev-parse", "--show-toplevel" },
        { text = true }
      ):wait()
      if top.code ~= 0 then return false end
      local root = canon(vim.trim(top.stdout))
      if not root then return false end

      -- -z で NUL 区切り(空白/日本語/特殊文字のパスを安全に)。
      -- --ignored で !! を取得(指定しないと ignored は出ない)。
      local st = vim.system({
        "git", "-C", oil_dir, "status", "--porcelain=v1", "-z",
        "--untracked-files=normal", "--ignored=matching",
      }, { text = true }):wait()
      if st.code ~= 0 then return false end

      local files = {}     -- [abspath] = state
      local ancestors = {} -- [dir] = true(配下に tracked の変更を含む dir)

      -- 変更ファイルの親 dir を root まで遡って ancestors に積む。
      local function mark_ancestors(abspath)
        local dir = vim.fs.dirname(abspath)
        while dir and #dir >= #root do
          ancestors[dir] = true
          if dir == root then break end
          local parent = vim.fs.dirname(dir)
          if parent == dir then break end
          dir = parent
        end
      end

      -- -z レコードを走査。各レコードは "XY <path>"。rename(R/C)時は
      -- 直後の NUL フィールドに旧パスが続くのでスキップする。
      local records = vim.split(st.stdout, "\0", { plain = true })
      local i = 1
      while i <= #records do
        local rec = records[i]
        if rec == "" then i = i + 1; goto continue end
        local x = rec:sub(1, 1)
        local y = rec:sub(2, 2)
        local rel = rec:sub(4)  -- "XY " の後ろ
        local state = classify(x, y)
        -- porcelain のパスは repo root 相対。末尾 / は untracked/ignored dir。
        local clean = rel:sub(-1) == "/" and rel:sub(1, -2) or rel
        local abspath = canon(root .. "/" .. clean) or (root .. "/" .. clean)
        if state then
          files[abspath] = state
          -- untracked/ignored 以外(= tracked の変更)は親 dir を modified 集約。
          if state ~= "untracked" then
            mark_ancestors(abspath)
          end
        end
        -- rename/copy は旧パスフィールドを 1 つ読み飛ばす。
        if x == "R" or x == "C" then i = i + 1 end
        i = i + 1
        ::continue::
      end

      git_cache[oil_dir] = { files = files, ancestors = ancestors }
      return true
    end

    -- highlight_filename: キャッシュ参照のみ。無ければ遅延構築。
    -- 戻り値はハイライトグループ名 or nil(nil なら oil 既定にフォールバック)。
    local function git_highlight(entry, is_hidden, is_link_target, is_link_orphan, bufnr)
      -- link target 側は過剰着色を避けて既定色に倒す。
      if is_link_target then return nil end
      local oil_dir = canon(oil.get_current_dir(bufnr))
      if not oil_dir then return nil end

      local c = git_cache[oil_dir]
      if c == nil then
        if not build_git_cache(oil_dir) then
          git_cache[oil_dir] = false  -- リポ外: 取得失敗を記録し再試行しない
          return nil
        end
        c = git_cache[oil_dir]
      end
      if not c then return nil end  -- false = git リポ外

      local name = entry.name
      local is_dir = entry.type == "directory"
      local abspath = canon(oil_dir .. "/" .. name) or (oil_dir .. "/" .. name)

      -- ファイル/シンボリックリンク本体: 自身の状態を直接参照。
      -- untracked なドットファイルは is_hidden(Comment)より git 状態を優先。
      local state = c.files[abspath]
      if state then
        return STATE_HL[state]
      end

      -- ディレクトリ集約: 配下に変更を含むなら modified 色。
      -- (丸ごと untracked/ignored な dir は上の c.files 参照で untracked が返る)
      if is_dir and c.ancestors[abspath] then
        return STATE_HL.modified
      end

      return nil
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
        highlight_filename = git_highlight,
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
        -- 次回レンダ時に git 状態を取り直す(oil 内の作成/削除/リネーム後も
        -- ここを通るため、これで変更に追従する)。
        local d = canon(oil.get_current_dir(args.data.buf))
        if d then git_cache[d] = nil end
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
