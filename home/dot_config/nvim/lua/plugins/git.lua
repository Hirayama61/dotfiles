return {
  "lewis6991/gitsigns.nvim",
  event = { "BufReadPre", "BufNewFile" },
  config = function()
    require("gitsigns").setup({
      current_line_blame = true,    -- カーソル行末に inline blame
      current_line_blame_opts = {
        delay = 500,
      },
    })
  end,
}
