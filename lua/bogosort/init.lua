local M = {}

local ns = vim.api.nvim_create_namespace("bogosort")
local uv = vim.uv or vim.loop

local N = 25
local COL_W = 3 -- "## " per column

local function setup_hl()
  vim.api.nvim_set_hl(0, "BogoCorrect", { fg = "#00FF00", bold = true })
  vim.api.nvim_set_hl(0, "BogoWrong", { fg = "#FFB347" })
  vim.api.nvim_set_hl(0, "BogoHeader", { fg = "#888888", italic = true })
  vim.api.nvim_set_hl(0, "BogoSorted", { fg = "#FFD700", bold = true })
end

local function is_sorted(arr)
  for i = 1, #arr - 1 do
    if arr[i] > arr[i + 1] then return false end
  end
  return true
end

local function shuffle(arr)
  for i = #arr, 2, -1 do
    local j = math.random(i)
    arr[i], arr[j] = arr[j], arr[i]
  end
end

local function fmt_time(secs)
  return string.format("%02d:%02d:%02d",
    math.floor(secs / 3600),
    math.floor((secs % 3600) / 60),
    secs % 60)
end

local function fmt_attempts(n)
  if n >= 1e15 then
    return string.format("%.1fQ", n / 1e15)
  elseif n >= 1e12 then
    return string.format("%.1fT", n / 1e12)
  elseif n >= 1e9 then
    return string.format("%.1fB", n / 1e9)
  elseif n >= 1e6 then
    return string.format("%.1fM", n / 1e6)
  end
  local s = tostring(n)
  return s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

local function render(buf, arr, attempts, start_time, start_hrtime, done)
  local elapsed = fmt_time(os.time() - start_time)
  local elapsed_sec = math.max(0.001, (uv.hrtime() - start_hrtime) / 1e9)
  local sps = attempts / elapsed_sec
  local status = done and "*** SORTED! *** (q to close)" or "q to quit"
  local header = string.format(" %s SpS | shuffles: %s | elapsed: %s | %s",
    fmt_attempts(math.floor(sps)), fmt_attempts(attempts), elapsed, status)

  local lines = {}
  table.insert(lines, header)
  table.insert(lines, "")

  -- bar chart: row N at top, row 1 at bottom
  for row = N, 1, -1 do
    local parts = {}
    for col = 1, N do
      parts[col] = arr[col] >= row and "## " or "   "
    end
    table.insert(lines, table.concat(parts))
  end

  table.insert(lines, string.rep("---", N))

  local vparts = {}
  for col = 1, N do
    vparts[col] = string.format("%-3d", arr[col])
  end
  table.insert(lines, table.concat(vparts))

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  -- header highlight
  local header_hl = done and "BogoSorted" or "BogoHeader"
  vim.api.nvim_buf_add_highlight(buf, ns, header_hl, 0, 0, -1)

  -- bar + values highlights
  -- bar rows: line 2..(N+1), values row: line N+3
  for col = 1, N do
    local hl = (arr[col] == col) and "BogoCorrect" or "BogoWrong"
    local bs = (col - 1) * COL_W
    local be = bs + 2

    for row = 1, arr[col] do
      local li = 2 + (N - row)
      vim.api.nvim_buf_add_highlight(buf, ns, hl, li, bs, be)
    end

    vim.api.nvim_buf_add_highlight(buf, ns, hl, N + 3, bs, be)
  end
end

local TICK_NS   = 14 * 1e6  -- 14ms of shuffling per tick
local RENDER_NS = 1e9        -- render once per second

function M.start()
  math.randomseed(os.time())
  setup_hl()

  local arr = {}
  for i = 1, N do arr[i] = i end
  shuffle(arr)

  local attempts   = 1
  local start_time = os.time()
  local start_hrtime = uv.hrtime()
  local last_render = start_hrtime

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"

  local width = N * COL_W  -- 75
  local height = N + 4     -- 29: header + blank + 25 bar rows + axis + values

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width    = width,
    height   = height,
    col      = math.floor((vim.o.columns - width) / 2),
    row      = math.floor((vim.o.lines - height) / 2),
    style    = "minimal",
    border   = "rounded",
  })

  vim.wo[win].wrap = false
  vim.wo[win].cursorline = false

  render(buf, arr, attempts, start_time, start_hrtime, false)

  local timer = uv.new_timer()

  local function close()
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  vim.keymap.set("n", "q", close, { buffer = buf, noremap = true, silent = true })

  timer:start(0, 16, vim.schedule_wrap(function()
    if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(win) then
      if not timer:is_closing() then timer:stop(); timer:close() end
      return
    end

    -- tight shuffle loop for up to TICK_NS nanoseconds
    local deadline = uv.hrtime() + TICK_NS
    local sorted = false
    repeat
      shuffle(arr)
      attempts = attempts + 1
      if is_sorted(arr) then sorted = true; break end
    until uv.hrtime() >= deadline

    -- render at most once per second
    local now = uv.hrtime()
    if sorted or (now - last_render) >= RENDER_NS then
      render(buf, arr, attempts, start_time, start_hrtime, sorted)
      last_render = now
    end

    if sorted then
      if not timer:is_closing() then timer:stop() end
    end
  end))
end

return M
