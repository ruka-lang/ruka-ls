function RukaLsStart()
    local client = vim.lsp.start_client {
        name = "ruka-ls",
        cmd = { "/home/dwclake/ruka-lang/ruka-ls/zig-out/bin/ruka-ls" },
    }

    vim.filetype.add({
        extension = {
            ruka = "ruka"
        }
    })

    if not client then
        vim.notify "client thing no good"
        return
    end

    vim.api.nvim_create_autocmd("FileType", {
        pattern = "ruka",
        callback = function()
            vim.lsp.buf_attach_client(0, client)
        end
    })
end
