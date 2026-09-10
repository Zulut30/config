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
quotaPanelHTML = function(data)
    data = data or {}

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

    for index, item in ipairs(models) do
        local share = totalTokens > 0 and math.floor((item.tokens / totalTokens) * 100 + 0.5) or 0
        local color = colors[((index - 1) % #colors) + 1]
        local safeName = htmlEscape(item.name)

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
                <div class="model-metrics">
                    <span><b>%s</b> токенов</span>
                    <span><b>%d</b> задач</span>
                    <span><b>%s</b> работы</span>
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
            formatDuration(item.seconds)
        ))
    end

    local focusModel = nil
    for _, item in ipairs(models) do
        if item.name == "gpt-6-astra" then
            focusModel = item
            break
        end
    end

    local efficiencyHTML = [[
        <div class="empty-insight">Для gpt-6-astra пока недостаточно данных.</div>
    ]]

    if focusModel and focusModel.tasks > 0 then
        local perTask = focusModel.tokens / focusModel.tasks
        local averagePerTask = totalTasks > 0 and totalTokens / totalTasks or 0
        local ratio = averagePerTask > 0 and perTask / averagePerTask or 0
        local delta = math.floor(math.abs(ratio - 1) * 100 + 0.5)
        local tasksPerHour = focusModel.seconds > 0 and focusModel.tasks / (focusModel.seconds / 3600) or 0
        local verdictClass = ratio <= 1 and "good" or "watch"
        local verdict

        if ratio <= 0.9 then
            verdict = string.format("на %d%% экономнее среднего", delta)
        elseif ratio <= 1.1 then
            verdict = "примерно на уровне среднего"
        else
            verdict = string.format("на %d%% ресурсоёмче среднего", delta)
        end

        efficiencyHTML = string.format([[
            <div class="insight-copy">
                <span class="eyebrow">ЭФФЕКТИВНОСТЬ МОДЕЛИ</span>
                <h3>gpt-6-astra</h3>
                <p class="verdict %s">%s</p>
                <p class="explanation">Сравнение основано на сгенерированных токенах на одну завершённую задачу за 7 дней.</p>
            </div>
            <div class="insight-stats">
                <div><b>%s</b><span>токенов / задача</span></div>
                <div><b>%.1f</b><span>задач / час</span></div>
                <div><b>%d</b><span>задач всего</span></div>
            </div>
        ]],
            verdictClass,
            verdict,
            formatTokens(perTask),
            tasksPerHour,
            focusModel.tasks
        )
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
        max-width: 760px;
        margin: 0 auto;
    }

    .topbar {
        display: flex;
        align-items: center;
        justify-content: space-between;
        margin-bottom: 14px;
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

    .usage-card { padding: 17px 18px 14px; }

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
        gap: 0 20px;
    }

    .model-row {
        padding: 10px 0;
        border-top: 1px solid var(--line);
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
        margin: 8px 0 7px 16px;
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

    .model-metrics {
        display: flex;
        gap: 12px;
        margin-left: 16px;
        color: var(--muted);
        font-size: 9px;
        white-space: nowrap;
    }

    .model-metrics b {
        color: var(--ink);
        font-weight: 700;
    }

    .insight {
        display: grid;
        grid-template-columns: 1.2fr 1fr;
        gap: 16px;
        margin-top: 12px;
        padding: 16px 18px;
        border-color: rgba(169,101,24,.14);
        background: linear-gradient(135deg, rgba(255,250,241,.94), rgba(255,255,255,.86));
    }

    .insight-copy h3 {
        margin: 4px 0 5px;
        font-size: 18px;
        letter-spacing: -.035em;
    }

    .verdict {
        display: inline-flex;
        margin: 0;
        padding: 5px 8px;
        border-radius: 8px;
        font-size: 10px;
        font-weight: 800;
    }

    .verdict.good {
        color: #187356;
        background: var(--green-soft);
    }

    .verdict.watch {
        color: var(--amber);
        background: var(--amber-soft);
    }

    .explanation {
        max-width: 390px;
        margin: 8px 0 0;
        color: var(--muted);
        font-size: 9px;
        line-height: 1.45;
    }

    .insight-stats {
        display: grid;
        grid-template-columns: repeat(3, 1fr);
        align-items: center;
        overflow: hidden;
        border: 1px solid var(--line);
        border-radius: 13px;
        background: rgba(255,255,255,.68);
    }

    .insight-stats div {
        min-width: 0;
        padding: 12px 9px;
        text-align: center;
        border-left: 1px solid var(--line);
    }

    .insight-stats div:first-child { border-left: 0; }

    .insight-stats b {
        display: block;
        font-size: 14px;
        letter-spacing: -.03em;
    }

    .insight-stats span {
        display: block;
        margin-top: 3px;
        color: var(--muted);
        font-size: 8px;
        line-height: 1.25;
    }

    .empty-insight {
        grid-column: 1 / -1;
        color: var(--muted);
        font-size: 12px;
    }

    @media (max-width: 620px) {
        body { padding: 14px; }
        .summary { grid-template-columns: 1fr 1fr; }
        .quota-card { grid-column: 1 / -1; }
        .models, .insight { grid-template-columns: 1fr; }
    }
</style>
</head>
<body>
<main class="shell">
    <header class="topbar">
        <div class="brand"><span class="brand-mark">CQ</span> Codex Quota</div>
        <div class="updated">Обновлено __UPDATED__</div>
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

    <section class="card usage-card">
        <div class="section-head">
            <div>
                <h2>Распределение нагрузки</h2>
                <p>Доля сгенерированных токенов, Spark исключён</p>
            </div>
            <span class="period">7 дней</span>
        </div>
        <div class="composition">__SEGMENTS__</div>
        <div class="models">__MODEL_ROWS__</div>
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
    inject("__EFFICIENCY__", efficiencyHTML)

    return html
end
  else
    codexQuotaMenu:setTitle("--")
    codexQuotaMenu:setTooltip("Codex: ожидаю первое обновление лимита")
    codexQuotaMenu:setMenu(nil)
    codexQuotaMenu:setClickCallback(showCodexQuotaPanel)
  end
end

refreshCodexQuota()
hs.timer.doEvery(60, refreshCodexQuota)
