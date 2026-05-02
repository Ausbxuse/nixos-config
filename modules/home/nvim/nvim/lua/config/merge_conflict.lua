local M = {}
local ns = vim.api.nvim_create_namespace("merge_conflict")

local function line(n)
  return vim.api.nvim_buf_get_lines(0, n - 1, n, false)[1] or ""
end

local function starts_with_marker(text, marker)
  return text:sub(1, #marker) == marker
end

local function find_conflict()
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  local last = vim.api.nvim_buf_line_count(0)
  local start_line

  for n = cursor, 1, -1 do
    local text = line(n)
    if starts_with_marker(text, "<<<<<<<") then
      start_line = n
      break
    end
    if starts_with_marker(text, ">>>>>>>") then
      break
    end
  end

  if not start_line then
    return nil, "cursor is not inside a conflict block"
  end

  local base_line
  local middle_line
  local end_line

  for n = start_line + 1, last do
    local text = line(n)
    if starts_with_marker(text, "|||||||") and not middle_line then
      base_line = n
    elseif starts_with_marker(text, "=======") then
      middle_line = n
    elseif starts_with_marker(text, ">>>>>>>") then
      end_line = n
      break
    elseif starts_with_marker(text, "<<<<<<<") then
      return nil, "nested or malformed conflict block"
    end
  end

  if not middle_line or not end_line then
    return nil, "malformed conflict block"
  end

  return {
    start_line = start_line,
    base_line = base_line,
    middle_line = middle_line,
    end_line = end_line,
  }
end

local function find_all_conflicts()
  local conflicts = {}
  local last = vim.api.nvim_buf_line_count(0)
  local n = 1

  while n <= last do
    if starts_with_marker(line(n), "<<<<<<<") then
      local start_line = n
      local base_line
      local middle_line
      local end_line

      n = n + 1
      while n <= last do
        local text = line(n)
        if starts_with_marker(text, "|||||||") and not middle_line then
          base_line = n
        elseif starts_with_marker(text, "=======") then
          middle_line = n
        elseif starts_with_marker(text, ">>>>>>>") then
          end_line = n
          break
        elseif starts_with_marker(text, "<<<<<<<") then
          break
        end
        n = n + 1
      end

      if middle_line and end_line then
        table.insert(conflicts, {
          start_line = start_line,
          base_line = base_line,
          middle_line = middle_line,
          end_line = end_line,
        })
      end
    end
    n = n + 1
  end

  return conflicts
end

local function slice(first, last)
  if first > last then
    return {}
  end
  return vim.api.nvim_buf_get_lines(0, first - 1, last, false)
end

local function replace_conflict(conflict, replacement)
  vim.api.nvim_buf_set_lines(
    0,
    conflict.start_line - 1,
    conflict.end_line,
    false,
    replacement
  )
  vim.api.nvim_win_set_cursor(0, { conflict.start_line, 0 })
  M.refresh_highlights()
end

local function resolve(kind)
  local conflict, err = find_conflict()
  if not conflict then
    vim.notify(err, vim.log.levels.WARN)
    return
  end

  local ours_end = (conflict.base_line or conflict.middle_line) - 1
  local ours = slice(conflict.start_line + 1, ours_end)
  local theirs = slice(conflict.middle_line + 1, conflict.end_line - 1)
  local replacement

  if kind == "ours" then
    replacement = ours
  elseif kind == "theirs" then
    replacement = theirs
  elseif kind == "both" then
    replacement = vim.list_extend(ours, theirs)
  elseif kind == "both_reverse" then
    replacement = vim.list_extend(theirs, ours)
  elseif kind == "none" then
    replacement = {}
  else
    error("unknown conflict resolution kind: " .. tostring(kind))
  end

  replace_conflict(conflict, replacement)
end

local function cursor_side(conflict)
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  local ours_end = (conflict.base_line or conflict.middle_line) - 1

  if cursor > conflict.start_line and cursor <= ours_end then
    return "ours"
  end

  if cursor > conflict.middle_line and cursor < conflict.end_line then
    return "theirs"
  end

  if conflict.base_line and cursor > conflict.base_line and cursor < conflict.middle_line then
    return "base"
  end

  return "marker"
end

function M.choose_both()
  resolve("both")
end

function M.choose_both_reverse()
  resolve("both_reverse")
end

function M.choose_none()
  resolve("none")
end

function M.choose_current()
  local conflict, err = find_conflict()
  if not conflict then
    vim.notify(err, vim.log.levels.WARN)
    return
  end

  local side = cursor_side(conflict)
  if side == "ours" or side == "theirs" then
    resolve(side)
    return
  end

  vim.notify("move cursor into ours or theirs section first", vim.log.levels.WARN)
end

function M.next_conflict()
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  local last = vim.api.nvim_buf_line_count(0)

  for n = cursor + 1, last do
    if starts_with_marker(line(n), "<<<<<<<") then
      vim.api.nvim_win_set_cursor(0, { n, 0 })
      return
    end
  end

  vim.notify("no next conflict", vim.log.levels.INFO)
end

function M.prev_conflict()
  local cursor = vim.api.nvim_win_get_cursor(0)[1]

  for n = cursor - 1, 1, -1 do
    if starts_with_marker(line(n), "<<<<<<<") then
      vim.api.nvim_win_set_cursor(0, { n, 0 })
      return
    end
  end

  vim.notify("no previous conflict", vim.log.levels.INFO)
end

function M.refresh_highlights(bufnr)
  bufnr = bufnr or 0
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  for _, conflict in ipairs(find_all_conflicts()) do
    local ours_end = (conflict.base_line or conflict.middle_line) - 1
    local theirs_start = conflict.middle_line + 1
    local base_start = conflict.base_line and (conflict.base_line + 1) or nil
    local base_end = conflict.base_line and (conflict.middle_line - 1) or nil

    vim.api.nvim_buf_set_extmark(bufnr, ns, conflict.start_line - 1, 0, {
      line_hl_group = "MergeConflictMarker",
    })
    vim.api.nvim_buf_set_extmark(bufnr, ns, conflict.middle_line - 1, 0, {
      line_hl_group = "MergeConflictMarker",
    })
    vim.api.nvim_buf_set_extmark(bufnr, ns, conflict.end_line - 1, 0, {
      line_hl_group = "MergeConflictMarker",
    })

    if conflict.base_line then
      vim.api.nvim_buf_set_extmark(bufnr, ns, conflict.base_line - 1, 0, {
        line_hl_group = "MergeConflictMarker",
      })
    end

    for n = conflict.start_line + 1, ours_end do
      vim.api.nvim_buf_set_extmark(bufnr, ns, n - 1, 0, {
        line_hl_group = "MergeConflictOurs",
      })
    end

    if base_start and base_end then
      for n = base_start, base_end do
        vim.api.nvim_buf_set_extmark(bufnr, ns, n - 1, 0, {
          line_hl_group = "MergeConflictBase",
        })
      end
    end

    for n = theirs_start, conflict.end_line - 1 do
      vim.api.nvim_buf_set_extmark(bufnr, ns, n - 1, 0, {
        line_hl_group = "MergeConflictTheirs",
      })
    end
  end
end

local function setup_highlights()
  vim.api.nvim_set_hl(0, "MergeConflictMarker", { link = "DiffText", default = true })
  vim.api.nvim_set_hl(0, "MergeConflictOurs", { link = "DiffAdd", default = true })
  vim.api.nvim_set_hl(0, "MergeConflictBase", { link = "DiffChange", default = true })
  vim.api.nvim_set_hl(0, "MergeConflictTheirs", { link = "DiffDelete", default = true })
end

function M.setup(opts)
  opts = opts or {}

  setup_highlights()

  vim.keymap.set("n", "<leader>cc", M.choose_current, { desc = "Choose current conflict side" })
  vim.keymap.set("n", "<leader>cb", M.choose_both, { desc = "Choose both" })
  vim.keymap.set("n", "<leader>cB", M.choose_both_reverse, { desc = "Choose both reversed" })
  vim.keymap.set("n", "<leader>c0", M.choose_none, { desc = "Choose none" })
  vim.keymap.set("n", "]x", M.next_conflict, { desc = "Next conflict" })
  vim.keymap.set("n", "[x", M.prev_conflict, { desc = "Previous conflict" })

  vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "TextChangedI" }, {
    group = vim.api.nvim_create_augroup("MergeConflictHighlights", { clear = true }),
    callback = function(args)
      M.refresh_highlights(args.buf)
    end,
  })

  M.refresh_highlights()
end

_G.MergeConflict = M
M.setup()

return M
