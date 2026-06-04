-- render-markdown.nvim — Markdown バッファ内レンダリング(Notion 風 WYSIWYG)。
--
-- treesitter ハイライトの上に描画層を薄く乗せるだけ。重い/邪魔なら <leader>tm で
-- 剥がせば素の treesitter ハイライトが残る(フォールバックがタダ)。
-- ★ render_modes = { "n", "c", "t" } を明示 = insert mode は生記号 / normal mode で整形の
--   ハイブリッド挙動(書く時はカーソルズレ無し、眺める時だけ整形)。
-- ★ conceallevel はグローバル設定しない。render-markdown が win_options で自動管理する
--   (rendered 時に conceal、raw 時はユーザー値へ復帰)。options.lua は触らない。
-- ★ アイコン表示は Nerd Font 前提(nvim-web-devicons)。Ghostty は JetBrainsMono Nerd Font 設定済み。

return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-tree/nvim-web-devicons",
    },
    ft = { "markdown" },
    opts = {
      render_modes = { "n", "c", "t" },
    },
    config = function(_, opts)
      require("render-markdown").setup(opts)

      -- トグルは markdown バッファのバッファローカルマップとして張る。
      -- ft=markdown 遅延ロードなのでグローバルに張ると未ロード時に require が落ちる。
      local function map_toggle(buf)
        vim.keymap.set("n", "<leader>tm", function()
          require("render-markdown").toggle()
        end, { buffer = buf, desc = "Markdown レンダリング表示トグル(md バッファ)" })
      end

      vim.api.nvim_create_autocmd("FileType", {
        pattern = "markdown",
        callback = function(ev) map_toggle(ev.buf) end,
      })

      -- config はプラグインを最初に開いた markdown バッファのロード時に走る。その初回
      -- バッファは上の autocmd 登録より前に FileType を発火済みのことがあり、autocmd では
      -- 取りこぼす。今開いているバッファが markdown なら即時に張って初回も確実にする。
      if vim.bo.filetype == "markdown" then
        map_toggle(0)
      end
    end,
  },
}
