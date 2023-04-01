local M = {}

function M.slugify(input_string, skip_lowercase)
    local output_string = input_string
    if not skip_lowercase then
        output_string = string.lower(input_string)
    end
    output_string = string.gsub(output_string, '[ %[%]()%{%}%\\%/-.,=%\'%\":;><`]+', '_')
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
function M.edit_note(file_dir, title)
    title = title or ""

    local opts = require("field_notes.opts")

    local filename = M.slugify(title)
    local file_path = file_dir .. '/' .. filename .. '.' .. opts.get().file_extension

    if not M.buffer_is_in_field_notes() then
        if not M.buffer_is_empty() then
            if opts.get()._vert then vim.cmd.vsplit() else vim.cmd.split() end
        end
        vim.cmd.lcd(vim.fn.expand(opts.get().field_notes_path))
    end
    vim.cmd.edit(file_path)

    -- TODO if the file_path doesn't exist yet, write the title to buffer
    local file_path_exists = vim.fn.filereadable(file_path)
    if file_path_exists == 0 and title ~= "" and M.buffer_is_empty() then
        local lines = {"# " .. title, ""}
        vim.api.nvim_buf_set_lines(0, 0, 0, true, lines)
        vim.cmd('setl nomodified')
        vim.cmd.normal('G$')
    end
end

function M.get_journal_title(timescale, timestamp)
    timestamp = timestamp or vim.fn.strftime('%s')
    local opts = require("field_notes.opts")
    local date_title_fmt = opts.get().journal_date_title_formats[timescale]
    return vim.fn.strftime(date_title_fmt, timestamp)
end

function M.get_journal_dir(timescale)
    local opts = require("field_notes.opts")
    if not timescale then
        return table.concat({
            opts.get().field_notes_path,
            opts.get().journal_dir,
        }, '/')
    end
    local timescale_dir = opts.get().journal_subdirs[timescale]
    return table.concat({
        opts.get().field_notes_path,
        opts.get().journal_dir,
        timescale_dir,
    }, '/')
end

function M.get_notes_dir()
    local opts = require("field_notes.opts")
    return table.concat({
        opts.get().field_notes_path,
        opts.get().notes_dir,
    }, '/')
end

function M.add_field_note_link_at_cursor(filename)
    local link_string = table.concat({"[[", filename, "]]"})
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1] - 1
    local col = cursor[2]
    vim.api.nvim_buf_set_text(0, row, col, row, col, {link_string})
    vim.cmd.write()
end

function M.add_field_note_link_at_current_journal(filename, timescale)
    local opts = require("field_notes.opts")

    -- Open current journal at timescale
    local title = M.get_journal_title(timescale, nil)
    local file_dir = M.get_journal_dir(timescale)
    local file_path = file_dir .. '/' .. M.slugify(title) .. '.' .. opts.get().file_extension
    if vim.fn.filereadable(file_path) == 0 then
        -- Exit if file doesn't exist
        return
    end

    -- Load the journal file
    local _bufnr_already_exists = vim.fn.bufexists(file_path)
    local bufnr = vim.fn.bufadd(file_path)
    vim.fn.bufload(file_path)
    -- Get list of lines
    local content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    -- Search for anchor
    local anchor = opts.get().journal_link_anchor
    local last_link_idx
    local link_match
    local title_idx = 0
    for line_idx, line in ipairs(content) do
        if title_idx == 0 and string.match(line, "^#%s") then
            title_idx = line_idx
        elseif not last_link_idx and string.match(line, "^" .. anchor) then
            last_link_idx = line_idx
        elseif last_link_idx then
            link_match = string.match(line, "%[%[(%S+)%]%]")
            if link_match then
                if link_match == filename then
                    -- Exit if item is already in list
                    if _bufnr_already_exists == 0 then
                        vim.cmd.bwipeout(file_path)
                    end
                    return
                end
                last_link_idx = line_idx
            else
                break
            end
        end
    end

    -- If anchor is not present, insert new anchor 2 lines below title
    if not last_link_idx then
        vim.api.nvim_buf_set_lines(bufnr, title_idx, title_idx, false, {"", anchor})
        last_link_idx = title_idx + 2
    end

    -- Get link str and insert line at end of list
    local link_string = table.concat({"[[", filename, "]]"})
    vim.api.nvim_buf_set_lines(bufnr, last_link_idx, last_link_idx, false, {"* " .. link_string})

    -- Close buffer
    vim.api.nvim_buf_call(bufnr, function() vim.cmd("silent write") end)
    if _bufnr_already_exists == 0 then
        vim.cmd.bwipeout(file_path)
    end

