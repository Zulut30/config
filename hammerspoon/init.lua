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

function showCodexQuotaPanel()
  local quota = hs.json.read(codexQuotaFile)
  local screen = hs.screen.mainScreen():frame()
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

-- Clean macOS-style dashboard. Keep data collection and menu bar behavior intact.
local efficiencyHistoryPath = os.getenv("HOME") .. "/Library/Caches/CodexQuota/efficiency-history.json"
local efficiencyStatusPath = os.getenv("HOME") .. "/Library/Caches/CodexQuota/status.json"
local modelQualityPath = os.getenv("HOME") .. "/Library/Caches/CodexQuota/model-quality.json"
local modelQualityScriptPath = os.getenv("HOME") .. "/.hammerspoon/codex_model_quality.py"
local modelFeedbackPath = os.getenv("HOME") .. "/Library/Caches/CodexQuota/model-feedback.json"

local function readQuotaJSON(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()
    local ok, value = pcall(hs.json.decode, content)
    if ok and type(value) == "table" then
        return value
    end
    return nil
end

local function writeQuotaJSON(path, value)
    local encoded = hs.json.encode(value)
    if not encoded then
        return false
    end
    local file = io.open(path, "w")
    if not file then
        return false
    end
    file:write(encoded)
    file:close()
    return true
end

hs.urlevent.bind("codexQuotaFeedback", function(_, params)
    local turnId = tostring(params.turn or "")
    local model = tostring(params.model or "")
    local verdict = tostring(params.verdict or "")
    if turnId == "" or model == "" or (verdict ~= "good" and verdict ~= "rework") then
        return
    end

    local feedback = readQuotaJSON(modelFeedbackPath) or {
        version = 1,
        records = {},
    }
    feedback.records = feedback.records or {}

    local replaced = false
    for _, record in ipairs(feedback.records) do
        if record.turnId == turnId then
            record.model = model
            record.verdict = verdict
            record.timestamp = os.time()
            replaced = true
            break
        end
    end

    if not replaced then
        table.insert(feedback.records, {
            turnId = turnId,
            model = model,
            verdict = verdict,
            timestamp = os.time(),
        })
    end

    writeQuotaJSON(modelFeedbackPath, feedback)
    hs.execute(string.format(
        "/usr/bin/python3 %q >/dev/null 2>&1 &",
        modelQualityScriptPath
    ))
    hs.alert.show(verdict == "good" and "Результат учтён" or "Переделка учтена")

    hs.timer.doAfter(1.2, function()
        local status = readQuotaJSON(efficiencyStatusPath)
        if status and codexQuotaPanel then
            codexQuotaPanel:html(quotaPanelHTML(status))
        end
    end)
end)

local function recordModelEfficiency(status)
    if type(status) ~= "table" or type(status.taskStats) ~= "table" then
        return
    end

    local timestamp = tonumber(status.updatedAt) or os.time()
    local history = readQuotaJSON(efficiencyHistoryPath) or {
        version = 1,
        startedAt = timestamp,
        days = {},
        points = {},
    }

    history.days = history.days or {}
    history.points = history.points or {}
    history.startedAt = history.startedAt or timestamp

    if history.lastSnapshot and tonumber(history.lastSnapshot.timestamp) == timestamp then
        return
    end

    local currentModels = {}
    local totalTokens = 0
    local totalTasks = 0

    for _, item in ipairs(status.taskStats) do
        local name = tostring(item.model or "")
        if name ~= "" and not string.find(string.lower(name), "spark", 1, true) then
            local tokens = tonumber(item.outputTokens) or 0
            local tasks = tonumber(item.completedTasks) or 0
            local seconds = tonumber(item.activeSeconds) or 0
            currentModels[name] = {
                tokens = tokens,
                tasks = tasks,
                seconds = seconds,
            }
            totalTokens = totalTokens + tokens
            totalTasks = totalTasks + tasks
        end
    end

    local averagePerTask = totalTasks > 0 and totalTokens / totalTasks or 0
    local pointModels = {}
    for name, item in pairs(currentModels) do
        local perTask = item.tasks > 0 and item.tokens / item.tasks or 0
        local ratio = averagePerTask > 0 and perTask / averagePerTask or 0
        pointModels[name] = {
            index = ratio > 0 and math.floor((1 / ratio) * 100 + 0.5) or 0,
            tokensPerTask = perTask,
            tasksPerHour = item.seconds > 0 and item.tasks / (item.seconds / 3600) or 0,
            tasks = item.tasks,
        }
    end

    if history.lastSnapshot and type(history.lastSnapshot.models) == "table" then
        local dayKey = os.date("%Y-%m-%d", timestamp)
        local day = history.days[dayKey] or {
            timestamp = timestamp,
            models = {},
        }
        day.models = day.models or {}

        for name, current in pairs(currentModels) do
            local previous = history.lastSnapshot.models[name]
            if previous then
                local deltaTokens = current.tokens - (tonumber(previous.tokens) or 0)
                local deltaTasks = current.tasks - (tonumber(previous.tasks) or 0)
                local deltaSeconds = current.seconds - (tonumber(previous.seconds) or 0)

                if deltaTokens >= 0 and deltaTasks >= 0 and deltaSeconds >= 0 then
                    local modelDay = day.models[name] or {
                        tokens = 0,
                        tasks = 0,
                        seconds = 0,
                    }
                    modelDay.tokens = modelDay.tokens + deltaTokens
                    modelDay.tasks = modelDay.tasks + deltaTasks
                    modelDay.seconds = modelDay.seconds + deltaSeconds
                    day.models[name] = modelDay
                end
            end
        end

        history.days[dayKey] = day
    end

    table.insert(history.points, {
        timestamp = timestamp,
        models = pointModels,
    })

    while #history.points > 192 do
        table.remove(history.points, 1)
    end

    local cutoff = os.time() - (30 * 86400)
    for key, day in pairs(history.days) do
        if (tonumber(day.timestamp) or 0) < cutoff then
            history.days[key] = nil
        end
    end

    history.lastSnapshot = {
        timestamp = timestamp,
        models = currentModels,
    }
    writeQuotaJSON(efficiencyHistoryPath, history)
end

quotaPanelHTML = function(data)
    data = data or {}
    recordModelEfficiency(data)
    local efficiencyHistory = readQuotaJSON(efficiencyHistoryPath) or {}
    local modelQuality = readQuotaJSON(modelQualityPath) or {}
    local qualityByModel = {}
    for _, item in ipairs(modelQuality.models or {}) do
        qualityByModel[tostring(item.name or "")] = item
    end

    local bestModel = nil
    local bestEconomy = nil
    local bestSpeed = nil
    for _, item in ipairs(modelQuality.models or {}) do
        local confidence = tonumber(item.confidence) or 0
        if confidence >= 25 then
            if not bestModel or (tonumber(item.score) or 0) > (tonumber(bestModel.score) or 0) then
                bestModel = item
            end
            if not bestEconomy
                or (tonumber(item.efficiencyScore) or 0) > (tonumber(bestEconomy.efficiencyScore) or 0)
            then
                bestEconomy = item
            end
            if not bestSpeed
                or (tonumber(item.speedScore) or 0) > (tonumber(bestSpeed.speedScore) or 0)
            then
                bestSpeed = item
            end
        end
    end

    local function clamp(value, minimum, maximum)
        value = tonumber(value) or 0
        return math.max(minimum, math.min(maximum, value))
    end

    local function formatTokens(value)
        value = tonumber(value) or 0
        if value >= 1000000 then
            return string.format("%.1f млн", value / 1000000)
        end
        if value >= 1000 then
            return string.format("%.1f тыс.", value / 1000)
        end
        return tostring(math.floor(value))
    end

    local function formatDuration(value)
        value = tonumber(value) or 0
        local hours = math.floor(value / 3600)
        local minutes = math.floor((value % 3600) / 60)
        if hours > 0 then
            return string.format("%d ч %02d мин", hours, minutes)
        end
        return string.format("%d мин", math.max(1, minutes))
    end

    local function formatReset(timestamp)
        timestamp = tonumber(timestamp)
        if not timestamp then
            return "Нет данных"
        end
        local remaining = math.max(0, timestamp - os.time())
        local days = math.floor(remaining / 86400)
        local hours = math.floor((remaining % 86400) / 3600)
        return os.date("%d.%m, %H:%M", timestamp)
            .. string.format(" · через %d д. %d ч.", days, hours)
    end

    local remaining = clamp(data.remainingPercent, 0, 100)
    local used = 100 - remaining
    local resetText = formatReset(data.primaryResetAt)
    local resetCredits = tonumber(data.resetCreditCount) or 0
    local updatedText = data.updatedAt and os.date("%H:%M", tonumber(data.updatedAt)) or "нет данных"

    local models = {}
    local totalTokens = 0
    local totalTasks = 0
    local totalSeconds = 0

    for _, item in ipairs(data.taskStats or {}) do
        local modelName = tostring(item.model or "")
        if not string.find(string.lower(modelName), "spark", 1, true) then
            local tokens = tonumber(item.outputTokens) or 0
            local tasks = tonumber(item.completedTasks) or 0
            local seconds = tonumber(item.activeSeconds) or 0
            table.insert(models, {
                name = modelName,
                tokens = tokens,
                tasks = tasks,
                seconds = seconds,
            })
            totalTokens = totalTokens + tokens
            totalTasks = totalTasks + tasks
            totalSeconds = totalSeconds + seconds
        end
    end

    table.sort(models, function(a, b)
        return a.tokens > b.tokens
    end)

    local colors = { "#2E9B78", "#E99A3E", "#527FD7", "#C4688B", "#7C6BB4" }
    local modelRows = {}
    local compositionSegments = {}
    local averagePerTask = totalTasks > 0 and totalTokens / totalTasks or 0

    local function buildSparkline(modelName, color, currentIndex)
        local values = {}
        for _, point in ipairs(efficiencyHistory.points or {}) do
            local modelPoint = point.models and point.models[modelName]
            local value = modelPoint and tonumber(modelPoint.index)
            if value and value > 0 then
                table.insert(values, value)
            end
        end

        if #values == 0 then
            table.insert(values, currentIndex)
        end

        while #values > 24 do
            table.remove(values, 1)
        end

        local coordinates = {}
        local lastX = 120
        local lastY = 14
        local count = #values

        for index, value in ipairs(values) do
            local x = count > 1 and ((index - 1) / (count - 1)) * 120 or 120
            local normalized = (math.max(50, math.min(150, value)) - 50) / 100
            local y = 26 - (normalized * 22)
            table.insert(coordinates, string.format("%.1f,%.1f", x, y))
            lastX = x
            lastY = y
        end

        if count == 1 then
            table.insert(coordinates, 1, string.format("0,%.1f", lastY))
        end

        local changeText = "сбор истории"
        local changeClass = "flat"
        if count > 1 then
            local change = values[count] - values[1]
            if change > 0 then
                changeText = string.format("+%d п.", change)
                changeClass = "up"
            elseif change < 0 then
                changeText = string.format("%d п.", change)
                changeClass = "down"
            else
                changeText = "без изменений"
            end
        end

        return string.format([[
            <div class="history-line">
                <div class="spark-wrap">
                    <svg class="sparkline" viewBox="0 0 120 28" preserveAspectRatio="none" aria-label="История индекса эффективности">
                        <line x1="0" y1="15" x2="120" y2="15"></line>
                        <polyline points="%s" style="stroke:%s"></polyline>
                        <circle cx="%.1f" cy="%.1f" r="2.4" style="fill:%s"></circle>
                    </svg>
                </div>
                <span class="history-change %s">%s</span>
            </div>
        ]],
            table.concat(coordinates, " "),
            color,
            lastX,
            lastY,
            color,
            changeClass,
            changeText
        )
    end

    for index, item in ipairs(models) do
        local share = totalTokens > 0 and math.floor((item.tokens / totalTokens) * 100 + 0.5) or 0
        local color = colors[((index - 1) % #colors) + 1]
        local safeName = htmlEscape(item.name)
        local perTask = item.tasks > 0 and item.tokens / item.tasks or 0
        local tasksPerHour = item.seconds > 0 and item.tasks / (item.seconds / 3600) or 0
        local ratio = averagePerTask > 0 and perTask / averagePerTask or 0
        local efficiencyIndex = ratio > 0 and math.floor((1 / ratio) * 100 + 0.5) or 0
        local meterWidth = clamp(efficiencyIndex / 1.5, 3, 100)
        local difference = math.floor(math.abs(ratio - 1) * 100 + 0.5)
        local verdictClass = "average"
        local verdict = "на уровне среднего"

        if item.tasks < 5 then
            verdictClass = "sample"
            verdict = "мало данных"
        elseif ratio <= 0.95 then
            verdictClass = "good"
            verdict = string.format("на %d%% экономнее", difference)
        elseif ratio >= 1.05 then
            verdictClass = "watch"
            verdict = string.format("на %d%% ресурсоёмче", difference)
        end

        local sparklineHTML = buildSparkline(item.name, color, efficiencyIndex)
        local quality = qualityByModel[item.name]
        local qualityHTML = [[
            <div class="quality-block quality-pending">
                <div>
                    <span class="quality-label">Качество результата</span>
                    <strong>Собираю сигналы</strong>
                </div>
                <span class="quality-confidence">нужна история</span>
            </div>
        ]]

        if quality then
            local score = tonumber(quality.score) or 0
            local confidence = tonumber(quality.confidence) or 0
            local firstPass = quality.firstPassRate ~= nil
                and (tostring(math.floor(tonumber(quality.firstPassRate) or 0)) .. "%")
                or "—"
            local toolSuccess = quality.toolSuccessRate ~= nil
                and (tostring(math.floor(tonumber(quality.toolSuccessRate) or 0)) .. "%")
                or "—"
            local acceptedCost = tonumber(quality.tokensPerAcceptedResult) or 0
            local reworkShare = tonumber(quality.reworkTokenShare) or 0
            local qualityClass = "quality-average"
            local qualityVerdict = "стабильно"

            if confidence < 25 then
                qualityClass = "quality-sample"
                qualityVerdict = "низкая уверенность"
            elseif score >= 80 then
                qualityClass = "quality-good"
                qualityVerdict = "сильный результат"
            elseif score < 65 then
                qualityClass = "quality-watch"
                qualityVerdict = "нужна проверка"
            end

            qualityHTML = string.format([[
                <div class="quality-block %s">
                    <div class="quality-score">
                        <span class="quality-label">Справляется</span>
                        <div><strong>%d</strong><small>/100</small></div>
                    </div>
                    <div class="quality-signals">
                        <span>С первой попытки <b>%s</b></span>
                        <span>Принятый результат <b>%s</b></span>
                        <span>Переделки <b>%d%%</b></span>
                    </div>
                    <div class="quality-state">
                        <b>%s</b>
                        <span>уверенность %d%%</span>
                    </div>
                </div>
            ]],
                qualityClass,
                score,
                firstPass,
                formatTokens(acceptedCost),
                reworkShare,
                qualityVerdict,
                confidence
            )
        end

        table.insert(compositionSegments, string.format(
            '<span style="width:%d%%;background:%s" title="%s: %d%%"></span>',
            share,
            color,
            safeName,
            share
        ))

        table.insert(modelRows, string.format([[
            <article class="model-row">
                <div class="model-head">
                    <div class="model-name">
                        <span class="model-dot" style="background:%s"></span>
                        <strong>%s</strong>
                    </div>
                    <span class="model-share">%d%%</span>
                </div>
                <div class="track"><span style="width:%d%%;background:%s"></span></div>
                <div class="model-summary">%s токенов · %d задач · %s</div>
                %s
                <div class="efficiency-block">
                    <div class="efficiency-head">
                        <div class="efficiency-index">
                            <b>%d</b>
                            <span>экономичность</span>
                        </div>
                        <span class="efficiency-verdict %s">%s</span>
                    </div>
                    <div class="efficiency-track">
                        <span style="width:%.1f%%;background:%s"></span>
                        <i></i>
                    </div>
                    %s
                    <div class="efficiency-metrics">
                        <span><b>%s</b> / задача</span>
                        <span><b>%.1f</b> задач / час</span>
                    </div>
                </div>
            </article>
        ]],
            color,
            safeName,
            share,
            share,
            color,
            formatTokens(item.tokens),
            item.tasks,
            formatDuration(item.seconds),
            qualityHTML,
            efficiencyIndex,
            verdictClass,
            verdict,
            meterWidth,
            color,
            sparklineHTML,
            formatTokens(perTask),
            tasksPerHour
        ))
    end

    local trackingSince = efficiencyHistory.startedAt
        and os.date("%d.%m, %H:%M", tonumber(efficiencyHistory.startedAt))
        or "сейчас"

    local recommendationHTML = [[
        <div class="decision-empty">
            Рекомендация появится после накопления нескольких задач.
        </div>
    ]]

    if bestModel then
        local latest = modelQuality.latestUnrated
        local feedbackHTML = [[
            <div class="feedback-done">
                <span>Прямая оценка</span>
                <b>Новых результатов для оценки нет</b>
            </div>
        ]]

        if latest and latest.turnId and latest.model then
            local taskTime = latest.startedAt
                and os.date("%d.%m %H:%M", tonumber(latest.startedAt))
                or ""
            feedbackHTML = string.format([[
                <div class="feedback-box">
                    <div class="feedback-copy">
                        <span>ОЦЕНИТЬ ПОСЛЕДНИЙ РЕЗУЛЬТАТ · %s · %s</span>
                        <p>%s</p>
                    </div>
                    <div class="feedback-actions">
                        <a class="feedback-good" href="hammerspoon://codexQuotaFeedback?turn=%s&amp;model=%s&amp;verdict=good">Подошло</a>
                        <a class="feedback-rework" href="hammerspoon://codexQuotaFeedback?turn=%s&amp;model=%s&amp;verdict=rework">Нужна переделка</a>
                    </div>
                </div>
            ]],
                htmlEscape(tostring(latest.model)),
                taskTime,
                htmlEscape(tostring(latest.promptPreview or "Последняя задача")),
                tostring(latest.turnId),
                tostring(latest.model),
                tostring(latest.turnId),
                tostring(latest.model)
            )
        end

        recommendationHTML = string.format([[
            <div class="decision-main">
                <span class="decision-eyebrow">ЛУЧШИЙ ВЫБОР ПО ТВОЕЙ ИСТОРИИ</span>
                <div class="decision-title">
                    <h2>%s</h2>
                    <span>%d/100</span>
                </div>
                <p>Уверенность %d%% · %d задач за 30 дней</p>
            </div>
            <div class="decision-metrics">
                <div><span>Результат</span><b>%d</b></div>
                <div><span>Цена результата</span><b>%s</b></div>
                <div><span>Скорость</span><b>%d</b></div>
            </div>
            <div class="decision-alternatives">
                <span>Экономнее <b>%s</b></span>
                <span>Быстрее <b>%s</b></span>
            </div>
            %s
        ]],
            htmlEscape(tostring(bestModel.name or "")),
            tonumber(bestModel.score) or 0,
            tonumber(bestModel.confidence) or 0,
            tonumber(bestModel.tasks) or 0,
            tonumber(bestModel.outcomeScore) or 0,
            formatTokens(tonumber(bestModel.tokensPerAcceptedResult) or 0),
            tonumber(bestModel.speedScore) or 0,
            htmlEscape(tostring(bestEconomy and bestEconomy.name or "—")),
            htmlEscape(tostring(bestSpeed and bestSpeed.name or "—")),
            feedbackHTML
        )
    end

    local efficiencyHTML = string.format([[
        <div class="method-mark">Q</div>
        <div class="method-copy">
            <span class="eyebrow">РЕЙТИНГ «КАК СПРАВЛЯЕТСЯ»</span>
            <h3>Результат 70%% · экономичность 20%% · скорость 10%%</h3>
            <p>Главный сигнал — отсутствие переделки после финального ответа. Уверенность растёт с числом задач и реакций. История расхода ведётся с %s.</p>
        </div>
        <div class="method-scale">
            <span class="scale-good">80+ сильный результат</span>
            <span class="scale-average">65–79 стабильно</span>
            <span class="scale-watch">&lt;65 проверить</span>
        </div>
    ]], trackingSince)

    local categoryCards = {}
    for _, item in ipairs(modelQuality.categoryRecommendations or {}) do
        table.insert(categoryCards, string.format([[
            <article class="category-item">
                <span>%s</span>
                <strong>%s</strong>
                <div>
                    <b>%d/100</b>
                    <small>%d%% уверенность · %s токенов</small>
                </div>
            </article>
        ]],
            htmlEscape(tostring(item.label or "")),
            htmlEscape(tostring(item.model or "")),
            tonumber(item.score) or 0,
            tonumber(item.confidence) or 0,
            formatTokens(tonumber(item.acceptedCost) or 0)
        ))
    end

    local categoryHTML = table.concat(categoryCards)
    if categoryHTML == "" then
        categoryHTML = '<div class="category-empty">Категорий пока недостаточно для рекомендации.</div>'
    end

    local html = [[
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
    :root {
        color-scheme: light;
        --canvas: #F1F2EE;
        --paper: rgba(255,255,255,.82);
        --ink: #17201C;
        --muted: #68736D;
        --line: rgba(23,32,28,.10);
        --green: #2E9B78;
        --green-soft: #DDF1E9;
        --amber: #A96518;
        --amber-soft: #F8EBD8;
        --shadow: 0 16px 42px rgba(24,34,29,.10);
    }

    * { box-sizing: border-box; }

    html, body {
        margin: 0;
        min-height: 100%;
        background:
            radial-gradient(circle at 12% 0%, rgba(46,155,120,.12), transparent 33%),
            radial-gradient(circle at 95% 12%, rgba(82,127,215,.09), transparent 28%),
            var(--canvas);
        color: var(--ink);
        font-family: "Avenir Next", "SF Pro Display", sans-serif;
        -webkit-font-smoothing: antialiased;
    }

    body { padding: 22px; }

    .shell {
        width: 100%;
        max-width: 1120px;
        margin: 0 auto;
    }

    .topbar {
        display: flex;
        align-items: center;
        justify-content: space-between;
        margin-bottom: 14px;
    }

    .top-meta {
        display: flex;
        align-items: center;
        gap: 10px;
    }

    .tracking-live {
        display: inline-flex;
        align-items: center;
        gap: 5px;
        padding: 4px 7px;
        border: 1px solid rgba(46,155,120,.18);
        border-radius: 999px;
        color: #187356;
        background: rgba(221,241,233,.78);
        font-size: 8px;
        font-weight: 800;
        letter-spacing: .04em;
        text-transform: uppercase;
    }

    .tracking-live::before {
        content: "";
        width: 5px;
        height: 5px;
        border-radius: 50%;
        background: var(--green);
        box-shadow: 0 0 0 3px rgba(46,155,120,.12);
    }

    .brand {
        display: flex;
        align-items: center;
        gap: 9px;
        font-size: 13px;
        font-weight: 700;
        letter-spacing: .02em;
    }

    .brand-mark {
        width: 22px;
        height: 22px;
        display: grid;
        place-items: center;
        border-radius: 7px;
        background: var(--ink);
        color: white;
        font-size: 11px;
        font-weight: 800;
    }

    .updated {
        color: var(--muted);
        font-size: 11px;
        font-weight: 600;
    }

    .summary {
        display: grid;
        grid-template-columns: 1.4fr .9fr .62fr;
        gap: 10px;
        margin-bottom: 12px;
    }

    .card {
        border: 1px solid rgba(255,255,255,.85);
        background: var(--paper);
        border-radius: 18px;
        box-shadow: var(--shadow);
        backdrop-filter: blur(20px);
    }

    .quota-card {
        min-height: 142px;
        display: flex;
        align-items: center;
        gap: 18px;
        padding: 18px;
    }

    .gauge {
        --size: 100px;
        width: var(--size);
        height: var(--size);
        flex: 0 0 var(--size);
        display: grid;
        place-items: center;
        border-radius: 50%;
        background: conic-gradient(var(--green) calc(var(--remaining) * 1%), #DCE2DE 0);
        position: relative;
    }

    .gauge::after {
        content: "";
        position: absolute;
        inset: 10px;
        border-radius: inherit;
        background: rgba(255,255,255,.96);
        box-shadow: inset 0 0 0 1px var(--line);
    }

    .gauge-value {
        position: relative;
        z-index: 1;
        text-align: center;
    }

    .gauge-value b {
        display: block;
        font-size: 28px;
        letter-spacing: -.06em;
        line-height: 1;
    }

    .gauge-value span {
        display: block;
        margin-top: 5px;
        color: var(--muted);
        font-size: 9px;
        font-weight: 800;
        letter-spacing: .10em;
    }

    .quota-copy .eyebrow,
    .insight-copy .eyebrow {
        color: var(--green);
        font-size: 9px;
        font-weight: 800;
        letter-spacing: .13em;
    }

    .quota-copy h1 {
        margin: 5px 0 6px;
        font-size: 21px;
        line-height: 1.1;
        letter-spacing: -.035em;
    }

    .quota-copy p {
        margin: 0;
        color: var(--muted);
        font-size: 12px;
        line-height: 1.45;
    }

    .quota-copy p b { color: var(--ink); }

    .mini-card {
        min-height: 142px;
        padding: 17px;
        display: flex;
        flex-direction: column;
        justify-content: space-between;
    }

    .mini-label {
        color: var(--muted);
        font-size: 10px;
        font-weight: 700;
        letter-spacing: .08em;
        text-transform: uppercase;
    }

    .mini-card strong {
        display: block;
        margin: 7px 0;
        font-size: 17px;
        line-height: 1.25;
        letter-spacing: -.025em;
    }

    .mini-note {
        color: var(--muted);
        font-size: 11px;
    }

    .credit {
        background: linear-gradient(145deg, rgba(23,32,28,.96), rgba(42,58,50,.96));
        color: white;
        border-color: transparent;
    }

    .credit .mini-label,
    .credit .mini-note { color: rgba(255,255,255,.62); }

    .credit strong {
        font-size: 38px;
        letter-spacing: -.06em;
    }

    .usage-card { padding: 17px 18px 18px; }

    .decision-card {
        display: grid;
        grid-template-columns: 1.15fr .82fr .72fr;
        align-items: center;
        gap: 16px;
        margin-bottom: 12px;
        padding: 17px 18px;
        overflow: hidden;
        color: white;
        border: 0;
        background:
            radial-gradient(circle at 85% -30%, rgba(87,218,172,.28), transparent 42%),
            linear-gradient(135deg, #17231E, #243B31);
        box-shadow: 0 18px 40px rgba(23,35,30,.18);
    }

    .decision-eyebrow {
        color: #78D9B5;
        font-size: 8px;
        font-weight: 800;
        letter-spacing: .12em;
    }

    .decision-title {
        display: flex;
        align-items: center;
        gap: 9px;
        margin: 4px 0;
    }

    .decision-title h2 {
        min-width: 0;
        margin: 0;
        overflow: hidden;
        text-overflow: ellipsis;
        font-size: 19px;
        letter-spacing: -.035em;
        white-space: nowrap;
    }

    .decision-title > span {
        padding: 4px 7px;
        border: 1px solid rgba(120,217,181,.25);
        border-radius: 8px;
        color: #8AE2C1;
        background: rgba(120,217,181,.10);
        font-size: 10px;
        font-weight: 800;
        white-space: nowrap;
    }

    .decision-main p {
        margin: 0;
        color: rgba(255,255,255,.56);
        font-size: 9px;
    }

    .decision-metrics {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        overflow: hidden;
        border: 1px solid rgba(255,255,255,.10);
        border-radius: 12px;
        background: rgba(255,255,255,.055);
    }

    .decision-metrics div {
        padding: 9px 7px;
        text-align: center;
        border-left: 1px solid rgba(255,255,255,.09);
    }

    .decision-metrics div:first-child { border-left: 0; }

    .decision-metrics span {
        display: block;
        color: rgba(255,255,255,.50);
        font-size: 7px;
    }

    .decision-metrics b {
        display: block;
        margin-top: 2px;
        font-size: 16px;
        letter-spacing: -.04em;
    }

    .decision-alternatives {
        display: grid;
        gap: 5px;
        color: rgba(255,255,255,.52);
        font-size: 8px;
    }

    .decision-alternatives span {
        padding: 5px 7px;
        border-radius: 7px;
        background: rgba(255,255,255,.055);
    }

    .decision-alternatives b {
        display: block;
        margin-top: 2px;
        overflow: hidden;
        color: white;
        font-size: 9px;
        text-overflow: ellipsis;
        white-space: nowrap;
    }

    .feedback-box {
        grid-column: 1 / -1;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        margin-top: -4px;
        padding-top: 11px;
        border-top: 1px solid rgba(255,255,255,.10);
    }

    .feedback-copy {
        min-width: 0;
    }

    .feedback-copy span,
    .feedback-done span {
        color: #78D9B5;
        font-size: 7px;
        font-weight: 800;
        letter-spacing: .08em;
    }

    .feedback-copy p {
        max-width: 480px;
        margin: 3px 0 0;
        overflow: hidden;
        color: rgba(255,255,255,.74);
        font-size: 9px;
        text-overflow: ellipsis;
        white-space: nowrap;
    }

    .feedback-actions {
        display: flex;
        gap: 6px;
        flex: 0 0 auto;
    }

    .feedback-actions a {
        padding: 6px 9px;
        border-radius: 8px;
        color: white;
        font-size: 8px;
        font-weight: 800;
        text-decoration: none;
    }

    .feedback-good { background: #2E9B78; }

    .feedback-rework {
        border: 1px solid rgba(255,255,255,.14);
        background: rgba(255,255,255,.07);
    }

    .feedback-done {
        grid-column: 1 / -1;
        display: flex;
        justify-content: space-between;
        padding-top: 10px;
        border-top: 1px solid rgba(255,255,255,.10);
    }

    .feedback-done b {
        color: rgba(255,255,255,.70);
        font-size: 8px;
    }

    .decision-empty {
        grid-column: 1 / -1;
        color: rgba(255,255,255,.70);
        font-size: 11px;
    }

    .section-head {
        display: flex;
        justify-content: space-between;
        align-items: end;
        margin-bottom: 11px;
    }

    .section-head h2 {
        margin: 0;
        font-size: 15px;
        letter-spacing: -.02em;
    }

    .section-head p {
        margin: 3px 0 0;
        color: var(--muted);
        font-size: 10px;
    }

    .period {
        color: var(--muted);
        font-size: 10px;
        font-weight: 700;
    }

    .composition {
        display: flex;
        gap: 3px;
        height: 8px;
        margin-bottom: 9px;
        overflow: hidden;
        border-radius: 999px;
        background: #DDE2DF;
    }

    .composition span {
        min-width: 3px;
        border-radius: 999px;
    }

    .models {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 10px;
    }

    .model-row {
        padding: 12px;
        border: 1px solid var(--line);
        border-radius: 14px;
        background: rgba(255,255,255,.58);
    }

    .model-head {
        display: flex;
        justify-content: space-between;
        align-items: center;
        gap: 10px;
    }

    .model-name {
        min-width: 0;
        display: flex;
        align-items: center;
        gap: 8px;
    }

    .model-name strong {
        overflow: hidden;
        text-overflow: ellipsis;
        white-space: nowrap;
        font-size: 12px;
        letter-spacing: -.01em;
    }

    .model-dot {
        width: 8px;
        height: 8px;
        flex: 0 0 8px;
        border-radius: 50%;
    }

    .model-share {
        font-size: 12px;
        font-weight: 800;
    }

    .track {
        height: 4px;
        margin: 8px 0 6px 16px;
        overflow: hidden;
        border-radius: 999px;
        background: #E5E8E6;
    }

    .track span {
        display: block;
        height: 100%;
        min-width: 3px;
        border-radius: inherit;
    }

    .model-summary {
        margin-left: 16px;
        color: var(--muted);
        font-size: 9px;
        white-space: nowrap;
    }

    .quality-block {
        display: grid;
        grid-template-columns: auto 1fr auto;
        align-items: center;
        gap: 10px;
        margin-top: 10px;
        padding: 9px 10px;
        border: 1px solid var(--line);
        border-radius: 11px;
        background: rgba(255,255,255,.76);
    }

    .quality-score {
        min-width: 62px;
        padding-right: 10px;
        border-right: 1px solid var(--line);
    }

    .quality-label {
        display: block;
        margin-bottom: 2px;
        color: var(--muted);
        font-size: 7px;
        font-weight: 800;
        letter-spacing: .08em;
        text-transform: uppercase;
    }

    .quality-score div {
        display: flex;
        align-items: baseline;
        gap: 2px;
    }

    .quality-score strong {
        font-size: 21px;
        line-height: 1;
        letter-spacing: -.055em;
    }

    .quality-score small {
        color: var(--muted);
        font-size: 8px;
        font-weight: 700;
    }

    .quality-signals {
        display: grid;
        gap: 3px;
        color: var(--muted);
        font-size: 8px;
    }

    .category-card {
        margin-top: 12px;
        padding: 16px 18px 18px;
    }

    .category-grid {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 9px;
        margin-top: 11px;
    }

    .category-item {
        min-width: 0;
        padding: 12px;
        border: 1px solid var(--line);
        border-radius: 13px;
        background: rgba(255,255,255,.60);
    }

    .category-item > span {
        display: block;
        color: var(--muted);
        font-size: 9px;
        font-weight: 700;
    }

    .category-item > strong {
        display: block;
        margin: 4px 0 9px;
        overflow: hidden;
        font-size: 12px;
        text-overflow: ellipsis;
        white-space: nowrap;
    }

    .category-item div {
        display: flex;
        align-items: baseline;
        justify-content: space-between;
        gap: 7px;
    }

    .category-item b {
        color: var(--green);
        font-size: 11px;
    }

    .category-item small {
        overflow: hidden;
        color: var(--muted);
        font-size: 7px;
        text-overflow: ellipsis;
        white-space: nowrap;
    }

    .category-empty {
        color: var(--muted);
        font-size: 11px;
    }

    .quality-signals b { color: var(--ink); }

    .quality-state {
        display: grid;
        justify-items: end;
        gap: 2px;
        text-align: right;
    }

    .quality-state b {
        padding: 3px 6px;
        border-radius: 6px;
        font-size: 7px;
        white-space: nowrap;
    }

    .quality-state span {
        color: var(--muted);
        font-size: 7px;
    }

    .quality-good .quality-state b {
        color: #187356;
        background: var(--green-soft);
    }

    .quality-average .quality-state b {
        color: #55615B;
        background: #E3E7E4;
    }

    .quality-watch .quality-state b {
        color: var(--amber);
        background: var(--amber-soft);
    }

    .quality-sample .quality-state b,
    .quality-pending .quality-confidence {
        color: #5F6690;
        background: #E6E8F4;
    }

    .quality-pending {
        grid-template-columns: 1fr auto;
        color: var(--muted);
    }

    .quality-pending strong {
        font-size: 10px;
        color: var(--ink);
    }

    .quality-confidence {
        padding: 3px 6px;
        border-radius: 6px;
        font-size: 7px;
        font-weight: 800;
    }

    .efficiency-block {
        margin-top: 10px;
        padding: 9px 10px 8px;
        border-radius: 10px;
        background: rgba(241,242,238,.92);
    }

    .efficiency-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
    }

    .efficiency-index {
        display: flex;
        align-items: baseline;
        gap: 4px;
    }

    .efficiency-index b {
        font-size: 17px;
        letter-spacing: -.05em;
    }

    .efficiency-index span {
        color: var(--muted);
        font-size: 8px;
        font-weight: 700;
        text-transform: uppercase;
        letter-spacing: .08em;
    }

    .efficiency-verdict {
        padding: 3px 6px;
        border-radius: 6px;
        font-size: 8px;
        font-weight: 800;
    }

    .efficiency-verdict.good {
        color: #187356;
        background: var(--green-soft);
    }

    .efficiency-verdict.average {
        color: #55615B;
        background: #E3E7E4;
    }

    .efficiency-verdict.watch {
        color: var(--amber);
        background: var(--amber-soft);
    }

    .efficiency-verdict.sample {
        color: #5F6690;
        background: #E6E8F4;
    }

    .efficiency-track {
        position: relative;
        height: 4px;
        margin: 7px 0 6px;
        border-radius: 999px;
        background: #DDE2DF;
    }

    .efficiency-track span {
        display: block;
        height: 100%;
        border-radius: inherit;
        opacity: .78;
    }

    .efficiency-track i {
        position: absolute;
        top: -2px;
        left: 66.66%;
        width: 2px;
        height: 8px;
        border-radius: 2px;
        background: rgba(23,32,28,.45);
    }

    .history-line {
        display: grid;
        grid-template-columns: 1fr auto;
        align-items: center;
        gap: 8px;
        margin: 5px 0 3px;
    }

    .spark-wrap {
        height: 24px;
        overflow: hidden;
        border-radius: 7px;
        background:
            linear-gradient(to bottom, transparent 49%, rgba(23,32,28,.05) 50%, transparent 51%);
    }

    .sparkline {
        display: block;
        width: 100%;
        height: 24px;
        overflow: visible;
    }

    .sparkline line {
        stroke: rgba(23,32,28,.12);
        stroke-width: 1;
        stroke-dasharray: 3 3;
    }

    .sparkline polyline {
        fill: none;
        stroke-width: 2;
        stroke-linecap: round;
        stroke-linejoin: round;
        vector-effect: non-scaling-stroke;
    }

    .history-change {
        min-width: 62px;
        padding: 3px 5px;
        border-radius: 6px;
        color: var(--muted);
        background: rgba(255,255,255,.74);
        font-size: 7px;
        font-weight: 800;
        text-align: center;
        white-space: nowrap;
    }

    .history-change.up { color: #187356; }
    .history-change.down { color: var(--amber); }

    .efficiency-metrics {
        display: flex;
        justify-content: space-between;
        gap: 8px;
        color: var(--muted);
        font-size: 8px;
    }

    .efficiency-metrics b {
        color: var(--ink);
        font-weight: 700;
    }

    .insight {
        display: grid;
        grid-template-columns: auto 1fr auto;
        align-items: center;
        gap: 14px;
        margin-top: 12px;
        padding: 13px 16px;
        border-color: rgba(46,155,120,.14);
        background: linear-gradient(135deg, rgba(245,252,248,.96), rgba(255,255,255,.86));
    }

    .method-mark {
        width: 48px;
        height: 48px;
        display: grid;
        place-items: center;
        border-radius: 15px;
        color: white;
        background: var(--green);
        box-shadow: 0 8px 18px rgba(46,155,120,.22);
        font-size: 17px;
        font-weight: 800;
        letter-spacing: -.04em;
    }

    .method-copy .eyebrow {
        color: var(--green);
        font-size: 8px;
        font-weight: 800;
        letter-spacing: .12em;
    }

    .method-copy h3 {
        margin: 3px 0 3px;
        font-size: 13px;
        letter-spacing: -.02em;
    }

    .method-copy p {
        margin: 0;
        max-width: 390px;
        color: var(--muted);
        font-size: 8px;
        line-height: 1.4;
    }

    .method-scale {
        display: grid;
        gap: 4px;
        justify-items: start;
    }

    .method-scale span {
        padding: 3px 6px;
        border-radius: 6px;
        font-size: 8px;
        font-weight: 800;
        white-space: nowrap;
    }

    .scale-good {
        color: #187356;
        background: var(--green-soft);
    }

    .scale-average {
        color: #55615B;
        background: #E3E7E4;
    }

    .scale-watch {
        color: var(--amber);
        background: var(--amber-soft);
    }

    @media (min-width: 900px) {
        body { padding: 28px; }

        .topbar { margin-bottom: 18px; }

        .brand {
            gap: 11px;
            font-size: 15px;
        }

        .brand-mark {
            width: 28px;
            height: 28px;
            border-radius: 9px;
            font-size: 12px;
        }

        .tracking-live {
            padding: 6px 9px;
            font-size: 9px;
        }

        .updated { font-size: 12px; }

        .summary {
            grid-template-columns: 1.45fr .9fr .55fr;
            gap: 14px;
            margin-bottom: 14px;
        }

        .card { border-radius: 21px; }

        .quota-card {
            min-height: 166px;
            gap: 24px;
            padding: 22px;
        }

        .gauge { --size: 118px; }

        .gauge::after { inset: 12px; }

        .gauge-value b { font-size: 34px; }

        .gauge-value span { font-size: 10px; }

        .quota-copy .eyebrow,
        .insight-copy .eyebrow { font-size: 10px; }

        .quota-copy h1 {
            margin: 7px 0 8px;
            font-size: 27px;
        }

        .quota-copy p { font-size: 14px; }

        .mini-card {
            min-height: 166px;
            padding: 21px;
        }

        .mini-label { font-size: 11px; }

        .mini-card strong { font-size: 20px; }

        .mini-note { font-size: 12px; }

        .credit strong { font-size: 45px; }

        .decision-card {
            gap: 22px;
            margin-bottom: 14px;
            padding: 21px 22px;
        }

        .decision-eyebrow { font-size: 9px; }

        .decision-title h2 { font-size: 25px; }

        .decision-title > span {
            padding: 6px 9px;
            font-size: 12px;
        }

        .decision-main p { font-size: 11px; }

        .decision-metrics span { font-size: 9px; }

        .decision-metrics b { font-size: 20px; }

        .decision-alternatives { font-size: 10px; }

        .decision-alternatives b { font-size: 11px; }

        .feedback-copy span { font-size: 9px; }

        .feedback-copy p { font-size: 11px; }

        .feedback-actions a {
            padding: 8px 12px;
            font-size: 10px;
        }

        .usage-card,
        .category-card { padding: 21px 22px; }

        .section-head h2 { font-size: 19px; }

        .section-head p,
        .period { font-size: 11px; }

        .models { gap: 14px; }

        .model-row {
            padding: 16px;
            border-radius: 17px;
        }

        .model-name strong { font-size: 15px; }

        .model-share { font-size: 14px; }

        .model-summary { font-size: 11px; }

        .quality-block { padding: 12px; }

        .quality-label,
        .quality-state span { font-size: 9px; }

        .quality-score strong { font-size: 26px; }

        .quality-signals { font-size: 10px; }

        .quality-state b {
            padding: 5px 8px;
            font-size: 9px;
        }

        .efficiency-block { padding: 11px 12px; }

        .efficiency-index b { font-size: 21px; }

        .efficiency-index span,
        .efficiency-metrics { font-size: 10px; }

        .efficiency-verdict { font-size: 9px; }

        .history-change { font-size: 9px; }

        .category-grid {
            grid-template-columns: repeat(3, minmax(0, 1fr));
            gap: 12px;
        }

        .category-item { padding: 15px; }

        .category-item > span { font-size: 11px; }

        .category-item > strong { font-size: 15px; }

        .category-item b { font-size: 13px; }

        .category-item small { font-size: 9px; }

        .insight { padding: 16px 20px; }

        .method-copy h3 { font-size: 16px; }

        .method-copy p,
        .method-scale span { font-size: 10px; }
    }

    @media (max-width: 620px) {
        body { padding: 14px; }
        .summary { grid-template-columns: 1fr 1fr; }
        .quota-card { grid-column: 1 / -1; }
        .models, .insight { grid-template-columns: 1fr; }
        .decision-card { grid-template-columns: 1fr; }
        .category-grid { grid-template-columns: 1fr; }
        .feedback-box { align-items: flex-start; flex-direction: column; }
        .method-scale { grid-template-columns: repeat(3, auto); }
    }
</style>
</head>
<body>
<main class="shell">
    <header class="topbar">
        <div class="brand"><span class="brand-mark">CQ</span> Codex Quota</div>
        <div class="top-meta">
            <span class="tracking-live">история пишется</span>
            <div class="updated">Обновлено __UPDATED__</div>
        </div>
    </header>

    <section class="summary">
        <article class="card quota-card">
            <div class="gauge" style="--remaining:__REMAINING__">
                <div class="gauge-value"><b>__REMAINING__%</b><span>ОСТАЛОСЬ</span></div>
            </div>
            <div class="quota-copy">
                <span class="eyebrow">НЕДЕЛЬНЫЙ ЛИМИТ</span>
                <h1>Запас в норме</h1>
                <p><b>__USED__%</b> уже использовано</p>
            </div>
        </article>

        <article class="card mini-card">
            <span class="mini-label">Следующий сброс</span>
            <strong>__RESET__</strong>
            <span class="mini-note">Основное недельное окно</span>
        </article>

        <article class="card mini-card credit">
            <span class="mini-label">Ручные сбросы</span>
            <strong>__CREDITS__</strong>
            <span class="mini-note">доступно сейчас</span>
        </article>
    </section>

    <section class="card decision-card">__RECOMMENDATION__</section>

    <section class="card usage-card">
        <div class="section-head">
            <div>
                <h2>Модели и эффективность</h2>
                <p>Доля токенов и стоимость одной задачи, Spark исключён</p>
            </div>
            <span class="period">7 дней</span>
        </div>
        <div class="composition">__SEGMENTS__</div>
        <div class="models">__MODEL_ROWS__</div>
    </section>

    <section class="card category-card">
        <div class="section-head">
            <div>
                <h2>Какая модель выгоднее для задачи</h2>
                <p>Рекомендации строятся отдельно по категориям</p>
            </div>
            <span class="period">30 дней</span>
        </div>
        <div class="category-grid">__CATEGORY_CARDS__</div>
    </section>

    <section class="card insight">__EFFICIENCY__</section>
</main>
</body>
</html>
    ]]

    local function inject(token, value)
        html = string.gsub(html, token, function()
            return tostring(value)
        end)
    end

    inject("__UPDATED__", updatedText)
    inject("__REMAINING__", math.floor(remaining + 0.5))
    inject("__USED__", math.floor(used + 0.5))
    inject("__RESET__", htmlEscape(resetText))
    inject("__CREDITS__", resetCredits)
    inject("__SEGMENTS__", table.concat(compositionSegments))
    inject("__MODEL_ROWS__", table.concat(modelRows))
    inject("__RECOMMENDATION__", recommendationHTML)
    inject("__CATEGORY_CARDS__", categoryHTML)
    inject("__EFFICIENCY__", efficiencyHTML)

    return html
end

local initialEfficiencyStatus = readQuotaJSON(efficiencyStatusPath)
if initialEfficiencyStatus then
    recordModelEfficiency(initialEfficiencyStatus)
end

codexQuotaEfficiencyTimer = hs.timer.doEvery(900, function()
    local status = readQuotaJSON(efficiencyStatusPath)
    if status then
        recordModelEfficiency(status)
    end
end)

local function refreshModelQuality()
    local command = string.format(
        "/usr/bin/python3 %q >/dev/null 2>&1 &",
        modelQualityScriptPath
    )
    hs.execute(command)
end

refreshModelQuality()
codexModelQualityTimer = hs.timer.doEvery(1800, refreshModelQuality)

function showCodexQuotaPanel()
    local screen = hs.screen.mainScreen():frame()
    local panelWidth = math.min(1180, screen.w - 80)
    local panelHeight = math.min(780, screen.h - 80)
    local frame = {
        x = screen.x + math.floor((screen.w - panelWidth) / 2),
        y = screen.y + math.floor((screen.h - panelHeight) / 2),
        w = panelWidth,
        h = panelHeight,
    }
    local status = readQuotaJSON(efficiencyStatusPath) or {}

    if not codexQuotaPanel then
        codexQuotaPanel = hs.webview.newBrowser(frame, { privateBrowsing = true })
            :allowNewWindows(false)
            :closeOnEscape(true)
            :windowTitle("Codex Quota")
            :shadow(true)
    else
        codexQuotaPanel:frame(frame)
    end

    codexQuotaPanel:html(quotaPanelHTML(status))
    codexQuotaPanel:show()
end

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
