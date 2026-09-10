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

local codexQuotaPanel = nil

local function htmlEscape(value)
  local escaped = tostring(value or "")
  escaped = escaped:gsub("&", "&amp;")
  escaped = escaped:gsub("<", "&lt;")
  escaped = escaped:gsub(">", "&gt;")
  escaped = escaped:gsub('"', "&quot;")
  return escaped
end

local function modelAccent(name)
  if name == "gpt-6-astra" then return "#ffbf62" end
  if name == "gpt-5.6-terra" then return "#65e1b0" end
  if name == "gpt-5.6-luna" then return "#69a9ff" end
  return "#e28bff"
end

local function quotaPanelHTML(quota)
  if not quota or not quota.remainingPercent then
    return [[
      <!doctype html>
      <html><body style="margin:0;background:#0b1420;color:#f7fbff;font:600 16px 'Avenir Next',sans-serif;display:grid;place-items:center;height:100vh">
        Данные лимита ещё загружаются
      </body></html>
    ]]
  end

  local remaining = math.max(0, math.min(100, tonumber(quota.remainingPercent) or 0))
  local taskStats, totalTokens, totalTasks = visibleTaskStats(quota.taskStats or {})
  local cards = {}
  local astra = nil

  for _, stat in ipairs(taskStats) do
    local tokens = stat.outputTokens or 0
    local tasks = stat.completedTasks or 0
    local share = totalTokens > 0 and math.floor((tokens / totalTokens) * 100 + 0.5) or 0
    local name = htmlEscape(friendlyModelName(stat.model))
    cards[#cards + 1] =
      [[<article class="model-card">
          <div class="model-row">
            <div class="model-name"><span class="dot" style="background:]] .. modelAccent(stat.model) .. [["></span>]] .. name .. [[</div>
            <strong>]] .. tostring(share) .. [[%</strong>
          </div>
          <div class="bar"><i style="width:]] .. tostring(share) .. [[%;background:]] .. modelAccent(stat.model) .. [["></i></div>
          <div class="model-meta">]] .. tokenText(tokens) .. [[ токенов <b>·</b> ]] .. tostring(tasks) .. [[ задач <b>·</b> ]] .. durationText(stat.activeSeconds or 0) .. [[</div>
        </article>]]

    if stat.model == "gpt-6-astra" then
      astra = {tokens = tokens, tasks = tasks}
    end
  end

  local astraTitle = "Astra: данных пока мало"
  local astraDetail = "После нескольких завершённых задач появится сравнение со средним расходом."
  local astraTone = "neutral"
  if astra and astra.tasks > 0 and totalTasks > 0 then
    local perTask = astra.tokens / astra.tasks
    local average = totalTokens / totalTasks
    local ratio = average > 0 and perTask / average or 0
    if ratio >= 1.5 then
      astraTitle = "Astra заметно дороже средней"
      astraTone = "high"
    elseif ratio >= 1.15 then
      astraTitle = "Astra немного дороже средней"
      astraTone = "medium"
    else
      astraTitle = "Astra близка к среднему расходу"
      astraTone = "good"
    end
    astraDetail = tokenText(perTask) .. " токенов на задачу, " .. string.format("%.1fx", ratio) .. " от твоего среднего. Используй Astra для сложных задач, где она экономит время на переделках."
  end

  local updated = quota.updatedAt and os.date("%d.%m %H:%M", quota.updatedAt) or "сейчас"
  return [[<!doctype html>
    <html lang="ru">
    <head>
      <meta charset="utf-8">
      <style>
        * { box-sizing:border-box; }
        body {
          margin:0; min-height:100vh; color:#f6f8fb;
          background:radial-gradient(circle at 84% 0%, #173c47 0, transparent 34%), linear-gradient(145deg,#07111d,#0c1d2b);
          font-family:"Avenir Next","Helvetica Neue",sans-serif;
        }
        .wrap { padding:30px 34px 28px; }
        .eyebrow { color:#72e4b7; font-size:11px; font-weight:800; letter-spacing:2px; }
        h1 { margin:5px 0 25px; font-size:28px; letter-spacing:-.8px; }
        .hero {
          display:grid; grid-template-columns:170px 1fr; gap:26px; align-items:center;
          padding:25px; border-radius:24px;
          background:linear-gradient(135deg,rgba(27,82,79,.9),rgba(16,44,66,.9));
          border:1px solid rgba(255,255,255,.12);
        }
        .ring {
          width:142px; height:142px; border-radius:50%; display:grid; place-items:center;
          background:conic-gradient(#68e3b0 var(--progress),rgba(255,255,255,.12) 0);
        }
        .ring > div {
          width:116px; height:116px; border-radius:50%; display:grid; place-items:center;
          background:#102b3b; text-align:center;
        }
        .ring strong { display:block; font-size:37px; letter-spacing:-2px; }
        .ring span { color:#9ab5be; font-size:11px; font-weight:700; text-transform:uppercase; letter-spacing:1px; }
        .hero h2 { margin:0 0 12px; font-size:24px; letter-spacing:-.5px; }
        .hero p { margin:6px 0; color:#c5d6dc; font-size:14px; }
        .hero p b { color:#fff; }
        .section { margin-top:22px; }
        .section-head { display:flex; justify-content:space-between; align-items:baseline; margin-bottom:10px; }
        .section-head h3 { margin:0; font-size:12px; letter-spacing:1.5px; color:#72e4b7; }
        .section-head span { font-size:12px; color:#8198a2; }
        .models { display:grid; grid-template-columns:repeat(3,1fr); gap:10px; }
        .model-card { padding:15px; border-radius:17px; background:rgba(255,255,255,.055); border:1px solid rgba(255,255,255,.06); }
        .model-row { display:flex; justify-content:space-between; align-items:center; font-size:15px; }
        .model-name { font-weight:800; }
        .dot { width:8px; height:8px; display:inline-block; border-radius:50%; margin-right:7px; }
        .bar { height:7px; overflow:hidden; margin:15px 0 10px; border-radius:99px; background:rgba(255,255,255,.09); }
        .bar i { display:block; height:100%; border-radius:99px; }
        .model-meta { color:#a9bdc5; font-size:11px; line-height:1.45; }
        .model-meta b { color:#5e7580; padding:0 2px; }
        .astra {
          margin-top:16px; padding:18px 20px; border-radius:18px;
          background:rgba(255,191,98,.1); border:1px solid rgba(255,191,98,.23);
        }
        .astra-label { color:#ffbf62; font-size:11px; font-weight:800; letter-spacing:1.4px; }
        .astra h3 { margin:5px 0 5px; font-size:19px; letter-spacing:-.35px; }
        .astra p { margin:0; color:#c6d2d7; font-size:13px; line-height:1.5; }
        .footer { margin-top:19px; color:#718995; font-size:11px; }
        @media (max-width:620px) { .hero { grid-template-columns:1fr; } .models { grid-template-columns:1fr; } .ring { margin:auto; } }
      </style>
    </head>
    <body>
      <main class="wrap">
        <div class="eyebrow">CODEX QUOTA</div>
        <h1>Лимиты и цена моделей</h1>
        <section class="hero">
          <div class="ring" style="--progress:]] .. tostring(remaining) .. [[%"><div><strong>]] .. tostring(remaining) .. [[%</strong><span>осталось</span></div></div>
          <div>
            <h2>Недельный запас</h2>
            <p><b>]] .. tostring(100 - remaining) .. [[%</b> уже использовано</p>
            <p>Сброс: <b>]] .. htmlEscape(resetText(quota.primaryResetAt)) .. [[</b></p>
            <p>Ручные сбросы: <b>]] .. tostring(quota.resetCreditCount or 0) .. [[</b></p>
          </div>
        </section>
        <section class="section">
          <div class="section-head"><h3>КУДА УХОДЯТ РЕСУРСЫ</h3><span>за 7 дней, без Spark</span></div>
          <div class="models">]] .. table.concat(cards) .. [[</div>
        </section>
        <section class="astra ]] .. astraTone .. [[">
          <div class="astra-label">ЭКОНОМИКА ASTRA</div>
          <h3>]] .. htmlEscape(astraTitle) .. [[</h3>
          <p>]] .. htmlEscape(astraDetail) .. [[</p>
        </section>
        <div class="footer">Обновлено ]] .. updated .. [[. Расход измеряется по сгенерированным токенам и не является автоматической оценкой качества результата.</div>
      </main>
    </body>
    </html>]]
end

local function showCodexQuotaPanel()
  local quota = hs.json.read(codexQuotaFile)
  local screen = hs.screen.mainScreen():visibleFrame()
  local width = math.min(780, screen.w - 48)
  local height = math.min(610, screen.h - 80)
  local frame = {
    x = screen.x + (screen.w - width) / 2,
    y = screen.y + (screen.h - height) / 2,
    w = width,
    h = height,
  }

  if not codexQuotaPanel then
    codexQuotaPanel = hs.webview.newBrowser(frame, {privateBrowsing = true})
      :allowNewWindows(false)
      :closeOnEscape(true)
      :windowTitle("Codex Quota")
      :shadow(true)
  else
    codexQuotaPanel:frame(frame)
  end

  codexQuotaPanel:html(quotaPanelHTML(quota))
  codexQuotaPanel:show()
  codexQuotaPanel:bringToFront(false)
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
    codexQuotaMenu:setMenu(nil)
    codexQuotaMenu:setClickCallback(showCodexQuotaPanel)
  else
    codexQuotaMenu:setTitle("--")
    codexQuotaMenu:setTooltip("Codex: ожидаю первое обновление лимита")
    codexQuotaMenu:setMenu(nil)
    codexQuotaMenu:setClickCallback(showCodexQuotaPanel)
  end
end

refreshCodexQuota()
hs.timer.doEvery(60, refreshCodexQuota)
