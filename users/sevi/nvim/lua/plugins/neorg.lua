return {
  {
    "nvim-neorg/neorg",
    version = "v9.6.4",
    lazy = false,
    init = function()
      -- Lazy installs Neorg's parser rocks outside runtimepath. Make their
      -- parser modules discoverable before Neorg initializes tree-sitter.
      local rocks = vim.fn.stdpath("data") .. "/lazy-rocks"
      package.cpath = table.concat({
        rocks .. "/tree-sitter-norg/lib/lua/5.1/?.so",
        rocks .. "/tree-sitter-norg-meta/lib/lua/5.1/?.so",
        package.cpath,
      }, ";")
    end,
    opts = {
      load = {
        ["core.defaults"] = {},
        ["core.concealer"] = {},
        ["core.dirman"] = {
          config = {
            workspaces = {
              notes = "~/notes",
            },
            default_workspace = "notes",
          },
        },
        ["core.journal"] = {
          config = {
            workspace = "notes",
          },
        },
      },
    },
  },
}
