local M = {}

local ns = vim.api.nvim_create_namespace("bogosort")
local uv = vim.uv or vim.loop

-- #region agent log
local function dbglog(location, message, data)
  local ok, json = pcall(vim.json.encode, {
    sessionId = "500613",
    location = location,
    message = message,
    data = data,
    timestamp = os.time() * 1000,
  })
  if not ok then return end
  local f = io.open("/Users/sivac0601/code/Bogo/.cursor/debug-500613.log", "a")
  if f then f:write(json .. "\n"); f:close() end
end
-- #endregion

local N = 25
local COL_W = 3 -- "## " per column
local active

local function setup_hl()
  vim.api.nvim_set_hl(0, "BogoCorrect", { fg = "#00FF00", bold = true, default = true })
  vim.api.nvim_set_hl(0, "BogoWrong", { fg = "#FFB347", default = true })
  vim.api.nvim_set_hl(0, "BogoHeader", { fg = "#888888", italic = true, default = true })
  vim.api.nvim_set_hl(0, "BogoSorted", { fg = "#FFD700", bold = true, default = true })
end

vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("BogoSortHighlights", { clear = true }),
  callback = setup_hl,
})

local function is_sorted(arr)
  for i = 1, #arr - 1 do
    if arr[i] > arr[i + 1] then return false end
  end
  return true
end

local function new_random()
  -- Independent Park-Miller state; never seed or consume Neovim's shared RNG.
  local state = (uv.hrtime() % 2147483646) + 1
  return function(limit)
    local value
    repeat
      state = (state * 48271) % 2147483647
      value = state - 1
    until value < math.floor(2147483646 / limit) * limit
    return (value % limit) + 1
  end
end

local function shuffle(arr, random)
  for i = #arr, 2, -1 do
    local j = random(i)
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

local _render_lines = {}
local _render_parts = {}

local function render(buf, arr, attempts, start_time, start_hrtime, done, width, height)
  local elapsed = fmt_time(os.time() - start_time)
  local elapsed_sec = math.max(0.001, (uv.hrtime() - start_hrtime) / 1e9)
  local sps = attempts / elapsed_sec
  local status = done and "*** SORTED! *** (q to close)" or "q to quit"
  local header = string.format(" %s SpS | shuffles: %s | elapsed: %s",
    fmt_attempts(math.floor(sps)), fmt_attempts(attempts), elapsed)
  if #header > width then
    header = string.format(" %s/s | #%s | %s",
      fmt_attempts(math.floor(sps)), fmt_attempts(attempts), elapsed)
  end
  header = header:sub(1, width)
  local col_width = width >= N * COL_W and COL_W or 2
  local bar_rows = height - 4

  local lines = _render_lines
  local parts = _render_parts

  for i = 1, N + 4 do lines[i] = nil end

  lines[1] = header
  lines[2] = " " .. status

  for row = bar_rows, 1, -1 do
    for col = 1, N do
      local filled = math.ceil(arr[col] * bar_rows / N) >= row
      parts[col] = filled and string.rep("#", col_width - 1) .. " " or string.rep(" ", col_width)
    end
    lines[bar_rows - row + 3] = table.concat(parts)
  end

  lines[bar_rows + 3] = string.rep("-", N * col_width)

  for col = 1, N do
    parts[col] = string.format("%-" .. col_width .. "d", arr[col])
  end
  lines[bar_rows + 4] = table.concat(parts)

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  local header_hl = done and "BogoSorted" or "BogoHeader"
  vim.api.nvim_buf_add_highlight(buf, ns, header_hl, 0, 0, -1)
  vim.api.nvim_buf_add_highlight(buf, ns, header_hl, 1, 0, -1)

  for col = 1, N do
    local hl = (arr[col] == col) and "BogoCorrect" or "BogoWrong"
    local bs = (col - 1) * col_width
    for row = 1, math.ceil(arr[col] * bar_rows / N) do
      vim.api.nvim_buf_add_highlight(buf, ns, hl, bar_rows - row + 2, bs, bs + col_width - 1)
    end

    vim.api.nvim_buf_add_highlight(buf, ns, hl, bar_rows + 3, bs, bs + 2)
  end
end

local function window_config()
  local width = math.min(N * COL_W, vim.o.columns - 2)
  local height = math.min(N + 4, vim.o.lines - vim.o.cmdheight - 2)
  if width < N * 2 or height < 5 then return nil end
  return {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width - 2) / 2),
    row = math.floor((vim.o.lines - vim.o.cmdheight - height - 2) / 2),
    style = "minimal",
    border = "rounded",
  }
end

local TICK_NS   = 2 * 1e6    -- bound main-thread work to 2ms every 50ms
local RENDER_NS = 1e9        -- render once per second

