#!/usr/bin/env python3
"""Build a transparent per-model quality score from local Codex session logs."""

from __future__ import annotations

import json
import math
import os
import re
import statistics
import tempfile
import time
from collections import defaultdict
from pathlib import Path
from typing import Any


PERIOD_DAYS = 30
SESSION_ROOT = Path.home() / ".codex" / "sessions"
OUTPUT_PATH = Path.home() / "Library" / "Caches" / "CodexQuota" / "model-quality.json"
FEEDBACK_PATH = Path.home() / "Library" / "Caches" / "CodexQuota" / "model-feedback.json"
LEDGER_PATH = Path.home() / "Library" / "Caches" / "CodexQuota" / "task-ledger.jsonl"
CUTOFF = time.time() - PERIOD_DAYS * 86400

# These weights are a relative local load proxy, not OpenAI billing or quota units.
# Cached context is cheaper to reuse, while generated and reasoning tokens usually
# represent more work than a fresh input token.
CACHED_INPUT_WEIGHT = 0.20
OUTPUT_TOKEN_WEIGHT = 1.50
REASONING_TOKEN_WEIGHT = 2.50
RECENCY_HALF_LIFE_DAYS = 14.0
OUTLIER_MAD_LIMIT = 3.5

CORRECTION_RE = re.compile(
    r"(?:"
    r"\bне\s+работает\b|\bне\s+сработал[оа]?\b|\bвс[её]\s+ещ[её]\b|"
    r"\bничего\s+не\b|\bты\s+не\b|\bне\s+сделал[оа]?\b|"
    r"\bне\s+так\b|\bне\s+то\b|\bне\s+открыва\w*\b|"
    r"\bне\s+показыва\w*\b|\bне\s+нравится\b|\bисправь\b|"
    r"\bпеределай\b|\bошибк\w*\b|\bсломал\w*\b|"
    r"doesn['’]?t\s+work|still\s+not|\bwrong\b|\bfix\s+(?:it|this)\b"
    r")",
    re.IGNORECASE,
)

TEST_RE = re.compile(
    r"(?:^|\s)(?:pytest|swift\s+test|xcodebuild\b.*\btest\b|"
    r"npm\s+(?:run\s+)?test|pnpm\s+(?:run\s+)?test|"
    r"yarn\s+(?:run\s+)?test|cargo\s+test|go\s+test|"
    r"vitest|jest)(?:\s|$)",
    re.IGNORECASE,
)

IGNORED_USER_PREFIXES = (
    "<recommended_plugins>",
    "<environment_context>",
    "<app-context>",
    "# agents.md instructions",
)


def parse_iso(value: Any) -> float | None:
    if not isinstance(value, str):
        return None
    try:
        from datetime import datetime

        return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except (TypeError, ValueError):
        return None


def text_content(payload: dict[str, Any]) -> str:
    parts: list[str] = []
    for item in payload.get("content") or []:
        if not isinstance(item, dict):
            continue
        value = item.get("text")
        if not isinstance(value, str):
            continue
        stripped = value.strip()
        if not stripped:
            continue
        if stripped.lower().startswith(IGNORED_USER_PREFIXES):
            continue
        parts.append(stripped)
    return "\n".join(parts)


def command_text(item: dict[str, Any]) -> str:
    command = item.get("command")
    if isinstance(command, list):
        return " ".join(str(part) for part in command)
    return str(command or "")


def benign_command_failure(command: str, exit_code: Any, stderr: str) -> bool:
    try:
        code = int(exit_code)
    except (TypeError, ValueError):
        return False
    if code != 1 or stderr.strip():
        return False
    lowered = command.lower()
    return bool(re.search(r"(?:^|[;&|]\s*)(?:rg|grep)\b", lowered))


def new_turn(turn_id: str) -> dict[str, Any]:
    return {
        "turnId": turn_id,
        "threadId": "",
        "model": "",
        "prompt": "",
        "startedAt": None,
        "endedAt": None,
        "completed": False,
        "hasFinal": False,
        "outputTokens": 0,
        "inputTokens": 0,
        "cachedInputTokens": 0,
        "reasoningTokens": 0,
        "totalTokens": 0,
        "commands": 0,
        "commandFailures": 0,
        "tests": 0,
        "testFailures": 0,
        "lastTestFailed": None,
        "fileChanges": 0,
        "manualFeedback": False,
    }