end

function M.buffer_is_in_field_notes(buf_idx, subdir)
    buf_idx = buf_idx or 0
    local opts = require("field_notes.opts")

    local buf_path = vim.api.nvim_buf_get_name(buf_idx)

    local field_notes_path = vim.fn.expand(opts.get().field_notes_path)
    if subdir then
        if subdir == "notes" then
            field_notes_path = M.get_notes_dir()
        elseif subdir == "journal" then
            field_notes_path = M.get_journal_dir()
        elseif M.is_timescale(subdir) then
            field_notes_path = M.get_journal_dir(subdir)
        end
    end

    if field_notes_path:sub(-1) ~= "/" then field_notes_path = field_notes_path .. '/' end

    local field_notes_path_in_buf_path = string.find(buf_path, field_notes_path, 1, true)
    if field_notes_path_in_buf_path then return true end
    return false
end


function M.buffer_is_empty(buf_idx)
    buf_idx = buf_idx or 0
    local status = false
    if #vim.api.nvim_buf_get_lines(buf_idx, 1, -1, false) == 0 then
        status = true
    end
    return status
end

-- Infers project name and branch name from current directory
-- Returns "<proj>: <branch>" as a string
-- TODO test
function M.get_note_title()
    local project_name, branch_name, _

    local project_path
    if M.is_in_git_project() then
        -- In a git project,
        -- project name will be the project directory
        -- and the branch name is the current branch
        project_path = vim.fn.finddir('.git/..', vim.fn.expand('%:p:h') .. ';')
        project_name = project_path:match('[^/]+$')
        branch_name = M.quiet_run_shell('git branch --show-current --quiet')
    else
        -- Not a git project,
        -- project name will be the upper directory
        -- and the branch name is the current directory
        project_path = vim.cmd.pwd()
        local project_parent_dirs = vim.fn.split(project_path, '/')
        local n_parents = #project_parent_dirs
        project_name = project_parent_dirs[n_parents - 1] or ""
        branch_name = project_parent_dirs[n_parents] or ""
    end

    -- Trim any leading punctuation before returning
    project_name, _ = string.gsub(project_name, '^%p+', '')
    branch_name, _ = string.gsub(branch_name, '^%p+', '')
    return project_name .. ": " .. branch_name
end

