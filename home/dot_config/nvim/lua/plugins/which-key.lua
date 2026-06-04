-- which-key.nvim — leader 押下後にキーマップのヒントを表示する。
--
-- 既存マップはほぼ全てに日本語 desc が付いているため、導入するだけで一覧化される。
-- ここでは接頭辞ごとの group ラベルだけを登録して可読性を上げる。
-- LSP(LspAttach)や oil のバッファローカルマップは which-key が動的に拾うため、
-- ここでの register は不要(group ラベルのみ宣言)。

return {
  "folke/which-key.nvim",
  event = "VeryLazy",
  opts = {
    -- 既定プリセットのまま。panda テーマの配色を尊重し border のみ角丸に。
    win = {
      border = "rounded",
    },
  },
  config = function(_, opts)
    local wk = require("which-key")
    wk.setup(opts)

    -- 接頭辞グループのラベル(v3 の add() スペック配列形式)。
    -- ca は LSP code action 専用なので c(コピー)とは別グループに分離する。
    wk.add({
      { "<leader>c", group = "コピー", mode = "n" },
      { "<leader>ca", group = "コード操作", mode = "n" },
      { "<leader>s", group = "分割", mode = "n" },
      { "<leader>f", group = "検索", mode = "n" },
      { "<leader>r", group = "リネーム/LSP", mode = "n" },
      { "<leader>t", group = "トグル", mode = "n" },
    })
  end,
}
