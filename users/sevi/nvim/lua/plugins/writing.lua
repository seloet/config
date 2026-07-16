return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        harper_ls = {
          filetypes = {
            "gitcommit",
            "markdown",
            "quarto",
            "rmd",
            "tex",
          },
        },
      },
    },
  },
}
