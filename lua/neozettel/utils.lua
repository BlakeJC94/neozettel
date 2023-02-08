local M = {}

function M.slugify(input_string)
    local output_string = string.lower(input_string)
    output_string = string.gsub(output_string, '[ %[%]()%{%}%\\%/-.,=%\'%\":;><]+', '_')
    output_string = string.gsub(output_string, '^[_]+', '')
    output_string = string.gsub(output_string, '[_]+$', '')
    return output_string
end

-- TODO Test
function M.create_dir(dir_path)
    if vim.fn.filereadable(dir_path) > 0 then
        error("Path at '" .. dir_path .. "' is a file, can't create directory here")
    end

    if vim.fn.isdirectory(dir_path) > 0 then
        return
    end

    local prompt = "Directory '" .. dir_path .. "' not found. Would you like to create it? (Y/n) : "
    local user_option = vim.fn.input(prompt)
    user_option = string.gsub(user_option, "^[ ]+", "")
    if string.sub(user_option, 1, 1) == 'Y' then
        vim.fn.mkdir(dir_path, "p")
    end
end

-- TODO Test
-- TODO Add template and keys to this instead of simply title
function M.edit_in_split(file_path, vert, title)
    vert = vert or false
    title = title or ""

    if vert then vim.cmd.vsplit() else vim.cmd.split() end
    vim.cmd.edit(file_path)
    vim.cmd.lcd(vim.fn.expand("%:p:h"))

    -- TODO if the file_path doesn't exist yet, write the title to buffer
    local file_path_exists = vim.fn.filereadable(file_path)
    if file_path_exists == 0 and title ~= "" then
        local lines = {"# " .. title, ""}
        vim.api.nvim_buf_set_lines(0, 0, 0, true, lines)
    end
    vim.cmd.normal('G$')
end

-- Infers project name and branch name from current directory
-- Returns "<proj>: <branch>" as a string
-- TODO test
function M.get_note_title()
    local project_name, branch_name, _

    -- Project name is either where the git dir is,
    -- or where vim is currently opened.
    local project_path = io.popen('git rev-parse --show-toplevel --quiet 2>/dev/null || pwd'):read()
    local project_parent_dirs = vim.fn.split(project_path, '/')
    local n_parents = #project_parent_dirs

    branch_name = io.popen('git branch --show-current --quiet 2>/dev/null'):read()
    if branch_name ~= nil then
        -- In a git project,
        -- project name will be the project directory
        -- and the branch name is the current branch
        project_name = project_parent_dirs[n_parents]
    else
        -- Not a git project,
        -- project name will be the upper directory
        -- and the branch name is the current directory
        project_name = project_parent_dirs[n_parents - 1] or ""
        branch_name = project_parent_dirs[n_parents] or ""
    end

    -- Trim any leading punctuation before returning
    project_name, _ = string.gsub(project_name, '^%p+', '')
    branch_name, _ = string.gsub(branch_name, '^%p+', '')
    return project_name .. ": " .. branch_name
end

return M

-- TODO look into vim.uri_from_bufnr
