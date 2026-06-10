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

  local lines = render._lines
  local parts = render._parts

  for i = 1, N + 4 do lines[i] = nil end

  lines[1] = header
  lines[2] = ""

  for row = N, 1, -1 do
    for col = 1, N do
      parts[col] = arr[col] >= row and "## " or "   "
    end
    lines[N - row + 3] = table.concat(parts)
  end

  lines[N + 3] = string.rep("---", N)

  for col = 1, N do
    parts[col] = string.format("%-3d", arr[col])
  end
  lines[N + 4] = table.concat(parts)

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  local header_hl = done and "BogoSorted" or "BogoHeader"
  vim.api.nvim_buf_add_highlight(buf, ns, header_hl, 0, 0, -1)

  for col = 1, N do
    local hl = (arr[col] == col) and "BogoCorrect" or "BogoWrong"
    local bs = (col - 1) * COL_W
    local be = bs + 2

    if arr[col] > 0 then
      vim.api.nvim_buf_set_extmark(buf, ns, 2 + (N - arr[col]), bs, {
        end_row = N + 1,
        end_col = be,
        hl_group = hl,
      })
    end

    vim.api.nvim_buf_set_extmark(buf, ns, N + 3, bs, {
      end_row = N + 4,
      end_col = be,
      hl_group = hl,
    })
  end
end

render._lines = {}
render._parts = {}

local TICK_NS   = 12 * 1e6  -- 12ms shuffle per tick (down from 14ms, more timer slack)
local RENDER_NS = 1e9        -- render once per second

function M.start()
  -- #region agent log
  dbglog("init.lua:start", "BogoSort started (instrumented build)", { pid = (uv.os_getpid and uv.os_getpid()) or 0 })
  -- #endregion
  math.randomseed(os.time())
  setup_hl()

  local arr = {}
  for i = 1, N do arr[i] = i end
  shuffle(arr)

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
      shuffle(arr)
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
      render(buf, arr, attempts, start_time, start_hrtime, sorted)
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
        tick_gap_ms = tick_gap_ms,      -- H-D: inter-tick wall gap (expect ~16ms)
        loop_ms = loop_ms,              -- H-A/H-E: busy-loop wall duration (expect ~12ms)
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
      if not timer:is_closing() then timer:stop() end
    end
  end))
end

return M
