-- Task Island integration for CMD via Clink (https://chrisant996.github.io/clink/).
-- Tracks EVERY command typed in cmd.exe, automatically, like the PowerShell profile does.
-- Install: copy this file into your Clink scripts folder (run `clink info` to see it), then open a new CMD.
--
-- No network calls: each event is written as a small JSON file into
-- %TEMP%\claude-island\spool, which the island picks up and deletes.

local spool = (os.getenv("TEMP") or ".") .. "\\claude-island\\spool"
pcall(os.mkdir, spool)

local pid = 0
do local ok, v = pcall(os.getpid); if ok and v then pid = v else pid = math.random(1, 999999) end end

local seq, current = 0, nil

local function esc(s)
  return (tostring(s or ""):gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' elseif c == '\\' then return '\\\\' end
    return string.format("\\u%04x", c:byte())
  end))
end

local function emit(json)
  seq = seq + 1
  local name = string.format("%s\\cmd-%d-%d-%06d.json", spool, pid, os.time(), seq)
  local f = io.open(name .. ".tmp", "w")
  if not f then return end
  f:write(json); f:close()
  os.rename(name .. ".tmp", name) -- island only reads finished *.json files
end

-- Command START: you pressed Enter
clink.onendedit(function(line)
  if line and line:match("%S") then
    current = string.format("cmd-%d-%d", pid, seq + 1)
    emit(string.format('{"phase":"start","id":"%s","source":"cmd","command":"%s","cwd":"%s","pid":%d}',
      current, esc(line), esc(os.getcwd()), pid))
  end
end)

-- Command END: the next prompt is about to show
clink.onbeginedit(function()
  if current then
    local code = 0
    local ok, lvl = pcall(os.geterrorlevel)
    if ok and lvl then code = lvl end
    emit(string.format('{"phase":"end","id":"%s","ok":%s,"exitCode":%d}',
      current, code == 0 and "true" or "false", code))
    current = nil
  end
end)