function M.start()
  if active then
    if vim.api.nvim_win_is_valid(active.win) then
      vim.api.nvim_set_current_win(active.win)
      return
    end
    active.close()
  end
  local config = window_config()
  if not config then
    vim.notify("BogoSort needs at least 52 columns and 7 rows above the command line", vim.log.levels.WARN)
    return
  end
  -- #region agent log
  dbglog("init.lua:start", "BogoSort started (instrumented build)", { pid = (uv.os_getpid and uv.os_getpid()) or 0 })
  -- #endregion
  setup_hl()

  local random = new_random()
  local arr = {}
  for i = 1, N do arr[i] = i end
  shuffle(arr, random)

  local attempts   = 1
  local start_time = os.time()
  local start_hrtime = uv.hrtime()
  local last_render = start_hrtime

  -- #region agent log
  local last_tick = start_hrtime
  local last_log = start_hrtime
  -- #endregion

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"

  local win = vim.api.nvim_open_win(buf, true, config)

  vim.wo[win].wrap = false
  vim.wo[win].cursorline = false

  local done, closed, pending = false, false, false
  local function redraw()
    render(buf, arr, attempts, start_time, start_hrtime, done, config.width, config.height)
  end
  redraw()
  local timer = uv.new_timer()
  local group = vim.api.nvim_create_augroup("BogoSortSession", { clear = true })

  local function stop_timer()
    if not timer:is_closing() then
      timer:stop()
      timer:close()
    end
  end

  local function cleanup()
    if closed then return end
    closed = true
    stop_timer()
    active = nil
    vim.api.nvim_del_augroup_by_id(group)
  end

  local function close()
    cleanup()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  active = { win = win, close = close }
  vim.api.nvim_create_autocmd("BufWipeout", { group = group, buffer = buf, callback = cleanup })
  vim.api.nvim_create_autocmd("WinClosed", { group = group, pattern = tostring(win), callback = cleanup })
  vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = cleanup })
  local function resize()
    local resized = window_config()
    if not resized then
      close()
      vim.notify("BogoSort closed: editor is too small for the chart", vim.log.levels.WARN)
      return
    end
    config = resized
    vim.api.nvim_win_set_config(win, config)
    redraw()
  end
  vim.api.nvim_create_autocmd("VimResized", { group = group, callback = resize })
  vim.api.nvim_create_autocmd("OptionSet", { group = group, pattern = "cmdheight", callback = resize })
  vim.keymap.set("n", "q", close, { buffer = buf, noremap = true, silent = true })

  local function tick()
    pending = false
    if done or closed then return end
    if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(win) then
      cleanup()
      return
    end

    -- #region agent log
    local tick_enter = uv.hrtime()
    local tick_gap_ms = (tick_enter - last_tick) / 1e6
    last_tick = tick_enter
    local attempts_before = attempts
    -- #endregion

    -- tight shuffle loop for up to TICK_NS nanoseconds
    local deadline = uv.hrtime() + TICK_NS
    local sorted = false
    repeat
      shuffle(arr, random)
      attempts = attempts + 1
      if is_sorted(arr) then sorted = true; break end
    until uv.hrtime() >= deadline

    -- #region agent log
    local loop_ms = (uv.hrtime() - tick_enter) / 1e6
    local iters = attempts - attempts_before
    local render_ms = 0
    -- #endregion

    -- render at most once per second
    local now = uv.hrtime()
    if sorted or (now - last_render) >= RENDER_NS then
      -- #region agent log
      local r0 = uv.hrtime()
      -- #endregion
      done = sorted
      redraw()
      last_render = now
      -- #region agent log
      render_ms = (uv.hrtime() - r0) / 1e6
      -- #endregion
    end

    -- #region agent log
    if (tick_enter - last_log) >= 5e9 then
      last_log = tick_enter
      local elapsed_s = (tick_enter - start_hrtime) / 1e9
      dbglog("init.lua:tick", "tick sample", {
        elapsed_s = elapsed_s,
        tick_gap_ms = tick_gap_ms,      -- H-D: inter-tick wall gap (expect ~50ms)
        loop_ms = loop_ms,              -- H-A/H-E: busy-loop wall duration (expect ~2ms)
        iters_this_tick = iters,        -- H-A/H-B: throughput per tick
        inst_sps = iters / math.max(0.000001, loop_ms / 1000), -- H-B: instantaneous SpS
        cumulative_sps = attempts / math.max(0.001, elapsed_s), -- H-B: displayed lifetime avg
        render_ms = render_ms,          -- H-C: render cost
        attempts = attempts,            -- H-E: magnitude of counter
        hrtime = now,                   -- H-E: magnitude of clock
      })
    end
    -- #endregion

    if sorted then
      stop_timer()
    end
  end

  timer:start(0, 50, function()
    if pending or done or closed then return end
    pending = true
    vim.schedule(tick)
  end)
end

return M
