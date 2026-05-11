-- 必須プラグイン

return {
  -- ファジーファインダー
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = "Telescope",
    keys = {
      { "<leader>ff", function() require("telescope.builtin").find_files() end, desc = "ファイル検索" },
      { "<leader>fg", function() require("telescope.builtin").live_grep() end, desc = "文字列検索" },
    },
  },
}
