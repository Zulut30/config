local function openOrFocusApp(appName, appPath)
  local names = type(appName) == "table" and appName or {appName}
  for _, name in ipairs(names) do
    local app = hs.application.find(name) or hs.application.get(name)
    if app then
      app:activate(true)
      return
    end
  end

  if appPath then
    hs.execute('open -a "' .. appPath .. '"')
  else
    hs.execute('open -a "' .. names[1] .. '"')
  end
end

local function bind(mods, key, fn)
  hs.hotkey.bind(mods, key, fn)
end

local terminalFontSize = 22
local terminalWidth = 1160
local terminalHeight = 760
local terminalInputSource = "com.apple.keylayout.ABC"

-- Open a new Terminal window with Ctrl+Shift+Z
bind({"ctrl", "shift"}, "z", function()
  local activeWindow = hs.window.frontmostWindow()
  local screen = (activeWindow and activeWindow:screen() or hs.screen.mainScreen()):frame()
  local left = math.floor(screen.x + (screen.w - terminalWidth) / 2)
  local top = math.floor(screen.y + (screen.h - terminalHeight) / 2)
  local right = left + terminalWidth
  local bottom = top + terminalHeight
  local script = string.format([[
    tell application "Terminal"
      activate
      if (count of windows) is 0 then
        do script ""
      end if
      set font size of selected tab of front window to %d
      set bounds of front window to {%d, %d, %d, %d}
    end tell
  ]], terminalFontSize, left, top, right, bottom)
  hs.osascript.applescript(script)
  hs.keycodes.currentSourceID(terminalInputSource)
end)

-- Open/focus Codex with Ctrl+Shift+A
bind({"ctrl", "shift"}, "a", function()
  openOrFocusApp("ChatGPT", "/Applications/ChatGPT.app")
end)

-- Open/focus Brave with Ctrl+Shift+S
bind({"ctrl", "shift"}, "s", function()
  openOrFocusApp("Brave Browser", "/Applications/Brave Browser.app")
end)

local codexQuotaFile = os.getenv("HOME") .. "/Library/Caches/CodexQuota/status.json"
local codexQuotaMenu = hs.menubar.new()

local function resetText(timestamp)
  if not timestamp then return "время неизвестно" end
  local seconds = math.max(0, timestamp - os.time())
  local days = math.floor(seconds / 86400)
  local hours = math.floor((seconds % 86400) / 3600)
  local minutes = math.floor((seconds % 3600) / 60)
  local relative = days > 0 and ("через " .. days .. " д. " .. hours .. " ч.")
    or hours > 0 and ("через " .. hours .. " ч. " .. minutes .. " мин.")
    or ("через " .. minutes .. " мин.")
  return os.date("%d.%m %H:%M", timestamp) .. " (" .. relative .. ")"
end

local function durationText(seconds)
  local hours = math.floor(seconds / 3600)
  local minutes = math.floor((seconds % 3600) / 60)
  return hours > 0 and (hours .. " ч. " .. minutes .. " мин.") or (minutes .. " мин.")
end

local function tokenText(tokens)
  if tokens >= 1000000 then
    return string.format("%.1f млн", tokens / 1000000)
  end
  if tokens >= 1000 then
    return string.format("%.1f тыс.", tokens / 1000)
  end
  return tostring(tokens)
end

local function friendlyModelName(name)
  local names = {
    ["gpt-6-astra"] = "Astra",
    ["gpt-5.6-terra"] = "Terra",
    ["gpt-5.6-luna"] = "Luna",
    ["gpt-5.3-codex-spark"] = "Spark",
    ["GPT-5.3-Codex-Spark"] = "Spark",
    ["Codex"] = "Codex",
  }
  return names[name] or name
end

local function isSparkModel(name)
  return name == "gpt-5.3-codex-spark" or name == "GPT-5.3-Codex-Spark"
end

