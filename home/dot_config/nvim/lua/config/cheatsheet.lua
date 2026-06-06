-- 操作チートシート — Neovim 組み込み操作 + このリポの実マップを一覧する自前フロート。
--
-- which-key は「leader 押下後に続くキー」を補助するが、組み込みの x/dd/ciw 等は
-- 拾わない。そこを埋めるため、カテゴリ別にキュレーションした静的データを描画する。
-- which-key が未インストールでも単体で動くようプラグイン非依存にする。
-- 起動マップ(<leader>?)は config/keymaps.lua 側が担い、ここは関数公開のみ。

local M = {}

-- カテゴリは { title, note?, items = { {key, desc}, ... } } の配列。
-- note はバッファローカル等の有効条件など、見出し脇に出す補足。
-- カテゴリ7/10〜12 は「このリポの実マップ」を実定義(keymaps/essentials/oil/lsp)から
-- 転記している。文言は各 lua ファイルの desc に合わせる(ズレたら追従すること)。
M.categories = {
  {
    title = "モード切替",
    items = {
      { "i / a", "カーソル前 / 後で挿入" },
      { "I / A", "行頭 / 行末で挿入" },
      { "o / O", "下 / 上に行を開いて挿入" },
      { "v / V", "文字 / 行 ビジュアル選択" },
      { "<C-v>", "矩形ビジュアル選択" },
      { ":", "コマンドラインモード" },
      { "<Esc>", "ノーマルモードへ戻る" },
    },
  },
  {
    title = "カーソル移動",
    items = {
      { "h j k l", "左 下 上 右" },
      { "w / b", "次 / 前の単語頭" },
      { "e / ge", "次 / 前の単語末" },
      { "0 / ^ / $", "行頭 / 最初の非空白 / 行末" },
      { "gg / G", "ファイル先頭 / 末尾" },
      { "{ / }", "前 / 次の段落" },
      { "<C-d> / <C-u>", "半画面 下 / 上スクロール" },
      { "f / t", "行内の文字へ / 手前まで" },
      { "; / ,", "f/t を 順 / 逆 に繰り返す" },
    },
  },
  {
    title = "編集",
    items = {
      { "x / r", "1文字削除 / 置換" },
      { "d / c / y", "削除 / 変更 / ヤンク(+モーション)" },
      { "p / P", "後 / 前にペースト" },
      { "dd / yy / cc", "1行 削除 / ヤンク / 変更" },
      { "J", "下の行を連結" },
      { "u / <C-r>", "アンドゥ / リドゥ" },
      { ".", "直前の変更を繰り返す" },
      { ">> / <<", "インデント 増 / 減" },
    },
  },
  {
    title = "テキストオブジェクト",
    note = "d/c/y/v と組み合わせて使う",
    items = {
      { "iw / aw", "単語 内 / 外(空白込み)" },
      { 'i" / a"', "ダブルクオート 内 / 外" },
      { "i( i{ i[", "各括弧の内側" },
      { "ip / ap", "段落 内 / 外" },
      { "it / at", "タグ 内 / 外" },
    },
  },
  {
    title = "検索・置換",
    items = {
      { "/ / ?", "前方 / 後方検索" },
      { "n / N", "次 / 前のマッチへ" },
      { "* / #", "カーソル下の単語を 前方 / 後方検索" },
      { ":%s/foo/bar/g", "全行で foo を bar に置換" },
      { ":noh", "検索ハイライト消去" },
    },
  },
  {
    title = "Visual モード操作",
    items = {
      { "v / V / <C-v>", "文字 / 行 / 矩形選択開始" },
      { "o", "選択範囲の反対端へ" },
      { "d / y / c", "選択を 削除 / ヤンク / 変更" },
      { "> / <", "選択をインデント 増 / 減(このリポは選択維持)" },
      { "J / K", "選択行を 下 / 上 に移動(このリポのマップ)" },
      { "gv", "直前の選択を復元" },
    },
  },
  {
    title = "ウィンドウ・タブ・バッファ",
    note = "上段=このリポの実マップ / 下段=Neovim 標準",
    items = {
      { "<C-h/j/k/l>", "左/下/上/右のウィンドウへ" },
      { "<leader>sv / sh", "縦分割 / 横分割" },
      { "<Tab> / <S-Tab>", "次 / 前のバッファ" },
      { "<C-w>q / <C-w>o", "ウィンドウ閉じる / 他を閉じる" },
      { "gt / gT", "次 / 前のタブ" },
      { ":bnext / :bprev", "次 / 前のバッファ(標準)" },
    },
  },
  {
    title = "折りたたみ・マーク・マクロ",
    items = {
      { "za / zR / zM", "折り トグル / 全展開 / 全畳み" },
      { "m{a-z}", "マークを設定" },
      { "`{a-z} / '{a-z}", "マーク位置 / マーク行へ" },
      { "q{a-z} … q", "マクロ記録 開始 … 終了" },
      { "@{a-z} / @@", "マクロ実行 / 直前のマクロ再実行" },
    },
  },
  {
    title = "レジスタ",
    items = {
      { '"{reg}', "次の y/d/p で使うレジスタ指定" },
      { '"+y / "+p', "システムクリップボードへ / から" },
      { '"0p', "直近ヤンク専用レジスタを貼付" },
      { ":reg", "レジスタ一覧を表示" },
    },
  },
  {
    title = "このリポの leader マップ",
    items = {
      { "<leader>w / q", "保存 / 終了(未保存時は確認)" },
      { "<leader>sv / sh", "縦分割 / 横分割" },
      { "<leader>o / O", "下 / 上に空行を挿入" },
      { "<leader>cp / cr / cf", "絶対 / 相対 / ファイル名 パスをコピー" },
      { "<leader>ff / fg", "ファイル検索 / 文字列検索(telescope)" },
      { "<leader>tm", "Markdown レンダリング表示トグル(md バッファ)" },
      { "<leader>?", "このチートシートを開く" },
      { "<C-a>", "全選択" },
      { "-", "親ディレクトリを開く(oil)" },
    },
  },
  {
    title = "LSP",
    note = "LSP attach 時のみ有効なバッファローカルマップ",
    items = {
      { "gd / gr / gi", "定義 / 参照一覧 / 実装へ" },
      { "K", "hover(ドキュメント表示)" },
      { "<leader>rn", "rename" },
      { "<leader>ca", "code action" },
      { "[d / ]d", "前 / 次の diagnostic へ" },
    },
  },
  {
    title = "oil(ファイラ)",
    note = "filetype=oil のバッファ内でのみ有効",
    items = {
      { "-", "親ディレクトリへ(ルートなら nvim 終了)" },
      { "<CR>", "エントリを開く" },
      { "<leader>cp / cr / cf", "選択エントリの 絶対 / 相対 / 名前 をコピー" },
      { "g.", "隠しファイル表示トグル" },
    },
  },
  {
    title = "GitHub(octo)",
    note = "gh CLI 前提。<localleader> 系は octo バッファ内のみ",
    items = {
      { "<leader>gp", "PR 一覧(:Octo pr list)" },
      { ":Octo pr diff", "PR の diff を確認" },
      { ":Octo pr checkout", "PR ブランチを checkout" },
      { ":Octo review", "レビュー開始 → 行コメント追加" },
      { ":Octo", "コマンド一覧 picker を開く" },
      { "<localleader>ca", "コメント追加(レビュー中)" },
      { "<localleader>cr", "コメント返信" },
    },
  },
}

