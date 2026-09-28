return {
  {
    "nvim-neorg/neorg",
    version = "v9.6.4",
    lazy = false,
    init = function()
      local rocks = vim.fn.stdpath("data") .. "/lazy-rocks"
      package.cpath = table.concat({
        rocks .. "/tree-sitter-norg/lib/lua/5.1/?.so",
        rocks .. "/tree-sitter-norg-meta/lib/lua/5.1/?.so",
        package.cpath,
      }, ";")
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "norg",
        callback = function(ev)
          local opts = { buffer = ev.buf, silent = true }
          vim.keymap.set("n", "<C-Space>", "<Plug>(neorg.qol.todo-items.todo.task-cycle)", opts)
          vim.keymap.set("n", "<C-S-M-Space>", "<Plug>(neorg.qol.todo-items.todo.task-cycle-reverse)", opts)
          vim.keymap.set("n", "gO", "<cmd>Neorg toc<CR>", opts)
        end,
      })
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