local function visibleTaskStats(stats)
  local ranked = {}
  local totalTokens = 0
  local totalTasks = 0
  for _, stat in ipairs(stats) do
    if stat.model ~= "gpt-5.3-codex-spark" and stat.model ~= "GPT-5.3-Codex-Spark" then
      table.insert(ranked, stat)
      totalTokens = totalTokens + (stat.outputTokens or 0)
      totalTasks = totalTasks + (stat.completedTasks or 0)
    end
  end
  table.sort(ranked, function(a, b)
    if (a.outputTokens or 0) == (b.outputTokens or 0) then
      return (a.activeSeconds or 0) > (b.activeSeconds or 0)
    end
    return (a.outputTokens or 0) > (b.outputTokens or 0)
  end)
  return ranked, totalTokens, totalTasks
end

local function openCodexQuotaDashboard()
  hs.execute("/usr/bin/open -n '/Users/zulut/Applications/Codex Quota.app' --args --show-dashboard")
end

local function infoItem(title)
  return {title = title, fn = function() end}
end

local function refreshCodexQuota()
  local quota = hs.json.read(codexQuotaFile)
  if quota and quota.remainingPercent then
    local remaining = math.max(0, math.min(100, tonumber(quota.remainingPercent) or 0))
    local percent = tostring(remaining) .. "%"
    local items = {
      {title = "Открыть полную панель Codex Quota", fn = openCodexQuotaDashboard},
      {title = "-"},
      infoItem("НЕДЕЛЬНЫЙ ЛИМИТ CODEX"),
      infoItem(percent .. " осталось  ·  " .. tostring(100 - remaining) .. "% использовано"),
      infoItem("Сброс: " .. resetText(quota.primaryResetAt) .. "  ·  Ручных: " .. tostring(quota.resetCreditCount or 0)),
      {title = "-"},
      infoItem("РАСХОД ЗА 7 ДНЕЙ"),
      infoItem("Доля по сгенерированным токенам, Spark скрыт"),
    }

    local taskStats, totalTokens, totalTasks = visibleTaskStats(quota.taskStats or {})
    if #taskStats == 0 then
      table.insert(items, infoItem("Данные о задачах ещё собираются"))
    end
    for _, stat in ipairs(taskStats) do
      local share = totalTokens > 0 and math.floor(((stat.outputTokens or 0) / totalTokens) * 100 + 0.5) or 0
      table.insert(items, infoItem(
        friendlyModelName(stat.model)
          .. "  " .. tostring(share) .. "%"
          .. "  ·  " .. tokenText(stat.outputTokens or 0)
          .. "  ·  " .. tostring(stat.completedTasks or 0) .. " задач"
          .. "  ·  " .. durationText(stat.activeSeconds or 0)
      ))
    end

    for _, stat in ipairs(taskStats) do
      if stat.model == "gpt-6-astra" and (stat.completedTasks or 0) > 0 and totalTasks > 0 then
        local astraPerTask = (stat.outputTokens or 0) / stat.completedTasks
        local averagePerTask = totalTokens / totalTasks
        local ratio = averagePerTask > 0 and astraPerTask / averagePerTask or 0
        table.insert(items, {title = "-"})
        table.insert(items, infoItem("ASTRA: " .. tokenText(astraPerTask) .. " на задачу  ·  " .. string.format("%.1fx", ratio) .. " от среднего"))
      end
    end

    if quota.updatedAt then
      table.insert(items, infoItem("Обновлено: " .. os.date("%d.%m %H:%M", quota.updatedAt)))
    end

    codexQuotaMenu:setTitle(percent)
    codexQuotaMenu:setTooltip("Codex: осталось " .. percent .. " недельного лимита")
    codexQuotaMenu:setMenu(items)
  else
    codexQuotaMenu:setTitle("--")
    codexQuotaMenu:setTooltip("Codex: ожидаю первое обновление лимита")
    codexQuotaMenu:setMenu({
      infoItem("Codex Quota ещё не получил лимит"),
    })
  end
end

refreshCodexQuota()
hs.timer.doEvery(60, refreshCodexQuota)
