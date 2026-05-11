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
    require("oil").setup({
      view_options = {
        show_hidden = true,
      },
    })
    -- `-` キーで親ディレクトリを開く
    vim.keymap.set("n", "-", "<cmd>Oil<cr>", { desc = "親ディレクトリを開く" })
  end,
}
