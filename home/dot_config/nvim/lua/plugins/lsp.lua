-- LSP セットアップ
--
-- LSP server バイナリは mise (~/.config/mise/config.toml) で一元管理し、
-- PATH 経由で Neovim と Claude Code が同じバイナリを共有する。
-- Mason は使わない。サーバー設定は nvim-lspconfig 同梱の定義をそのまま利用。

return {
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      -- mise で入れた LSP サーバーを有効化(Neovim 0.11+ ネイティブ API)。
      -- 各サーバーのバイナリが PATH 上に無ければ単に attach されないだけ。
      vim.lsp.enable({
        "vtsls",    -- TypeScript / JavaScript
        "lua_ls",   -- Lua (Neovim 設定)
        "marksman", -- Markdown
        "jsonls",   -- JSON
        "eslint",   -- ESLint
        "cssls",    -- CSS
        "html",     -- HTML
      })

      -- LSP attach 時の keymap
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(ev)
          local opts = { buffer = ev.buf, silent = true }
          vim.keymap.set("n", "gd", vim.lsp.buf.definition, vim.tbl_extend("force", opts, { desc = "定義へジャンプ" }))
          vim.keymap.set("n", "gr", vim.lsp.buf.references, vim.tbl_extend("force", opts, { desc = "参照一覧" }))
          vim.keymap.set("n", "gi", vim.lsp.buf.implementation, vim.tbl_extend("force", opts, { desc = "実装へジャンプ" }))
          vim.keymap.set("n", "K", vim.lsp.buf.hover, vim.tbl_extend("force", opts, { desc = "hover" }))
          vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, vim.tbl_extend("force", opts, { desc = "rename" }))
          vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, vim.tbl_extend("force", opts, { desc = "code action" }))
          vim.keymap.set("n", "[d", function() vim.diagnostic.jump({ count = -1, float = true }) end, vim.tbl_extend("force", opts, { desc = "前の diagnostic" }))
          vim.keymap.set("n", "]d", function() vim.diagnostic.jump({ count = 1, float = true }) end, vim.tbl_extend("force", opts, { desc = "次の diagnostic" }))
        end,
      })
    end,
  },
}