def parse_sessions() -> list[dict[str, Any]]:
    turns: dict[str, dict[str, Any]] = {}

    if not SESSION_ROOT.exists():
        return []

    files = []
    for path in SESSION_ROOT.rglob("*.jsonl"):
        try:
            if path.stat().st_mtime >= CUTOFF:
                files.append(path)
        except OSError:
            continue

    for path in files:
        current_turn_id = ""
        default_thread_id = ""
        try:
            handle = path.open("r", encoding="utf-8", errors="replace")
        except OSError:
            continue

        with handle:
            for raw_line in handle:
                try:
                    event = json.loads(raw_line)
                except (json.JSONDecodeError, TypeError):
                    continue

                event_type = event.get("type")
                payload = event.get("payload")
                if not isinstance(payload, dict):
                    continue

                timestamp = parse_iso(event.get("timestamp"))

                if event_type == "session_meta":
                    default_thread_id = str(
                        payload.get("thread_id")
                        or payload.get("session_id")
                        or payload.get("id")
                        or ""
                    )
                    continue

                if event_type == "turn_context":
                    turn_id = str(payload.get("turn_id") or "")
                    if not turn_id:
                        continue
                    current_turn_id = turn_id
                    turn = turns.setdefault(turn_id, new_turn(turn_id))
                    turn["threadId"] = str(
                        payload.get("thread_id")
                        or payload.get("root_turn_id")
                        or default_thread_id
                        or path.name
                    )
                    turn["model"] = str(payload.get("model") or turn["model"])
                    turn["startedAt"] = turn["startedAt"] or timestamp
                    continue

                payload_type = payload.get("type")
                if event_type == "event_msg" and payload_type == "task_started":
                    turn_id = str(payload.get("turn_id") or current_turn_id)
                    if not turn_id:
                        continue
                    current_turn_id = turn_id
                    turn = turns.setdefault(turn_id, new_turn(turn_id))
                    turn["threadId"] = turn["threadId"] or default_thread_id or path.name
                    turn["startedAt"] = (
                        float(payload.get("started_at"))
                        if payload.get("started_at") is not None
                        else turn["startedAt"] or timestamp
                    )
                    continue

                metadata = payload.get("internal_chat_message_metadata_passthrough")
                metadata_turn_id = (
                    str(metadata.get("turn_id") or "")
                    if isinstance(metadata, dict)
                    else ""
                )
                turn_id = str(payload.get("turn_id") or metadata_turn_id or current_turn_id)
                if not turn_id:
                    continue
                turn = turns.setdefault(turn_id, new_turn(turn_id))
                turn["threadId"] = turn["threadId"] or default_thread_id or path.name

                if event_type == "response_item" and payload_type == "message":
                    role = payload.get("role")
                    if role == "user":
                        message = text_content(payload)
                        if message and not turn["prompt"]:
                            turn["prompt"] = message
                    elif role == "assistant" and payload.get("phase") == "final_answer":
                        turn["hasFinal"] = True
                        turn["endedAt"] = max(turn["endedAt"] or 0, timestamp or 0)
                    continue

                if event_type == "token_usage_record":
                    turn["threadId"] = str(payload.get("thread_id") or turn["threadId"])
                    usage = payload.get("turn_token_usage") or payload.get("usage") or {}
                    if isinstance(usage, dict):
                        turn["outputTokens"] = max(
                            turn["outputTokens"],
                            int(usage.get("output_tokens") or 0),
                        )
                        turn["inputTokens"] = max(
                            turn["inputTokens"],
                            int(usage.get("input_tokens") or 0),
                        )
                        turn["cachedInputTokens"] = max(
                            turn["cachedInputTokens"],
                            int(usage.get("cached_input_tokens") or 0),
                        )
                        turn["reasoningTokens"] = max(
                            turn["reasoningTokens"],
                            int(usage.get("reasoning_output_tokens") or 0),
                        )
                        turn["totalTokens"] = max(
                            turn["totalTokens"],
                            int(
                                usage.get("total_tokens")
                                or (
                                    int(usage.get("input_tokens") or 0)
                                    + int(usage.get("output_tokens") or 0)
                                )
                            ),
                        )
                    continue

                if event_type != "event_msg":
                    continue

                if payload_type == "task_complete":
                    turn["completed"] = True
                    turn["endedAt"] = max(turn["endedAt"] or 0, timestamp or 0)
                    continue

                item = payload.get("item")
                if not isinstance(item, dict) or payload_type != "item_completed":
                    continue

                item_type = item.get("type")
                if item_type == "CommandExecution":
                    command = command_text(item)
                    exit_code = item.get("exit_code")
                    stderr = str(item.get("stderr") or "")
                    failed = item.get("status") == "failed"
                    if exit_code is not None:
                        try:
                            failed = failed or int(exit_code) != 0
                        except (TypeError, ValueError):
                            pass

                    if not benign_command_failure(command, exit_code, stderr):
                        turn["commands"] += 1
                        if failed:
                            turn["commandFailures"] += 1

                    if TEST_RE.search(command):
                        turn["tests"] += 1
                        turn["lastTestFailed"] = failed
                        if failed:
                            turn["testFailures"] += 1
                elif item_type == "FileChange":
                    turn["fileChanges"] += 1

    result = []
    for turn in turns.values():
        if not turn["model"] or "spark" in turn["model"].lower():
            continue
        started = turn["startedAt"]
        if not started or started < CUTOFF:
            continue
        if not turn["prompt"]:
            continue
        if not turn["endedAt"]:
            turn["endedAt"] = started
        result.append(turn)
    return result


