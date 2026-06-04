-- nvim-treesitter — エディタ全体のシンタックスハイライトを正規表現から treesitter へ格上げ。
--
-- ★ main ブランチ流儀で書く(master とは互換性が無い)。
--   ネットに多い `require("nvim-treesitter.configs").setup({ ensure_installed, highlight })`
--   は master 専用で main では動かない。main は「パーサを入れるだけ」に痩せ、
--   ハイライト有効化は本体 API `vim.treesitter.start()` を FileType autocmd で呼ぶ。
-- ★ main は lazy-load 非対応 → lazy = false 固定。build = ":TSUpdate" でパーサを最新追従。
-- ★ indent モジュールは experimental なので使わない。インデントは options.lua の
--   smartindent を維持する(ここでは何も触らない)。folding も変更しない。

-- 導入するパーサ集合(同梱済みのものも列挙してよい。main が最新版を入れ直す)。
local parsers = {
  "lua", "vim", "vimdoc", "query", "bash",
  "json", "yaml", "toml",
  "markdown", "markdown_inline",
  "typescript", "tsx", "javascript", "css", "html",
}

return {
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,        -- main は lazy-load 非対応
    build = ":TSUpdate", -- 導入済みパーサを最新へ
    config = function()
      -- パーサ導入。install() は非同期かつ冪等(導入済みなら no-op)。
      require("nvim-treesitter").install(parsers)

      -- ハイライト有効化は本体 API。パーサ未導入の filetype で呼ぶとエラーになるため
      -- pcall でガードした「全 filetype 試行」イディオムにする(導入済みだけが効く)。
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(ev)
          pcall(vim.treesitter.start, ev.buf)
        end,
      })
    end,
  },
}