local HL_TITLE = "CheatsheetTitle"
local HL_KEY = "CheatsheetKey"
local HL_DESC = "CheatsheetDesc"
local HL_NOTE = "CheatsheetNote"

local function ensure_highlights()
  -- 既定リンクでテーマ(panda)に追従させる。default=true でユーザー上書きを許容。
  vim.api.nvim_set_hl(0, HL_TITLE, { link = "Title", default = true })
  vim.api.nvim_set_hl(0, HL_KEY, { link = "Identifier", default = true })
  vim.api.nvim_set_hl(0, HL_DESC, { link = "Normal", default = true })
  vim.api.nvim_set_hl(0, HL_NOTE, { link = "Comment", default = true })
end

-- 1カテゴリを「行文字列 + ハイライト指示」のブロックに整形する。
-- key 列はブロック内で右揃え幅を揃え、key と desc を視覚的に分離する。
local function render_block(cat, inner_width)
  local lines = {}
  local marks = {} -- { row(0-based, ブロック内相対), col, end_col, hl }

  local function push(text, spans)
    local row = #lines
    lines[#lines + 1] = text
    for _, s in ipairs(spans or {}) do
      marks[#marks + 1] = { row = row, col = s[1], end_col = s[2], hl = s[3] }
    end
  end

  push(cat.title, { { 0, #cat.title, HL_TITLE } })
  if cat.note then
    local note = "  " .. cat.note
    push(note, { { 0, #note, HL_NOTE } })
  end

  local key_w = 0
  for _, it in ipairs(cat.items) do
    key_w = math.max(key_w, vim.fn.strdisplaywidth(it[1]))
  end
  key_w = math.min(key_w, math.max(8, math.floor(inner_width * 0.45)))

  for _, it in ipairs(cat.items) do
    local key, desc = it[1], it[2]
    local pad = key_w - vim.fn.strdisplaywidth(key)
    if pad < 0 then pad = 0 end
    local key_field = key .. string.rep(" ", pad)
    local prefix = "  "
    local line = prefix .. key_field .. "  " .. desc
    local key_start = #prefix
    local key_end = key_start + #key
    local desc_start = #prefix + #key_field + 2
    push(line, {
      { key_start, key_end, HL_KEY },
      { desc_start, #line, HL_DESC },
    })
  end

  return { lines = lines, marks = marks }
end

-- 端末幅から列数(1〜3)を決める。1列の目安幅 = 最長行 + 余白。
local function decide_columns(blocks, max_total_width)
  local col_w = 0
  for _, b in ipairs(blocks) do
    for _, l in ipairs(b.lines) do
      col_w = math.max(col_w, vim.fn.strdisplaywidth(l))
    end
  end
  col_w = col_w + 4 -- 列間ガター
  local fit = math.max(1, math.floor(max_total_width / col_w))
  return math.min(3, fit), col_w
end

-- 複数カテゴリブロックを columns 列のグリッドに段組みする。
-- 各列に縦積みし、列ごとの最大幅で右側をパディングして横に連結する。
local function layout(blocks, columns, col_inner_w)
  local per_col = math.ceil(#blocks / columns)
  local cols = {}
  for c = 1, columns do
    local col_lines = {}
    local col_marks = {}
    for i = (c - 1) * per_col + 1, math.min(c * per_col, #blocks) do
      local b = blocks[i]
      if #col_lines > 0 then col_lines[#col_lines + 1] = "" end
      local base = #col_lines
      for _, l in ipairs(b.lines) do col_lines[#col_lines + 1] = l end
      for _, m in ipairs(b.marks) do
        col_marks[#col_marks + 1] = { row = base + m.row, col = m.col, end_col = m.end_col, hl = m.hl }
      end
    end
    cols[c] = { lines = col_lines, marks = col_marks }
  end

  local height = 0
  for _, c in ipairs(cols) do height = math.max(height, #c.lines) end

  local out_lines = {}
  local out_marks = {}
  for row = 1, height do
    local parts = {}
    local offsets = {}
    local cursor = 0
    for c = 1, columns do
      offsets[c] = cursor
      local text = cols[c].lines[row] or ""
      local w = vim.fn.strdisplaywidth(text)
      local pad = col_inner_w - w
      if pad < 0 then pad = 0 end
      local field = text .. string.rep(" ", pad)
      parts[#parts + 1] = field
      cursor = cursor + #field
    end
    out_lines[row] = table.concat(parts)
    -- この行に対応する各列の marks をオフセット補正して回収
    for c = 1, columns do
      for _, m in ipairs(cols[c].marks) do
        if m.row == row - 1 then
          out_marks[#out_marks + 1] = {
            row = row - 1,
            col = offsets[c] + m.col,
            end_col = offsets[c] + m.end_col,
            hl = m.hl,
          }
        end
      end
    end
  end

  return out_lines, out_marks, col_inner_w * columns
end

function M.open()
  ensure_highlights()

  local screen_w = vim.o.columns
  local screen_h = vim.o.lines
  local max_total_width = math.max(40, math.floor(screen_w * 0.9))

  -- 列幅決定 → 各ブロックを内側幅で整形 → 段組み。
  local probe = {}
  for _, cat in ipairs(M.categories) do
    probe[#probe + 1] = render_block(cat, 40)
  end
  local columns, col_w = decide_columns(probe, max_total_width)

  local blocks = {}
  for _, cat in ipairs(M.categories) do
    blocks[#blocks + 1] = render_block(cat, col_w - 4)
  end

  local lines, marks, content_w = layout(blocks, columns, col_w)

  local width = math.min(content_w + 2, max_total_width)
  local height = math.min(#lines + 1, math.max(10, math.floor(screen_h * 0.85)))

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local ns = vim.api.nvim_create_namespace("cheatsheet")
  for _, m in ipairs(marks) do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, m.row, m.col, {
      end_col = m.end_col,
      hl_group = m.hl,
    })
  end

  vim.bo[buf].modifiable = false
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "cheatsheet"

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((screen_h - height) / 2),
    col = math.floor((screen_w - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " NeoVim Cheatsheet ",
    title_pos = "center",
  })
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = false

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  -- 専用バッファローカルのみ。グローバルマップ(<leader>? 等)は触らない。
  vim.keymap.set("n", "q", close, { buffer = buf, nowait = true, silent = true })
  vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true, silent = true })
end

return M