-- TODO is_git_dir
-- git rev-parse --git-dir 2> /dev/null;
function M.is_in_git_project()
    local git_is_installed = (#M.quiet_run_shell("command -v git") > 0)
    if not git_is_installed then return false end

    local git_dir_found = (#M.quiet_run_shell("git rev-parse --git-dir") > 0)
    if not git_dir_found then return false end

    return true
end

-- Outputs a string
function M.quiet_run_shell(cmd)
    local _
    cmd = cmd or ""
    cmd, _ = string.gsub(cmd, ";$" , "")
    local result = ""
    if #cmd > 0 then
        local quiet_stderr = "2> /dev/null"
        cmd = cmd .. " " .. quiet_stderr
        result = io.popen(cmd):read()
    end
    return result or {}
end

function M.is_direction(input_str)
    input_str = input_str or ""
    local out = false
    for _, direction in ipairs({"left", "down", "up", "right"}) do
        if input_str == direction then
            out = true
            break
        end
    end
    return out
end

function M.is_timescale(input_str)
    input_str = input_str or ""
    local out = false
    for _, timescale in ipairs({"day", "week", "month" }) do
        if input_str == timescale then
            out = true
            break
        end
    end
    return out
end

local function parse_date_format_char(char, date_format, input_str)
    local output, search_pattern, char_matches, _
    search_pattern, _ = string.gsub(date_format, '%%[^' .. char .. ']', '.+')
    search_pattern, _ = string.gsub(search_pattern, '([%-])', '%%%1')  -- Escape other regex chars
    search_pattern, char_matches = string.gsub(search_pattern, '%%' .. char, '(%%d+)')
    if char_matches == 0 then
        -- print(table.concat({"Character", "%" .. char, "not found in", date_format}, ' '))
        return nil
    end

    -- TODO escape other characters in search_pattern
    search_pattern = string.gsub(search_pattern, '', '')
    output = string.match(input_str, search_pattern)
    if not output then
        error(table.concat({"No match found for", char, "in", input_str, "with search", search_pattern}, ' '))
    end
    -- print(table.concat({"Match",output,"found for", char, "in", input_str, "with search", search_pattern,}, ' '))
    return tonumber(output)
end

local function day_of_first_wday(wday, year)
    for i=1,7 do
        if os.date("*t", os.time({year=year, day=i})).wday == wday then
            return i
        end
    end
end


function M.get_datetbl_from_str(date_format, input_str)
    local _

    -- parse s if present
    local timestamp = parse_date_format_char('s', date_format, input_str)
    if timestamp then
        return os.date('*t', timestamp)
    end

    -- replace x with d/m/y fmt
    if string.match(date_format, '%%x') then
        date_format, _ = string.gsub(date_format, "%%x", "%%d/%%m/%%y")
    end

    -- parse year
    local year = parse_date_format_char('Y', date_format, input_str)
    if not year then
        year = parse_date_format_char('y', date_format, input_str)
        if year < 70 then
            year = 2000 + year
        else
            year = 1900 + year
        end
    end
    if not year then error("NO YEAR FOUND") end

    -- parse month
    local month = parse_date_format_char('m', date_format, input_str) or 1

    -- parse day
    local day = parse_date_format_char('d', date_format, input_str)
    if day then
        return {year=year, month=month, day=day}
    end

    -- parse day of year
    local dayofyear = parse_date_format_char('j', date_format, input_str)
    if dayofyear then
        return {year=year, month=1, day=dayofyear}
    end

    -- parse day of week
    local dayofweek = parse_date_format_char('w', date_format, input_str) or 0

    -- parse week number
    local weeknum_sun = parse_date_format_char('U', date_format, input_str)
    local weeknum_mon = parse_date_format_char('W', date_format, input_str)
    if weeknum_sun then
        local day_of_first_sun = day_of_first_wday(1, year)
        day = day_of_first_sun + 7 * (weeknum_sun - 1) + (dayofweek)
    elseif weeknum_mon then
        local day_of_first_mon = day_of_first_wday(2, year)
        day = day_of_first_mon + 7 * (weeknum_mon - 1) + (dayofweek - 1)
    end
    return {year = year, month=1, day=day or 1}
end

return M

-- TODO look into vim.uri_from_bufnr
-- TODO yaml header writer
-- ```lua
-- local date = io.popen("date -u +'%Y_%m_%d'"):read()
-- local new_note = io.open(note_path, 'w')
-- Write yaml header
-- new_note:write("---\n")
-- new_note:write("title: " .. title .. "\n")
-- new_note:write("date: " .. string.gsub(date, '_', '-') .. "\n")
-- new_note:write("tags:\n")
-- new_note:write("---\n\n")
-- Write title and close
-- new_note:write("# " .. title .. '\n\n\n')
-- new_note:close()
-- ```
