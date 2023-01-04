local lspconfig = require('lspconfig')

local capabilities = vim.lsp.protocol.make_client_capabilities()

capabilities = require('cmp_nvim_lsp').default_capabilities(capabilities)

local signs = {
  Error = ' ',
  Warn = ' ',
  Info = ' ',
  Hint = ' ',
}
for type, icon in pairs(signs) do
  local hl = 'DiagnosticSign' .. type
  vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
end

vim.diagnostic.config({
  signs = true,
  update_in_insert = false,
  underline = true,
  severity_sort = true,
  virtual_text = {
    prefix = '🔥',
    source = true,
  },
})

local servers = {
  'dockerls',
  'bashls',
  'pyright',
  'rust_analyzer',
  'tsserver',
  'gopls',
  'sumneko_lua',
  'clangd',
  'jsonls',
}

-- Ensure the servers above are installed
require('mason').setup()
require('mason-lspconfig').setup({
  ensure_installed = servers,
})

for _, server in ipairs(servers) do
  lspconfig[server].setup({
    capabilities = capabilities,
  })
end

require("mason-null-ls").setup({
    ensure_installed = {
        'sql_formatter',
        'markdownlint'
    },
    automatic_installation = false,
    automatic_setup = true, -- Recommended, but optional
})

--[[ Anything not supported by mason.
require("null-ls").setup(
    sources = {},
)]]--

require 'mason-null-ls'.setup_handlers() -- If `automatic_setup` is true.

vim.lsp.handlers['workspace/diagnostic/refresh'] = function(_, _, ctx)
  local ns = vim.lsp.diagnostic.get_namespace(ctx.client_id)
  local bufnr = vim.api.nvim_get_current_buf()
  vim.diagnostic.reset(ns, bufnr)
  return true
end