def load_feedback() -> dict[str, str]:
    try:
        with FEEDBACK_PATH.open("r", encoding="utf-8") as handle:
            value = json.load(handle)
    except (OSError, json.JSONDecodeError, TypeError):
        return {}

    result = {}
    for record in value.get("records", []) if isinstance(value, dict) else []:
        if not isinstance(record, dict):
            continue
        turn_id = str(record.get("turnId") or "")
        verdict = str(record.get("verdict") or "")
        if turn_id and verdict in {"good", "rework"}:
            result[turn_id] = verdict
    return result


def enrich_outcomes(turns: list[dict[str, Any]], feedback: dict[str, str]) -> None:
    by_thread: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for turn in turns:
        by_thread[turn["threadId"]].append(turn)

    for thread_turns in by_thread.values():
        thread_turns.sort(key=lambda item: item["startedAt"] or 0)
        for index, turn in enumerate(thread_turns):
            turn["feedbackKnown"] = False
            turn["needsRework"] = False
            if index + 1 >= len(thread_turns):
                continue
            following = thread_turns[index + 1]
            gap = (following["startedAt"] or 0) - (turn["endedAt"] or turn["startedAt"] or 0)
            if gap < 0 or gap > 24 * 3600:
                continue
            turn["feedbackKnown"] = True
            turn["needsRework"] = bool(CORRECTION_RE.search(following["prompt"]))

    for turn in turns:
        verdict = feedback.get(turn["turnId"])
        if verdict:
            turn["feedbackKnown"] = True
            turn["needsRework"] = verdict == "rework"
            turn["manualFeedback"] = True


def classify_category(prompt: str) -> tuple[str, str]:
    lowered = prompt.lower()
    categories = (
        (
            "frontend",
            "Frontend и дизайн",
            r"frontend|фронтенд|интерфейс|ui\b|ux\b|дизайн|css\b|swiftui|дашборд|панел",
        ),
        (
            "research",
            "Исследования",
            r"исслед|поищи|найди данные|источник|research|проанализируй|сравни",
        ),
        (
            "writing",
            "Тексты и редактура",
            r"отредакт|статья|текст|перепиши|гайд|лонгрид|публикац|редактор",
        ),
        (
            "macos",
            "macOS и автоматизация",
            r"macos|мак\b|hammerspoon|терминал|горяч|автозапуск|menu bar|dock",
        ),
        (
            "documents",
            "Документы",
            r"pdf\b|docx\b|xlsx\b|таблиц|презентац|документ|google docs",
        ),
        (
            "coding",
            "Программирование",
            r"код\b|баг\b|ошибк|репозитор|commit|push|api\b|swift\b|python\b|"
            r"typescript|javascript|тест|файл|реализ",
        ),
    )
    for key, label, pattern in categories:
        if re.search(pattern, lowered):
            return key, label
    return "general", "Общие задачи"


def complexity(turn: dict[str, Any]) -> float:
    prompt_chars = len(turn["prompt"])
    prompt_weight = min(3.0, math.log2(1 + prompt_chars / 140))
    url_weight = min(1.0, len(re.findall(r"https?://", turn["prompt"])) * 0.25)
    path_weight = min(
        1.5,
        len(re.findall(r"(?:^|\s)(?:/|\./|\.\./)[^\s]+", turn["prompt"])) * 0.3,
    )
    category_key, _ = classify_category(turn["prompt"])
    category_weight = {
        "research": 1.2,
        "frontend": 0.8,
        "coding": 0.9,
        "documents": 0.7,
        "macos": 0.6,
        "writing": 0.4,
        "general": 0.0,
    }.get(category_key, 0.0)
    structure_weight = min(
        1.5,
        len(re.findall(r"(?m)^\s*(?:[-*]|\d+[.)])\s+", turn["prompt"])) * 0.18
        + len(re.findall(r"```", turn["prompt"])) * 0.15,
    )
    intent_weight = min(
        1.5,
        len(
            re.findall(
                r"\b(?:сделай|добавь|исправь|удали|проверь|сравни|найди|"
                r"создай|запусти|реализуй|build|fix|add|remove|check|compare)\w*\b",
                turn["prompt"],
                re.IGNORECASE,
            )
        )
        * 0.16,
    )
    return max(
        1.0,
        1.0
        + prompt_weight
        + url_weight
        + path_weight
        + category_weight
        + structure_weight
        + intent_weight,
    )


