-- カラースキーム
-- VSCode の Panda Theme と世界観を揃えるため、公式 Vim 移植
-- markvincze/panda-vim をそのまま採用する。Ghostty 側も自作 panda テーマで一致。
-- 背景は本家より僅かに暗い Panda 公式の _background-dark (#242526) へ調整。

return {
  {
    "markvincze/panda-vim",
    priority = 1000,
    lazy = false,
    config = function()
      vim.cmd.colorscheme("panda")
      local bg = "#242526"
      -- 各グループの既存定義を保持したまま背景色だけ差し替える
      for _, group in ipairs({
        "Normal",
        "NormalNC",
        "NormalFloat",
        "SignColumn",
        "LineNr",
        "EndOfBuffer",
      }) do
        local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
        hl.bg = bg
        vim.api.nvim_set_hl(0, group, hl)
      end
    end,
  },
}
