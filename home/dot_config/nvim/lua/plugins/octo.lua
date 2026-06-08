-- octo.nvim — GitHub の Issue/PR を nvim 内で操作する。
--
-- gitsigns(ローカル git の差分/blame)とは別レイヤーで、こちらは GitHub 側
-- (PR の diff 確認 / コメント返信 / レビューコメント追加 / PR 本文修正)を担う。
-- 前提: gh CLI 導入済み・認証済み。picker は既存の telescope を再利用する
-- (依存宣言は lazy が dedupe するので二重ロードにならない)。
-- 起動は <leader>gp(GitHub PR list)のみ。バッファ内のコメント操作は octo の
-- 組み込み localleader マップ(<localleader>ca 追加 / <localleader>cr 返信 等)を
-- そのまま使う(再マップしない)。一覧は :Octo の組み込みコマンド説明を参照。
return {
  "pwntester/octo.nvim",
  cmd = "Octo",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope.nvim",
    "nvim-tree/nvim-web-devicons",
  },
  keys = {
    { "<leader>gp", "<cmd>Octo pr list<cr>", desc = "GitHub: PR 一覧" },
  },
  opts = {
    picker = "telescope",
    enable_builtin = true, -- 素の :Octo でコマンド一覧 picker を開く
  },
}