def effective_token_cost(turn: dict[str, Any]) -> float:
    input_tokens = max(0, int(turn.get("inputTokens") or 0))
    cached_tokens = min(input_tokens, max(0, int(turn.get("cachedInputTokens") or 0)))
    reasoning_tokens = min(
        max(0, int(turn.get("outputTokens") or 0)),
        max(0, int(turn.get("reasoningTokens") or 0)),
    )
    visible_output_tokens = max(
        0,
        int(turn.get("outputTokens") or 0) - reasoning_tokens,
    )
    return (
        (input_tokens - cached_tokens)
        + cached_tokens * CACHED_INPUT_WEIGHT
        + visible_output_tokens * OUTPUT_TOKEN_WEIGHT
        + reasoning_tokens * REASONING_TOKEN_WEIGHT
    )


def build_chains(turns: list[dict[str, Any]]) -> list[dict[str, Any]]:
    by_thread: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for turn in turns:
        by_thread[turn["threadId"]].append(turn)

    chains = []
    for thread_id, thread_turns in by_thread.items():
        thread_turns.sort(key=lambda item: item["startedAt"] or 0)
        current = None
        previous = None
        for turn in thread_turns:
            if (
                current is None
                or not previous
                or not previous["needsRework"]
                or current["model"] != turn["model"]
            ):
                current = {
                    "chainId": turn["turnId"],
                    "threadId": thread_id,
                    "model": turn["model"],
                    "category": turn["category"],
                    "categoryLabel": turn["categoryLabel"],
                    "startedAt": turn["startedAt"],
                    "turns": [],
                }
                chains.append(current)
            current["turns"].append(turn)
            previous = turn

    for chain in chains:
        attempts = chain["turns"]
        last = attempts[-1]
        chain["accepted"] = (
            not last["needsRework"] if last["feedbackKnown"] else None
        )
        chain["attempts"] = len(attempts)
        chain["totalTokens"] = sum(
            item["totalTokens"] or item["inputTokens"] + item["outputTokens"]
            for item in attempts
        )
        chain["effectiveTokens"] = sum(effective_token_cost(item) for item in attempts)
        chain["cachedInputTokens"] = sum(item["cachedInputTokens"] for item in attempts)
        chain["reworkTokens"] = sum(
            item["totalTokens"] or item["inputTokens"] + item["outputTokens"]
            for item in attempts[1:]
        )
        chain["activeSeconds"] = sum(
            max(0.0, (item["endedAt"] or 0) - (item["startedAt"] or 0))
            for item in attempts
        )
        chain["complexity"] = attempts[0]["complexity"]
        chain["tokensPerComplexity"] = chain["effectiveTokens"] / max(
            1.0, chain["complexity"]
        )
        chain["secondsPerComplexity"] = chain["activeSeconds"] / max(
            1.0, chain["complexity"]
        )
        chain["manualFeedback"] = any(item["manualFeedback"] for item in attempts)
    return chains


