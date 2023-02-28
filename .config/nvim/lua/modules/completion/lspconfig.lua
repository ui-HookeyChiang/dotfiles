local lspconfig = require('lspconfig')

local capabilities = vim.lsp.protocol.make_client_capabilities()

capabilities = require('cmp_nvim_lsp').default_capabilities(capabilities)

local signs = {
  Error = ' ',
  Warn = ' ',
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

local function _attach(client, _)
  vim.opt.omnifunc = 'v:lua.vim.lsp.omnifunc'
  client.server_capabilities.semanticTokensProvider = nil
end

--- Ensure the servers above are installed
require('mason').setup()
require('mason-lspconfig').setup({
  ensure_installed = {
    'dockerls',
    'pyright',
    'bashls',
    'jsonls',
    'tsserver',
    'gopls',
    'lua_ls',
    'rust_analyzer',
    'clangd',
    'sqlls',
    'marksman',
  },
})

lspconfig.gopls.setup({
  cmd = { 'gopls', 'serve' },
  capabilities = capabilities,
  on_attach = _attach,
  init_options = {
    usePlaceholders = true,
    completeUnimported = true,
  },
  settings = {
    gopls = {
      analyses = {
        unusedparams = true,
      },
      staticcheck = true,
      env = {
        GOFLAGS = '-tags=windows,linux,unittest',
      },
    },
  },
})

lspconfig.lua_ls.setup({
  capabilities = capabilities,
  on_attach = _attach,
  settings = {
    Lua = {
      diagnostics = {
        enable = true,
        globals = { 'vim' },
      },
      runtime = {
        version = 'LuaJIT',
        path = vim.split(package.path, ';'),
      },
      workspace = {
        library = {
          vim.env.VIMRUNTIME,
          vim.env.HOME .. '/.local/share/nvim/lazy/emmylua-nvim',
        },
        checkThirdParty = false,
      },
      completion = {
        callSnippet = 'Replace',
      },
    },
  },
})

lspconfig.clangd.setup({
  capabilities = capabilities,
  on_attach = _attach,
  cmd = {
    'clangd',
    '--background-index',
    '--suggest-missing-includes',
    '--clang-tidy',
    '--header-insertion=iwyu',
  },
})

lspconfig.rust_analyzer.setup({
  capabilities = capabilities,
  on_attach = _attach,
  settings = {
    ['rust-analyzer'] = {
      imports = {
        granularity = {
          group = 'module',
        },
        prefix = 'self',
      },
      cargo = {
        buildScripts = {
          enable = true,
        },
      },
      procMacro = {
        enable = true,
      },
    },
  },
})

local servers = {
  'dockerls',
  'pyright',
  'bashls',
  'zls',
  'jsonls',
  'tsserver',
}

for _, server in ipairs(servers) do
  lspconfig[server].setup({
    capabilities = capabilities,
    on_attach = _attach,
  })
end

--require('mason-null-ls').setup({
--  ensure_installed = {},
--  automatic_installation = false,
--  automatic_setup = true,
--})
--
----- If `automatic_setup` is true
--require('mason-null-ls').setup_handlers()

vim.lsp.handlers['workspace/diagnostic/refresh'] = function(_, _, ctx)
  local ns = vim.lsp.diagnostic.get_namespace(ctx.client_id)
  local bufnr = vim.api.nvim_get_current_buf()
  print(bufnr, ns, vim.inspect(ctx))
  vim.diagnostic.reset(ns, bufnr)
  return true
end
