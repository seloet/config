return {
  {
    "GCBallesteros/jupytext.nvim",
    lazy = false,
    config = function()
      require("jupytext").setup({
        style = "markdown",
        output_extension = "md",
        force_ft = "markdown",
      })

      vim.api.nvim_create_autocmd("BufReadCmd", {
        pattern = "*.ipynb",
        callback = function(ev)
          vim.schedule(function()
            if not vim.api.nvim_buf_is_loaded(ev.buf) or vim.bo[ev.buf].filetype ~= "markdown" then
              return
            end
            local file = assert(io.open(ev.file, "rb"))
            local notebook = vim.json.decode(file:read("*a"))
            file:close()

            local has_outputs = false
            for _, cell in ipairs(notebook.cells) do
              if cell.cell_type == "code" and cell.outputs and #cell.outputs > 0 then
                has_outputs = true
                break
              end
            end
            if not has_outputs then
              return
            end

            local kernels = vim.fn.MoltenAvailableKernels()
            local spec = notebook.metadata.kernelspec
            local kernel = spec and spec.name
            if not kernel or not vim.tbl_contains(kernels, kernel) then
              kernel = vim.tbl_contains(kernels, "nix-python3") and "nix-python3" or nil
            end
            if not kernel then
              vim.notify("Cannot show notebook outputs: no Jupyter kernel is available", vim.log.levels.WARN)
              return
            end

            vim.api.nvim_buf_call(ev.buf, function()
              if #vim.fn.MoltenRunningKernels(true) > 0 then
                return
              end
              vim.api.nvim_cmd({ cmd = "MoltenInit", args = { kernel } }, {})
              local running = vim.fn.MoltenRunningKernels(true)
              if #running > 0 then
                vim.api.nvim_cmd({ cmd = "MoltenImportOutput", args = { ev.file, running[#running] } }, {})
              end
            end)
          end)
        end,
      })
    end,
  },

  {
    "benlubas/molten-nvim",
    lazy = false,
    build = ":UpdateRemotePlugins",
    init = function()
      local data = vim.env.JUPYTER_DATA_DIR or (vim.env.XDG_DATA_HOME or vim.fn.expand("~/.local/share")) .. "/jupyter"
      if vim.fn.mkdir(data .. "/runtime", "p") == 0 then
        error("Cannot create Jupyter connection directory: " .. data .. "/runtime")
      end
      vim.g.molten_auto_open_output = false
      vim.g.molten_wrap_output = true
      vim.g.molten_virt_text_output = true
      vim.g.molten_virt_lines_off_by_1 = true
    end,
  },

  {
    "quarto-dev/quarto-nvim",
    ft = { "markdown", "quarto" },
    dependencies = {
      "jmbuhr/otter.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    keys = {
      { "<leader>mc", function() require("quarto.runner").run_cell() end, desc = "Run notebook code cell" },
    },
    opts = {
      lspFeatures = {
        languages = { "python" },
        chunks = "all",
        diagnostics = { enabled = true, triggers = { "BufWritePost" } },
        completion = { enabled = true },
      },
      codeRunner = {
        enabled = true,
        default_method = "molten",
      },
    },
    config = function(_, opts)
      require("quarto").setup(opts)

      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "markdown", "quarto" },
        callback = function()
          require("quarto").activate()
        end,
      })
    end,
  },

  {
    "MeanderingProgrammer/render-markdown.nvim",
    opts = {
      file_types = { "markdown", "quarto" },
    },
  },

  {
    "benlubas/molten-nvim",
    keys = {
      { "<leader>mi", ":MoltenInit<CR>", desc = "Choose notebook kernel", silent = true },
      { "<leader>me", ":MoltenExportOutput!<CR>", desc = "Save evaluated outputs to notebook", silent = true },
      { "<leader>mr", ":MoltenReevaluateCell<CR>", desc = "Re-run evaluated cell", silent = true },
      { "<leader>ma", ":<C-u>MoltenEvaluateVisual<CR>gv", desc = "Run notebook selection", silent = true, mode = "v" },
      { "<leader>mo", ":noautocmd MoltenEnterOutput<CR>", desc = "Open cell output", silent = true },
      { "<leader>mh", ":MoltenHideOutput<CR>", desc = "Hide cell output", silent = true },
    },
  },

  {
    "folke/snacks.nvim",
    init = function()
      local function repl(focus)
        local python = vim.fn.exepath("python3")
        if python == "" then
          vim.notify("Python 3 is not available for the REPL", vim.log.levels.ERROR)
          return
        end
        local cmd = { python, "-i", "-q" }
        local opts = { cwd = vim.fn.getcwd(), win = { position = "bottom", height = 12 } }
        if focus then
          return Snacks.terminal.focus(cmd, opts)
        end
        local source_win = vim.api.nvim_get_current_win()
        local terminal = Snacks.terminal.get(cmd, opts)
        terminal:show()
        vim.api.nvim_set_current_win(source_win)
        return terminal
      end

      local function send(text)
        local terminal = repl(false)
        if terminal then
          vim.api.nvim_chan_send(vim.b[terminal.buf].terminal_job_id, text .. "\n")
        end
      end

      vim.api.nvim_create_autocmd("FileType", {
        pattern = "python",
        callback = function(ev)
          vim.keymap.set("n", "<leader>rp", function() repl(true) end, { buffer = ev.buf, desc = "Focus Python REPL" })
          vim.keymap.set("n", "<leader>rl", function() send(vim.api.nvim_get_current_line()) end, {
            buffer = ev.buf,
            desc = "Send line to Python REPL",
          })
          vim.keymap.set("x", "<leader>rs", function()
            local lines = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = vim.fn.mode() })
            send("exec(" .. vim.json.encode(table.concat(lines, "\n")) .. ")")
          end, { buffer = ev.buf, desc = "Send selection to Python REPL" })
        end,
      })
    end,
  },
}