def write_ledger(chains: list[dict[str, Any]]) -> None:
    LEDGER_PATH.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(
        prefix="task-ledger-",
        suffix=".jsonl",
        dir=LEDGER_PATH.parent,
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            for chain in sorted(chains, key=lambda item: item["startedAt"] or 0):
                record = {
                    "chainId": chain["chainId"],
                    "threadId": chain["threadId"],
                    "model": chain["model"],
                    "category": chain["category"],
                    "categoryLabel": chain["categoryLabel"],
                    "startedAt": int(chain["startedAt"] or 0),
                    "attempts": chain["attempts"],
                    "accepted": chain["accepted"],
                    "totalTokens": chain["totalTokens"],
                    "effectiveTokens": round(chain["effectiveTokens"], 1),
                    "cachedInputTokens": chain["cachedInputTokens"],
                    "reworkTokens": chain["reworkTokens"],
                    "activeSeconds": round(chain["activeSeconds"], 1),
                    "complexity": round(chain["complexity"], 2),
                    "tokensPerComplexity": round(chain["tokensPerComplexity"], 1),
                    "secondsPerComplexity": round(chain["secondsPerComplexity"], 1),
                    "manualFeedback": chain["manualFeedback"],
                }
                handle.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")))
                handle.write("\n")
        os.replace(temporary, LEDGER_PATH)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def ratio_score(value: float, median: float) -> float:
    if value <= 0 or median <= 0:
        return 50.0
    return max(0.0, min(100.0, 50.0 + 40.0 * math.log2(median / value)))


def bayesian_rate(
    successes: float,
    observations: float,
    prior_mean: float = 0.5,
    prior_strength: float = 4.0,
) -> float:
    return (successes + prior_mean * prior_strength) / (
        observations + prior_strength
    )


def comparable_score(index: float, samples: int) -> float:
    raw = ratio_score(index, 1.0)
    reliability = 1 - math.exp(-max(0, samples) / 6)
    return 50.0 + (raw - 50.0) * reliability


def recency_weight(timestamp: Any) -> float:
    try:
        age_days = max(0.0, (time.time() - float(timestamp or 0)) / 86400)
    except (TypeError, ValueError):
        age_days = PERIOD_DAYS
    return 0.5 ** (age_days / RECENCY_HALF_LIFE_DAYS)


def effective_sample_size(weights: list[float]) -> float:
    positive = [weight for weight in weights if weight > 0]
    if not positive:
        return 0.0
    total = sum(positive)
    squares = sum(weight * weight for weight in positive)
    concentration_size = total * total / squares if squares else 0.0
    # Preserve the usual concentration penalty, but also discount a uniformly
    # old sample instead of letting its scale cancel out of the formula.
    return min(concentration_size, total)


def safe_comparison_index(value: float, baseline: float) -> float:
    if value <= 0 or baseline <= 0:
        return 1.0
    return value / baseline


def weighted_median(values: list[tuple[float, float]]) -> float:
    valid = sorted(
        (float(value), float(weight))
        for value, weight in values
        if value > 0 and weight > 0
    )
    if not valid:
        return 0.0
    midpoint = sum(weight for _, weight in valid) / 2
    cumulative = 0.0
    for value, weight in valid:
        cumulative += weight
        if cumulative >= midpoint:
            return value
    return valid[-1][0]


def robust_recent_median(samples: list[tuple[float, Any]]) -> float:
    valid = [
        (float(value), timestamp)
        for value, timestamp in samples
        if value is not None and float(value) > 0
    ]
    if not valid:
        return 0.0

    logs = [math.log(value) for value, _ in valid]
    center = statistics.median(logs)
    mad = statistics.median(abs(value - center) for value in logs)
    spread = max(0.12, mad * 1.4826)
    lower = center - OUTLIER_MAD_LIMIT * spread
    upper = center + OUTLIER_MAD_LIMIT * spread
    weighted_logs = [
        (max(lower, min(upper, math.log(value))), recency_weight(timestamp))
        for value, timestamp in valid
    ]
    result = weighted_median(
        [(math.exp(value), weight) for value, weight in weighted_logs]
    )
    return result


def weighted_available(parts: list[tuple[float | None, float]]) -> float:
    present = [(value, weight) for value, weight in parts if value is not None]
    if not present:
        return 50.0
    weight_sum = sum(weight for _, weight in present)
    return sum(float(value) * weight for value, weight in present) / weight_sum


def aggregate(turns: list[dict[str, Any]], chains: list[dict[str, Any]]) -> dict[str, Any]:
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for turn in turns:
        grouped[turn["model"]].append(turn)

    chains_by_model: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for chain in chains:
        chains_by_model[chain["model"]].append(chain)

    accepted_by_category: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for chain in chains:
        if chain["accepted"] is True:
            accepted_by_category[chain["category"]].append(chain)
    category_token_baseline = {
        category: robust_recent_median(
            [
                (chain["tokensPerComplexity"], chain["startedAt"])
                for chain in items
                if chain["tokensPerComplexity"] > 0
            ]
        )
        for category, items in accepted_by_category.items()
        if any(chain["tokensPerComplexity"] > 0 for chain in items)
    }
    category_time_baseline = {
        category: robust_recent_median(
            [
                (chain["secondsPerComplexity"], chain["startedAt"])
                for chain in items
                if chain["secondsPerComplexity"] > 0
            ]
        )
        for category, items in accepted_by_category.items()
        if any(chain["secondsPerComplexity"] > 0 for chain in items)
    }

    raw_models = []
    for model, items in grouped.items():
        model_chains = chains_by_model.get(model, [])
        tasks = len(model_chains)
        known_chains = [chain for chain in model_chains if chain["accepted"] is not None]
        first_pass = [
            chain
            for chain in known_chains
            if chain["accepted"] and chain["attempts"] == 1
        ]
        accepted_chains = [chain for chain in model_chains if chain["accepted"] is True]
        commands = sum(item["commands"] for item in items)
        command_failures = sum(item["commandFailures"] for item in items)
        tests = sum(item["tests"] for item in items)
        validated_tasks = [item for item in items if item["lastTestFailed"] is not None]
        complexity_sum = sum(item["complexity"] for item in items)
        output_tokens = sum(item["outputTokens"] for item in items)
        total_tokens = sum(
            item["totalTokens"] or item["inputTokens"] + item["outputTokens"]
            for item in items
        )
        cached_input_tokens = sum(item["cachedInputTokens"] for item in items)
        active_seconds = sum(
            max(0.0, (item["endedAt"] or 0) - (item["startedAt"] or 0))
            for item in items
        )

        first_pass_rate = (
            len(first_pass) / len(known_chains) if known_chains else None
        )
        weighted_known = sum(
            2.0 if chain["manualFeedback"] else 1.0 for chain in known_chains
        )
        weighted_accepted = sum(
            (2.0 if chain["manualFeedback"] else 1.0)
            for chain in known_chains
            if chain["accepted"]
        )
        weighted_first_pass = sum(
            (2.0 if chain["manualFeedback"] else 1.0)
            for chain in known_chains
            if chain["accepted"] and chain["attempts"] == 1
        )
        acceptance_rate = (
            len(accepted_chains) / len(known_chains) if known_chains else None
        )
        completion_rate = (
            sum(
                bool(
                    chain["turns"][-1]["completed"]
                    and chain["turns"][-1]["hasFinal"]
                )
                for chain in model_chains
            )
            / tasks
            if tasks
            else None
        )
        tool_success_rate = (
            (commands - command_failures) / commands if commands else None
        )
        validation_rate = (
            sum(not item["lastTestFailed"] for item in validated_tasks)
            / len(validated_tasks)
            if validated_tasks
            else None
        )

        outcome_score = weighted_available(
            [
                (bayesian_rate(weighted_accepted, weighted_known) * 100, 0.45),
                (bayesian_rate(weighted_first_pass, weighted_known) * 100, 0.25),
                (
                    bayesian_rate(
                        completion_rate * tasks if completion_rate is not None else 0,
                        tasks,
                        prior_mean=0.8,
                    )
                    * 100,
                    0.15,
                ),
                (
                    bayesian_rate(
                        commands - command_failures,
                        commands,
                        prior_mean=0.9,
                    )
                    * 100
                    if commands
                    else None,
                    0.10,
                ),
                (
                    bayesian_rate(
                        sum(not item["lastTestFailed"] for item in validated_tasks),
                        len(validated_tasks),
                        prior_mean=0.8,
                    )
                    * 100
                    if validated_tasks
                    else None,
                    0.05,
                ),
            ]
        )

        token_samples = [
            (
                chain["tokensPerComplexity"]
                / category_token_baseline[chain["category"]],
                chain["startedAt"],
            )
            for chain in accepted_chains
            if chain["category"] in category_token_baseline
            and chain["tokensPerComplexity"] > 0
        ]
        time_samples = [
            (
                chain["secondsPerComplexity"]
                / category_time_baseline[chain["category"]],
                chain["startedAt"],
            )
            for chain in accepted_chains
            if chain["category"] in category_time_baseline
            and chain["secondsPerComplexity"] > 0
        ]
        token_index = robust_recent_median(token_samples) or 1.0
        time_index = robust_recent_median(time_samples) or 1.0
        accepted_weights = [recency_weight(chain["startedAt"]) for chain in accepted_chains]
        turn_weights = [recency_weight(item["startedAt"]) for item in items]
        chain_weights = [recency_weight(chain["startedAt"]) for chain in model_chains]
        known_weights = [recency_weight(chain["startedAt"]) for chain in known_chains]
        manual_weights = [
            recency_weight(chain["startedAt"])
            for chain in model_chains
            if chain["manualFeedback"]
        ]
        effective_tokens = sum(effective_token_cost(item) for item in items)

        raw_models.append(
            {
                "name": model,
                "tasks": tasks,
                "evaluatedTasks": len(known_chains),
                "acceptedResults": len(accepted_chains),
                "firstPassRate": first_pass_rate,
                "acceptanceRate": acceptance_rate,
                "reworkRate": 1 - first_pass_rate if first_pass_rate is not None else None,
                "completionRate": completion_rate,
                "toolSuccessRate": tool_success_rate,
                "validationRate": validation_rate,
                "commands": commands,
                "tests": tests,
                "validatedTasks": len(validated_tasks),
                "manualRatings": sum(bool(item["manualFeedback"]) for item in items),
                "outputTokens": output_tokens,
                "totalTokens": total_tokens,
                "effectiveTokens": round(effective_tokens),
                "cachedInputTokens": cached_input_tokens,
                "activeSeconds": active_seconds,
                "complexityUnits": complexity_sum,
                "tokensPerComplexity": (
                    effective_tokens / complexity_sum if complexity_sum else 0
                ),
                "secondsPerComplexity": (
                    active_seconds / complexity_sum if complexity_sum else 0
                ),
                "outcomeScore": outcome_score,
                "_tokenIndex": token_index,
                "_timeIndex": time_index,
                "_acceptedEvidence": effective_sample_size(accepted_weights),
                "_effectiveTasks": effective_sample_size(turn_weights),
                "_recentFeedbackCoverage": (
                    sum(known_weights) / sum(chain_weights) if chain_weights else 0
                ),
                "_recentManualCoverage": min(
                    1.0,
                    sum(manual_weights) / max(1.0, sum(chain_weights)),
                ),
                "lastTaskAt": round(max(item["startedAt"] or 0 for item in items)),
                "tokensPerAcceptedResult": (
                    statistics.median(
                        chain["totalTokens"] for chain in accepted_chains
                    )
                    if accepted_chains
                    else 0
                ),
                "secondsPerAcceptedResult": (
                    statistics.median(
                        chain["activeSeconds"] for chain in accepted_chains
                    )
                    if accepted_chains
                    else 0
                ),
                "effectiveTokensPerAcceptedResult": (
                    statistics.median(
                        chain["effectiveTokens"] for chain in accepted_chains
                    )
                    if accepted_chains
                    else 0
                ),
                "reworkTokenShare": (
                    sum(chain["reworkTokens"] for chain in model_chains)
                    / sum(chain["totalTokens"] for chain in model_chains)
                    if sum(chain["totalTokens"] for chain in model_chains) > 0
                    else 0
                ),
            }
        )

    for model in raw_models:
        efficiency_score = comparable_score(
            model["_tokenIndex"], model["_acceptedEvidence"]
        )
        speed_score = comparable_score(
            model["_timeIndex"], model["_acceptedEvidence"]
        )
        model["efficiencyScore"] = round(efficiency_score)
        model["speedScore"] = round(speed_score)
        model["score"] = round(
            model["outcomeScore"] * 0.60
            + efficiency_score * 0.25
            + speed_score * 0.15
        )
        model["normalizedTokenIndex"] = round(model["_tokenIndex"] * 100)
        model["normalizedTimeIndex"] = round(model["_timeIndex"] * 100)
        model["tokenSavingsPercent"] = round(
            max(-200, min(80, (1 - model["_tokenIndex"]) * 100))
        )
        model["timeSavingsPercent"] = round(
            max(-200, min(80, (1 - model["_timeIndex"]) * 100))
        )
        del model["_tokenIndex"]
        del model["_timeIndex"]

        sample_confidence = 1 - math.exp(-model["_effectiveTasks"] / 10)
        feedback_coverage = model["_recentFeedbackCoverage"]
        manual_coverage = model["_recentManualCoverage"]
        signal_coverage = (
            (1 if model["commands"] else 0)
            + (1 if model["tests"] else 0)
            + (1 if model["evaluatedTasks"] else 0)
        ) / 3
        confidence = 100 * sample_confidence * (
            0.35
            + 0.30 * feedback_coverage
            + 0.20 * signal_coverage
            + 0.15 * manual_coverage
        )
        model["confidence"] = round(max(0, min(100, confidence)))
        model["effectiveSampleSize"] = round(model["_effectiveTasks"], 1)
        model["freshnessDays"] = round(
            max(0.0, (time.time() - model["lastTaskAt"]) / 86400), 1
        )
        model["outcomeScore"] = round(model["outcomeScore"])
        del model["_acceptedEvidence"]
        del model["_effectiveTasks"]
        del model["_recentFeedbackCoverage"]
        del model["_recentManualCoverage"]

        for key in (
            "firstPassRate",
            "acceptanceRate",
            "reworkRate",
            "completionRate",
            "toolSuccessRate",
            "validationRate",
        ):
            if model[key] is not None:
                model[key] = round(model[key] * 100)

        model["tokensPerComplexity"] = round(model["tokensPerComplexity"], 1)
        model["secondsPerComplexity"] = round(model["secondsPerComplexity"], 1)
        model["complexityUnits"] = round(model["complexityUnits"], 1)
        model["tokensPerAcceptedResult"] = round(model["tokensPerAcceptedResult"])
        model["secondsPerAcceptedResult"] = round(model["secondsPerAcceptedResult"], 1)
        model["effectiveTokensPerAcceptedResult"] = round(
            model["effectiveTokensPerAcceptedResult"]
        )
        model["reworkTokenShare"] = round(model["reworkTokenShare"] * 100)

    raw_models.sort(key=lambda item: (-item["score"], -item["confidence"], item["name"]))

    category_recommendations = []
    category_groups: dict[str, dict[str, list[dict[str, Any]]]] = defaultdict(
        lambda: defaultdict(list)
    )
    for chain in chains:
        category_groups[chain["category"]][chain["model"]].append(chain)

    for category, model_groups in category_groups.items():
        candidates = []
        for model, model_chains in model_groups.items():
            known = [chain for chain in model_chains if chain["accepted"] is not None]
            accepted = [chain for chain in model_chains if chain["accepted"] is True]
            if not known or not accepted:
                continue
            known_weights = [recency_weight(chain["startedAt"]) for chain in known]
            first_pass_weight = sum(
                recency_weight(chain["startedAt"])
                for chain in known
                if chain["accepted"] and chain["attempts"] == 1
            )
            accepted_weights = [recency_weight(chain["startedAt"]) for chain in accepted]
            candidates.append(
                {
                    "model": model,
                    "tasks": len(model_chains),
                    "known": len(known),
                    "evidence": effective_sample_size(known_weights),
                    "successProbability": bayesian_rate(
                        first_pass_weight,
                        sum(known_weights),
                    ),
                    "acceptedCost": robust_recent_median(
                        [(chain["totalTokens"], chain["startedAt"]) for chain in accepted]
                    ),
                    "economyCost": robust_recent_median(
                        [
                            (chain["tokensPerComplexity"], chain["startedAt"])
                            for chain in accepted
                        ]
                    ),
                    "acceptedSeconds": robust_recent_median(
                        [(chain["activeSeconds"], chain["startedAt"]) for chain in accepted]
                    ),
                    "speedCost": robust_recent_median(
                        [
                            (chain["secondsPerComplexity"], chain["startedAt"])
                            for chain in accepted
                        ]
                    ),
                }
            )

        if not candidates:
            continue
        category_cost_median = statistics.median(
            item["economyCost"] for item in candidates
        )
        category_time_median = statistics.median(
            item["speedCost"] for item in candidates
        )
        for item in candidates:
            item["score"] = round(
                item["successProbability"] * 60
                + comparable_score(
                    safe_comparison_index(item["economyCost"], category_cost_median),
                    item["evidence"],
                )
                * 0.25
                + comparable_score(
                    safe_comparison_index(item["speedCost"], category_time_median),
                    item["evidence"],
                )
                * 0.15
            )
            item["confidence"] = round(
                100 * (1 - math.exp(-item["evidence"] / 7))
            )
        best = max(candidates, key=lambda item: (item["score"], item["confidence"]))
        label = next(
            (
                chain["categoryLabel"]
                for chain in chains
                if chain["category"] == category
            ),
            category,
        )
        category_recommendations.append(
            {
                "category": category,
                "label": label,
                "model": best["model"],
                "score": best["score"],
                "confidence": best["confidence"],
                "tasks": best["tasks"],
                "acceptedCost": round(best["acceptedCost"]),
            }
        )

    category_recommendations.sort(
        key=lambda item: (-item["confidence"], item["label"])
    )

    latest_unrated = None
    candidates = [
        turn
        for turn in turns
        if turn["completed"]
        and turn["hasFinal"]
        and not turn["manualFeedback"]
        and (time.time() - (turn["startedAt"] or 0)) <= 7 * 86400
    ]
    if candidates:
        latest = max(candidates, key=lambda item: item["startedAt"] or 0)
        preview = re.sub(r"\s+", " ", latest["prompt"]).strip()
        if len(preview) > 78:
            preview = preview[:75].rstrip() + "..."
        latest_unrated = {
            "turnId": latest["turnId"],
            "model": latest["model"],
            "startedAt": int(latest["startedAt"] or 0),
            "promptPreview": preview,
        }

    return {
        "version": 3,
        "generatedAt": int(time.time()),
        "periodDays": PERIOD_DAYS,
        "methodology": {
            "resultWeight": 60,
            "efficiencyWeight": 25,
            "speedWeight": 15,
            "acceptanceShareOfResult": 45,
            "firstPassShareOfResult": 25,
            "comparison": "category-and-complexity-normalized",
            "tokenMetric": "relative-effective-token-load",
            "recencyHalfLifeDays": RECENCY_HALF_LIFE_DAYS,
            "outlierMethod": "log-median-mad-winsorization",
            "note": (
                "Relative local score, not quota accounting. Quality uses accepted "
                "outcomes; economy and speed compare similar task categories after "
                "complexity normalization and small-sample shrinkage."
            ),
        },
        "models": raw_models,
        "categoryRecommendations": category_recommendations,
        "latestUnrated": latest_unrated,
    }


def atomic_write(value: dict[str, Any]) -> None:
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(
        prefix="model-quality-",
        suffix=".json",
        dir=OUTPUT_PATH.parent,
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(value, handle, ensure_ascii=False, separators=(",", ":"))
        os.replace(temporary, OUTPUT_PATH)
    finally:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass


def sources_changed() -> bool:
    if not OUTPUT_PATH.exists() or not LEDGER_PATH.exists():
        return True
    try:
        generated = min(OUTPUT_PATH.stat().st_mtime, LEDGER_PATH.stat().st_mtime)
    except OSError:
        return True

    try:
        if Path(__file__).stat().st_mtime > generated:
            return True
    except OSError:
        return True

    if FEEDBACK_PATH.exists():
        try:
            if FEEDBACK_PATH.stat().st_mtime > generated:
                return True
        except OSError:
            return True

    if not SESSION_ROOT.exists():
        return False
    for path in SESSION_ROOT.rglob("*.jsonl"):
        try:
            stat = path.stat()
        except OSError:
            continue
        if stat.st_mtime >= CUTOFF and stat.st_mtime > generated:
            return True
    return False


def main() -> None:
    if not sources_changed():
        return
    turns = parse_sessions()
    enrich_outcomes(turns, load_feedback())
    for turn in turns:
        turn["complexity"] = complexity(turn)
        turn["category"], turn["categoryLabel"] = classify_category(turn["prompt"])
    chains = build_chains(turns)
    write_ledger(chains)
    atomic_write(aggregate(turns, chains))


if __name__ == "__main__":
    main()
