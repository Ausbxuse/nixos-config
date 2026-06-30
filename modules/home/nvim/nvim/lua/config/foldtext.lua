local M = {}

local suffix_hl = 'FoldedEllipsis'

local function hl(name)
  local ok, value = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  if ok then
    return value
  end
  return {}
end

local function setup_suffix_hl()
  local normal = hl('Normal')
  local bg = normal.bg or 0x1e1e1e
  local r = math.floor(bg / 0x10000) % 0x100
  local g = math.floor(bg / 0x100) % 0x100
  local b = bg % 0x100
  local luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b

  vim.api.nvim_set_hl(0, suffix_hl, {
    fg = luminance > 128 and 0x6a6a6a or 0x808080,
  })
end

local function capture_group(capture)
  if not capture or not capture.capture then
    return 'Normal'
  end

  local group = '@' .. capture.capture
  if capture.lang and capture.lang ~= '' then
    group = group .. '.' .. capture.lang
  end

  return group
end

local function top_capture(bufnr, row, col)
  local ok, captures = pcall(vim.treesitter.get_captures_at_pos, bufnr, row, col)
  if not ok or not captures or vim.tbl_isempty(captures) then
    return nil
  end

  return captures[#captures]
end

local function add_chunk(chunks, text, group)
  if text == '' then
    return
  end

  local last = chunks[#chunks]
  if last and last[2] == group then
    last[1] = last[1] .. text
  else
    table.insert(chunks, { text, group })
  end
end

function M.foldtext()
  local bufnr = vim.api.nvim_get_current_buf()
  local row = vim.v.foldstart - 1
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
  local chunks = {}
  local byte_col = 0

  pcall(function()
    vim.treesitter.get_parser(bufnr):parse { row, row + 1 }
  end)

  while byte_col < #line do
    local next_col = vim.str_byteindex(line, vim.str_utfindex(line, byte_col) + 1)
    local capture = top_capture(bufnr, row, byte_col)

    add_chunk(chunks, line:sub(byte_col + 1, next_col), capture_group(capture))
    byte_col = next_col
  end

  local line_count = vim.v.foldend - vim.v.foldstart + 1
  local suffix = line_count == 1 and 'line' or 'lines'
  add_chunk(chunks, string.format(' … %d %s', line_count, suffix), suffix_hl)

  return chunks
end

setup_suffix_hl()

vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('TreesitterFoldText', { clear = true }),
  callback = setup_suffix_hl,
})

return M
