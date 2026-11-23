#!/usr/bin/env python3
"""Measure what /feat and /fix runs cost, from Claude Code's session transcripts.

Reads the transcripts Claude Code keeps on this machine
($CLAUDE_CONFIG_DIR/projects, else ~/.claude/projects): each session's
<session>.jsonl and its subagents/agent-<id>.jsonl and agent-<id>.meta.json.
Finds the /feat and /fix runs of a repo and prints, per skill, the medians of
what the coordinator and each agent type cost, where the wall-clock time
went, and what an agent's first request is made of.

Read-only and offline: files are only opened for reading, nothing is written
but the report on stdout (usage errors on stderr), no network, no
subprocess. It prints only counts, tool names, agent types, model ids,
session ids, dates and repo paths, never a message, prompt, tool output,
file content or error text.

Python 3.11 or later, standard library only.
Usage: python3 measure.py [options]   (--help lists them)
"""

import argparse
import json
import math
import os
import re
import statistics
import sys
from collections import Counter
from datetime import date, datetime

# --- defaults and options ----------------------------------------------------

# The one place the default weights live: --help and every report print them.
DEFAULT_WEIGHTS = {
    "tokens": {
        "input": 1,
        "cache_read": 0.1,
        "output": 5,
        "cache_write_1h": 2,
        "cache_write_5m": 1.25,
    },
    "models": {"haiku": 1, "sonnet": 3, "opus": 5},
}
TOKEN_LABELS = {
    "input": "input",
    "cache_read": "cache read",
    "output": "output",
    "cache_write_1h": "cache write 1h",
    "cache_write_5m": "cache write 5m",
}
TOKEN_KINDS = ("input", "cache_write_5m", "cache_write_1h", "cache_read", "output")

SPAWN_TOOLS = ("Agent", "Task")
WAIT_TOOLS = SPAWN_TOOLS + ("SendMessage",)  # calls whose result the coordinator waits for
SHIPPER = "feat-shipper"


def wnum(x):
    """A weight or price as written: 1, 0.1, 1.25."""
    return str(int(x)) if float(x).is_integer() else repr(float(x))


def weights_line(weights):
    tokens = ", ".join(f"{TOKEN_LABELS[k]} {wnum(weights['tokens'][k])}" for k in TOKEN_LABELS)
    models = ", ".join(f"{safe(k)} {wnum(v)}" for k, v in weights["models"].items())
    return f"weights: {tokens}; {models}"


def prices_line(prices):
    return "prices: " + ", ".join(f"{safe(k)} {wnum(v)}/Mtok" for k, v in prices.items())


class WeightsError(Exception):
    """A bad --weights file; the message names a section and key, never other content."""


def _no_constant(name):
    raise WeightsError(f"{name} is not a number here")


def valid_number(v):
    """An int or float, not a bool, finite and >= 0."""
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return False
    try:
        return math.isfinite(v) and v >= 0
    except OverflowError:  # an int too large for a float
        return False


def load_weights(path):
    """The weights in effect: the file's sections merged over the defaults."""
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f, parse_constant=_no_constant)
    except OSError:
        raise WeightsError("cannot be read") from None
    except (ValueError, RecursionError):
        raise WeightsError("not valid JSON") from None
    if not isinstance(data, dict):
        raise WeightsError("not a JSON object")
    weights = {"tokens": dict(DEFAULT_WEIGHTS["tokens"]), "models": dict(DEFAULT_WEIGHTS["models"]), "prices": {}}
    for section, values in data.items():
        if section not in weights:
            raise WeightsError(f"unknown section {safe(section)}")
        if not isinstance(values, dict):
            raise WeightsError(f"section {section} is not an object")
        for key, value in values.items():
            if section == "tokens" and key not in TOKEN_LABELS:
                raise WeightsError(f"unknown key tokens.{safe(key)}")
            if not valid_number(value):
                raise WeightsError(f"{section}.{safe(key)} must be a finite number >= 0")
            weights[section][key] = value
    return weights


def parse_date(text):
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", text):
        raise argparse.ArgumentTypeError("dates are YYYY-MM-DD")
    try:
        return date.fromisoformat(text)
    except ValueError:
        raise argparse.ArgumentTypeError("not a valid date (YYYY-MM-DD)") from None


def parse_args(argv):
    parser = argparse.ArgumentParser(
        prog="measure.py",
        description=(
            "Measure what /feat and /fix runs cost, from the session transcripts\n"
            "Claude Code keeps on this machine. Read-only and offline."
        ),
        epilog=weights_line(DEFAULT_WEIGHTS),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    where = parser.add_mutually_exclusive_group()
    where.add_argument(
        "--project",
        metavar="PATH",
        help="runs of the repo at PATH (default: the repo of the current directory, with its worktrees)",
    )
    where.add_argument("--all", action="store_true", help="every repo: one block per repo, then the total")
    parser.add_argument(
        "--since", metavar="YYYY-MM-DD", type=parse_date, help="runs invoked on or after this local date"
    )
    parser.add_argument(
        "--until", metavar="YYYY-MM-DD", type=parse_date, help="runs invoked on or before this local date"
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--session", metavar="ID", help="one run's own figures instead of medians (any repo)")
    mode.add_argument(
        "--compare-since",
        metavar="YYYY-MM-DD",
        type=parse_date,
        help="medians before this date next to those since it, with the difference",
    )
    parser.add_argument("--weights", metavar="FILE", help="JSON file overriding weights, optionally with prices")
    parser.add_argument("--strict", action="store_true", help="exit 1 when any run in the selection was left out")
    return parser.parse_args(argv)


# --- printing ----------------------------------------------------------------

# Unicode category Cc: C0 (tab and newline included), DEL and C1; and lone
# surrogates (a JSON escape, or a file name not in UTF-8), which cannot print.
_CONTROL = re.compile(r"[\x00-\x1f\x7f-\x9f\ud800-\udfff]")


def safe(text):
    """Every string from a transcript or the filesystem is printed through this."""
    return _CONTROL.sub("?", str(text))


def count(n, noun):
    """`1 run`, `2 runs`: a noun after a count agrees with it."""
    return f"{n} {noun}" if n == 1 else f"{n} {noun}s"


def fnum(x):
    """Counts and medians: an integer, or one decimal."""
    if x is None:
        return "-"
    return str(int(x)) if float(x).is_integer() else f"{x:.1f}"


def ftok(x):
    """Tokens: integer below 10,000, then 18.2k, then 1.4M."""
    if x is None:
        return "-"
    if x < 10_000:
        return fnum(x)
    if x < 999_950:
        return f"{x / 1000:.1f}k"
    return f"{x / 1_000_000:.1f}M"


def fpct(x):
    return "-" if x is None else f"{x * 100:.0f}%"


def fmin(seconds):
    return "-" if seconds is None else f"{seconds / 60:.1f}"


def funits(x):
    return "-" if x is None else f"{x:,.0f}"


def fusd(x):
    return "-" if x is None else f"${x:,.2f}"


# --- discovery and repo resolution -------------------------------------------


def projects_dir():
    config = os.environ.get("CLAUDE_CONFIG_DIR")
    if config:
        return os.path.join(config, "projects")
    return os.path.join(os.path.expanduser("~"), ".claude", "projects")


def read_text(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def _repo_from_gitfile(holder, gitfile):
    """The repo a `.git` file belongs to: the main repo of a worktree, else its holder."""
    try:
        first = read_text(gitfile).splitlines()[0]
    except (OSError, IndexError):
        return holder
    if not first.startswith("gitdir:"):
        return holder
    gitdir = os.path.join(holder, first[len("gitdir:") :].strip())
    try:
        common = read_text(os.path.join(gitdir, "commondir")).strip()
    except OSError:
        return holder  # a submodule or a separate git dir: its own repo
    if not common:
        return holder
    return os.path.dirname(os.path.realpath(os.path.join(gitdir, common)))


def resolve_repo(cwd):
    """The repo a directory belongs to (research R7); no subprocess."""
    path = os.path.abspath(cwd)
    existing = path
    while not os.path.isdir(existing):
        parent = os.path.dirname(existing)
        if parent == existing:
            break
        existing = parent
    cur = os.path.realpath(existing)
    while True:
        git = os.path.join(cur, ".git")
        if os.path.isdir(git):
            return cur
        if os.path.isfile(git):
            return _repo_from_gitfile(cur, git)
        parent = os.path.dirname(cur)
        if parent == cur:
            return os.path.realpath(path)
        cur = parent


def discover(projects):
    """Sessions with at least one agent transcript: dicts with id, path, dir."""
    try:
        folders = sorted(os.listdir(projects))
    except OSError:
        return
    for folder in folders:
        fdir = os.path.join(projects, folder)
        try:
            names = sorted(os.listdir(fdir))
        except OSError:
            continue
        for name in names:
            if not name.endswith(".jsonl"):
                continue
            sid = name[: -len(".jsonl")]
            sdir = os.path.join(fdir, sid)
            try:
                agents = os.listdir(os.path.join(sdir, "subagents"))
            except OSError:
                continue
            if any(n.startswith("agent-") and n.endswith(".jsonl") for n in agents):
                yield {"id": sid, "path": os.path.join(fdir, name), "dir": sdir}


def peek_cwd(path):
    try:
        with open(path, "rb") as f:
            for line in f:
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                if isinstance(rec, dict) and isinstance(rec.get("cwd"), str):
                    return rec["cwd"]
    except (OSError, RecursionError):
        return None
    return None


_TAG_RAW = re.compile(rb"<command-name>\s*/?(?:logistics:)?(?:feat|fix)\s*</command-name>")
_TAG = re.compile(r"<command-name>\s*/?(?:logistics:)?(feat|fix)\s*</command-name>")
_ARGS = re.compile(r"<command-args>(.*?)</command-args>", re.DOTALL)
_AGENT_ID = re.compile(r"[A-Za-z0-9_-]+")
_TASK_ID = re.compile(r"<task-id>([A-Za-z0-9_-]+)</task-id>")


def has_tag(path):
    try:
        with open(path, "rb") as f:
            return any(_TAG_RAW.search(line) for line in f)
    except OSError:
        return False


# --- session parse -----------------------------------------------------------


class Shape(Exception):
    """A record of an unexpected shape; its text is never printed."""


BAD = object()  # a line that is not JSON


def as_dict(v):
    if v is None:
        return {}
    if not isinstance(v, dict):
        raise Shape
    return v


def as_list(v):
    if v is None:
        return []
    if not isinstance(v, list):
        raise Shape
    return v


def as_str(v):
    if v is not None and not isinstance(v, str):
        raise Shape
    return v


def as_count(v):
    if v is None:
        return 0
    if isinstance(v, bool) or not isinstance(v, int) or v < 0:
        raise Shape
    return v


def stamp(rec):
    """The record's timestamp as an aware datetime, or None."""
    v = rec.get("timestamp")
    if not isinstance(v, str):
        return None
    try:
        t = datetime.fromisoformat(v)
    except ValueError:
        return None
    return t if t.tzinfo is not None else None


def local_date(t):
    return t.astimezone().date().isoformat()


def read_records(path):
    out = []
    with open(path, "rb") as f:
        for line in f:
            if not line.strip():
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                out.append(BAD)
                continue
            if not isinstance(rec, dict):
                raise Shape
            out.append(rec)
    return out


def blocks(msg):
    content = msg.get("content")
    if content is None or isinstance(content, str):
        return []
    out = as_list(content)
    for b in out:
        as_dict(b)
    return out


def message_text(msg):
    content = msg.get("content")
    if isinstance(content, str):
        return content
    return "".join(as_str(b.get("text")) or "" for b in blocks(msg) if b.get("type") == "text")


def usage_tokens(usage):
    created = as_count(usage.get("cache_creation_input_tokens"))
    breakdown = usage.get("cache_creation")
    if breakdown is None:
        w5m, w1h = created, 0  # no breakdown: weighted as the 5-minute cache
    else:
        breakdown = as_dict(breakdown)
        w5m = as_count(breakdown.get("ephemeral_5m_input_tokens"))
        w1h = as_count(breakdown.get("ephemeral_1h_input_tokens"))
    return {
        "input": as_count(usage.get("input_tokens")),
        "cache_write_5m": w5m,
        "cache_write_1h": w1h,
        "cache_read": as_count(usage.get("cache_read_input_tokens")),
        "output": as_count(usage.get("output_tokens")),
    }


class Calls:
    """Model calls grouped by message.id: first record's time and model, last usage."""

    def __init__(self):
        self.by_id = {}

    def add(self, rec, msg, t):
        """Adds one assistant record; returns its tool_use blocks."""
        model = as_str(msg.get("model"))
        if model == "<synthetic>" or rec.get("isApiErrorMessage") is True:
            return []
        mid = as_str(msg.get("id"))
        if mid is None:
            raise Shape
        call = self.by_id.get(mid)
        if call is None:
            call = self.by_id[mid] = {"model": model or "unknown", "time": t, "usage": None, "tools": []}
        if msg.get("usage") is not None:
            call["usage"] = as_dict(msg.get("usage"))
        uses = [b for b in blocks(msg) if b.get("type") == "tool_use"]
        for b in uses:
            call["tools"].append(as_str(b.get("name")) or "unknown")
        return uses

    def finish(self):
        """The calls in order, or the left-out reason."""
        out = []
        for call in self.by_id.values():
            if call["usage"] is None:
                return None, "model call without token usage"
            out.append({"model": call["model"], "time": call["time"], "tools": call["tools"],
                        "tokens": usage_tokens(call["usage"])})
        return out, None


def first_request(recs):
    """What an agent's first request is made of (research R6), or None."""
    shape = None
    skills = files = instructions = 0
    before_call = True
    for rec in recs:
        if rec is BAD:
            continue
        kind = rec.get("type")
        if kind == "assistant":
            before_call = False
        elif kind == "api-request-shape" and shape is None:
            shape = as_dict(rec.get("shape"))
        elif kind == "attachment" and before_call:
            att = as_dict(rec.get("attachment"))
            if att.get("type") == "skill_listing":
                skills += len(as_str(att.get("content")) or "")
            elif att.get("type") == "instructions":
                for f in as_list(att.get("files")):
                    files += 1
                    instructions += len(as_str(as_dict(f).get("content")) or "")
    if shape is None:
        return None
    system = shape.get("system")
    if isinstance(system, str):
        system_chars = len(system)
    else:
        system_chars = sum(len(as_str(as_dict(b).get("text")) or "") for b in as_list(system))
    schemas = {}
    for tool in as_list(shape.get("tools")):
        tool = as_dict(tool)
        name = as_str(tool.get("name")) or "unknown"
        size = len(json.dumps(tool, separators=(",", ":"), ensure_ascii=False))
        schemas[name] = schemas.get(name, 0) + size
    return {"schemas": schemas, "tools": sum(schemas.values()), "skills": skills,
            "system": system_chars, "files": files, "instructions": instructions}


def parse_agent(path, meta_path, inv_time, spawned_type):
    """One agent of the run ({"type": ..., ...}), None if it started before
    the invocation; with a left-out reason, the agent holds only its type."""
    recs = read_records(path)
    first = next((t for t in (stamp(r) for r in recs if r is not BAD) if t is not None), None)
    if first is None or first < inv_time:
        return None, None
    agent_type, reason = None, None
    if os.path.isfile(meta_path):
        try:
            meta = json.loads(read_text(meta_path))
        except ValueError:
            reason = "unreadable line"
        else:
            agent_type = as_str(as_dict(meta).get("agentType"))
    # The type is kept even when the agent leaves the run out: a run whose
    # only feat-* agent is defective is left out, not taken for "not a run".
    agent = {"type": (agent_type or spawned_type or "unknown").rsplit(":", 1)[-1]}
    if reason or BAD in recs:
        return agent, reason or "unreadable line"
    calls = Calls()
    model_s = tool_s = 0.0
    prev = None
    for rec in recs:
        kind = rec.get("type")
        if kind not in ("assistant", "user"):
            continue  # record types not used, known or not, change nothing
        t = stamp(rec)
        if t is None:
            return agent, "event without timestamp"
        msg = as_dict(rec.get("message"))
        gap = (t - prev).total_seconds() if prev is not None else 0.0
        if kind == "assistant":
            calls.add(rec, msg, t)
            model_s += gap
        elif any(b.get("type") == "tool_result" for b in blocks(msg)):
            tool_s += gap
        prev = t
    done, reason = calls.finish()
    if reason:
        return agent, reason
    agent.update(first_time=first, calls=done, model_s=model_s, tool_s=tool_s, recs=recs)
    return agent, None


def find_invocation(recs):
    """The first human-origin /feat or /fix command (research R1): (inv, None),
    (None, reason) when it cannot be placed, or (None, None) when there is none."""
    for i, rec in enumerate(recs):
        if rec is BAD or rec.get("type") != "user" or rec.get("isSidechain") is True:
            continue
        msg = as_dict(rec.get("message"))
        match = _TAG.search(message_text(msg))
        if not match or rec.get("isMeta") is True or rec.get("isCompactSummary") is True:
            continue
        origin = rec.get("origin")
        if origin is None:
            return None, "no message origin recorded"
        if as_dict(origin).get("kind") != "human":
            continue
        t = stamp(rec)
        if t is None:
            return None, "event without timestamp"
        args = _ARGS.search(message_text(msg))
        words = args.group(1).split() if args else []
        return {"index": i, "skill": match.group(1), "resumed": bool(words) and words[0] == "resume",
                "time": t}, None
    return None, None


def _parse_session(sess, info):
    recs = read_records(sess["path"])
    for rec in recs:
        if rec is BAD:
            continue
        if info["version"] is None and isinstance(rec.get("version"), str):
            info["version"] = rec["version"]
        if info["first_time"] is None:
            info["first_time"] = stamp(rec)

    inv, reason = find_invocation(recs)
    if reason:
        return "left", reason  # parse_session checks it is a run first
    if inv is None:
        return None, None
    info["inv_time"] = inv["time"]
    info["date"] = local_date(inv["time"])

    reason = None
    calls = Calls()
    tool_names = {}
    spawn_types = {}
    spawned = {}  # agent id -> type from its spawn
    failed = Counter()
    timeline = {"agents": 0.0, "user": 0.0, "thinking": 0.0, "tools": 0.0}
    answers = 0
    # A batch ends when its last result arrives; the next counted model call is recorded in firsts.
    open_ids = set()  # tool_use ids of the current spawn batch still without a result
    batch_mid = None  # message id of the call that opened the batch
    armed = False  # the batch is complete: the next counted call is its first
    firsts = []  # message ids of the first call after each batch
    prev = inv["time"]
    for rec in recs[inv["index"] + 1 :]:
        if rec is BAD:
            reason = reason or "unreadable line"
            continue
        if rec.get("isSidechain") is True:
            continue
        kind = rec.get("type")
        if kind == "assistant":
            part = "thinking"
        elif kind == "user":
            if rec.get("isCompactSummary") is True:
                continue
            # an agent's report is a meta record too: it is the one meta record that counts
            if rec.get("isMeta") is True and as_dict(rec.get("origin")).get("kind") != "peer":
                continue
            part = None
        else:
            continue
        msg = as_dict(rec.get("message"))
        t = stamp(rec)
        if kind == "assistant":
            if t is None:
                reason = reason or "event without timestamp"
                continue
            uses = calls.add(rec, msg, t)
            mid = as_str(msg.get("id"))
            if mid in calls.by_id:
                if armed and mid != batch_mid:
                    firsts.append(mid)
                    armed = False
                waits = [as_str(b.get("id")) for b in uses if as_str(b.get("name")) in WAIT_TOOLS]
                if waits:
                    if mid != batch_mid:
                        batch_mid = mid
                        open_ids = set()
                        armed = False
                    open_ids.update(waits)
            for b in uses:
                tid = as_str(b.get("id"))
                name = as_str(b.get("name")) or "unknown"
                tool_names[tid] = name
                if name in SPAWN_TOOLS:
                    spawn_types[tid] = as_str(as_dict(b.get("input")).get("subagent_type"))
        else:
            results = [b for b in blocks(msg) if b.get("type") == "tool_result"]
            origin = as_dict(rec.get("origin"))
            if results:
                part = "tools"
                result = rec.get("toolUseResult")
                for b in results:
                    tid = as_str(b.get("tool_use_id"))
                    if tid in open_ids:
                        open_ids.discard(tid)
                        if not open_ids:
                            armed = True
                    name = tool_names.get(tid, "unknown")
                    error = b.get("is_error") is True
                    if error:
                        failed[name] += 1
                    if name not in SPAWN_TOOLS:
                        continue
                    if isinstance(result, dict):
                        aid = result.get("agentId")
                        if aid is not None:
                            if not isinstance(aid, str) or not _AGENT_ID.fullmatch(aid):
                                reason = reason or "agent transcript missing"
                            elif not os.path.isfile(os.path.join(sess["dir"], "subagents", f"agent-{aid}.jsonl")):
                                reason = reason or "agent transcript missing"
                            else:
                                spawned[aid] = spawn_types.get(tid)
                        status = result.get("status")
                    else:
                        status = None
                    if not error and status != "async_launched":
                        part = "agents"  # the agent's report, returned as the result
            elif origin.get("kind") == "peer":
                part = "agents"
                sender = origin.get("from")
                if sender is not None and (not isinstance(sender, str) or not _AGENT_ID.fullmatch(sender)):
                    reason = reason or "agent transcript missing"
            elif origin.get("kind") == "task-notification":
                # a background task ended: one of this session's agents, or the
                # coordinator's own command
                task = _TASK_ID.search(message_text(msg))
                ended_agent = task is not None and os.path.isfile(
                    os.path.join(sess["dir"], "subagents", f"agent-{task.group(1)}.jsonl")
                )
                part = "agents" if ended_agent else "tools"
            elif origin.get("kind") == "human":
                part = "user"
                answers += 1
            else:
                continue
            if t is None:
                reason = reason or "event without timestamp"
                continue
        timeline[part] += (t - prev).total_seconds()
        prev = t

    coordinator, call_reason = calls.finish()
    reason = reason or call_reason
    after_spawn = sum(1 for mid in firsts if not calls.by_id[mid]["tools"])

    agents = []
    sub = os.path.join(sess["dir"], "subagents")
    for name in sorted(os.listdir(sub)):
        if not (name.startswith("agent-") and name.endswith(".jsonl")):
            continue
        aid = name[len("agent-") : -len(".jsonl")]
        agent, agent_reason = parse_agent(
            os.path.join(sub, name), os.path.join(sub, f"agent-{aid}.meta.json"), inv["time"], spawned.get(aid)
        )
        reason = reason or agent_reason
        if agent is not None:
            agents.append(agent)
    if not any(a["type"].startswith("feat-") for a in agents):
        return None, None  # not a run
    info["checked"] = True
    if reason:
        return "left", reason

    # First request: only the first agent of each type (by its first timestamp).
    agents.sort(key=lambda a: a["first_time"])
    seen = set()
    for a in agents:
        recs_a = a.pop("recs")
        a["first_request"] = None
        if a["type"] not in seen:
            seen.add(a["type"])
            a["first_request"] = first_request(recs_a)
            a["first_of_type"] = True

    if inv["resumed"]:
        status = "resumed"
    else:
        status = "finished" if any(a["type"] == SHIPPER for a in agents) else "unfinished"
    return "run", {
        "session": sess["id"], "repo": sess["repo"], "skill": inv["skill"], "date": info["date"],
        "shipped": any(a["type"] == SHIPPER for a in agents), "status": status,
        "calls": coordinator, "failed": failed, "timeline": timeline, "answers": answers, "agents": agents,
        "after_spawn": after_spawn,
    }


def loose_records(path):
    """The JSON-object lines of a file, skipping any other line. Never raises."""
    out = []
    try:
        with open(path, "rb") as f:
            for line in f:
                try:
                    rec = json.loads(line)
                except (ValueError, RecursionError):
                    continue
                if isinstance(rec, dict):
                    out.append(rec)
    except OSError:
        pass
    return out


def spawned_types(recs):
    """Agent id -> the type its spawn asked for, from a session's records."""
    asked, out = {}, {}
    for rec in recs:
        msg = rec.get("message")
        content = msg.get("content") if isinstance(msg, dict) else None
        result = rec.get("toolUseResult")
        for b in content if isinstance(content, list) else []:
            if not isinstance(b, dict):
                continue
            tid = b.get("id") if b.get("type") == "tool_use" else b.get("tool_use_id")
            if not isinstance(tid, str):
                continue
            if b.get("type") == "tool_use" and b.get("name") in SPAWN_TOOLS and isinstance(b.get("input"), dict):
                asked[tid] = b["input"].get("subagent_type")
            elif b.get("type") == "tool_result" and isinstance(result, dict) and isinstance(result.get("agentId"), str):
                out[result["agentId"]] = asked.get(tid)
    return out


def feat_agent_in(sess, after):
    """Whether an agent transcript of the session (started at `after` or later,
    when the invocation is placed) has a feat-* type: from its meta, else from
    its spawn. Used for a run left out before its agents were read."""
    try:
        spawned = spawned_types(loose_records(sess["path"]))
        sub = os.path.join(sess["dir"], "subagents")
        for name in sorted(os.listdir(sub)):
            if not (name.startswith("agent-") and name.endswith(".jsonl")):
                continue
            aid = name[len("agent-") : -len(".jsonl")]
            if after is not None:
                first = next((t for t in map(stamp, loose_records(os.path.join(sub, name))) if t), None)
                if first is None or first < after:
                    continue
            meta = loose_records(os.path.join(sub, f"agent-{aid}.meta.json"))
            kind = meta[0].get("agentType") if meta else None
            if not isinstance(kind, str):
                kind = spawned.get(aid)
            if isinstance(kind, str) and kind.rsplit(":", 1)[-1].startswith("feat-"):
                return True
    except Exception:  # cannot tell: left out, as before this check
        return True
    return False


def parse_session(sess, defect=None):
    """A run, a left-out run, or None (not a run). Never raises, never prints.
    With `defect`, a run is left out for that reason."""
    info = {"version": None, "first_time": None, "date": None, "inv_time": None, "checked": False}
    try:
        kind, value = _parse_session(sess, info)
    except Exception:  # any shape we did not expect: left out, its text unread
        kind, value = "left", "unexpected record shape"
    if kind == "left" and not info["checked"] and not feat_agent_in(sess, info["inv_time"]):
        return None  # no feat-* agent: not a run, whatever its defect
    if kind is not None and defect:
        kind, value = "left", defect
    if kind == "run":
        return value
    if kind == "left":
        when = info["date"] or (local_date(info["first_time"]) if info["first_time"] else "unknown")
        return {"left_out": True, "session": sess["id"], "repo": sess["repo"], "date": when,
                "reason": value, "version": info["version"]}
    return None


def collect(projects, wanted, session=None):
    """Runs and left-out runs of the sessions whose repo passes `wanted`
    (with `session`, only the session of that id)."""
    runs, left = [], []
    repos = {}
    for sess in discover(projects):
        if session is not None and sess["id"] != session:
            continue
        defect = None
        try:  # the recorded directory is transcript data: guarded like the parse
            cwd = peek_cwd(sess["path"])
            if cwd is None:
                continue
            if cwd not in repos:
                repos[cwd] = resolve_repo(cwd)
            sess["repo"] = repos[cwd]
        except Exception:  # its repo is unknown; the error text is never printed
            sess["repo"], defect = "unknown", "unexpected record shape"
        if not wanted(sess["repo"]) or not has_tag(sess["path"]):
            continue
        result = parse_session(sess, defect)
        if result is None:
            continue
        (left if result.get("left_out") else runs).append(result)
    return runs, left


# --- per-run figures ---------------------------------------------------------


def lookup(model, table, missing):
    """A model's value in `models` or `prices`: the id, else one of its
    `-`-separated parts, else the highest value given (noted in `missing`)."""
    if model in table:
        return table[model]
    for part in model.split("-"):
        if part in table:
            return table[part]
    top = max(table.values())
    missing[model] = top
    return top


def call_base(call, weights):
    return sum(call["tokens"][k] * weights["tokens"][k] for k in TOKEN_KINDS)


def call_units(call, weights, missing):
    return call_base(call, weights) * lookup(call["model"], weights["models"], missing["models"])


def call_usd(call, weights, missing):
    return call_base(call, weights) * lookup(call["model"], weights["prices"], missing["prices"]) / 1_000_000


def context(call):
    t = call["tokens"]
    return t["input"] + t["cache_write_5m"] + t["cache_write_1h"] + t["cache_read"]


def call_kind(call):
    if any(name in SPAWN_TOOLS for name in call["tools"]):
        return "spawn"
    return "chore" if call["tools"] else "text"


def mean(values):
    return sum(values) / len(values) if values else None


def share(part, total):
    return part / total if total else 0.0


def run_figures(run, weights, missing):
    coord = run["calls"]
    coord_units = sum(call_units(c, weights, missing) for c in coord)
    by_type = {}
    for a in run["agents"]:
        by_type.setdefault(a["type"], []).append(a)
    type_units = {
        t: sum(call_units(c, weights, missing) for a in lst for c in a["calls"]) for t, lst in by_type.items()
    }
    total = coord_units + sum(type_units.values())

    kinds = Counter(call_kind(c) for c in coord)
    contexts = [context(c) for c in coord]
    figs = {
        "coord": {
            "after_spawn": run["after_spawn"], "calls": len(coord), "spawn": kinds["spawn"], "chore": kinds["chore"], "text": kinds["text"],
            "ctx_first": contexts[0] if contexts else None,
            "ctx_median": statistics.median(contexts) if contexts else None,
            "ctx_max": max(contexts) if contexts else None,
            "share": share(coord_units, total),
        },
        "failed": Counter(run["failed"]),
        "types": {},
    }
    for t, lst in by_type.items():
        firsts = [context(a["calls"][0]) for a in lst if a["calls"]]
        fr = next((a["first_request"] for a in lst if a.get("first_of_type")), None)
        if fr is not None:
            parts_total = fr["tools"] + fr["skills"] + fr["system"] + fr["instructions"]
            fr = dict(fr, total=parts_total, **{f"{k}_share": share(fr[k], parts_total)
                                                for k in ("tools", "skills", "system", "instructions")})
        figs["types"][t] = {
            "spawns": len(lst),
            "calls": mean([len(a["calls"]) for a in lst]),
            "ctx_first": mean(firsts),
            "share": share(type_units[t], total),
            "model_s": mean([a["model_s"] for a in lst]),
            "tool_s": mean([a["tool_s"] for a in lst]),
            "first_request": fr,
        }
    wall = dict(run["timeline"])
    duration = sum(wall.values())
    for k in list(wall):
        wall[f"{k}_share"] = share(wall[k], duration)
    wall["duration"] = duration
    figs["wall"] = wall
    figs["answers"] = run["answers"]
    tokens = dict.fromkeys(TOKEN_KINDS, 0)
    every = coord + [c for a in run["agents"] for c in a["calls"]]
    for c in every:
        for k in TOKEN_KINDS:
            tokens[k] += c["tokens"][k]
    figs["tokens"] = {
        "input": tokens["input"],
        "cache_write": tokens["cache_write_5m"] + tokens["cache_write_1h"],
        "cache_read": tokens["cache_read"],
        "output": tokens["output"],
        "units": total,
        # Money only from prices the user gave: None prints no USD row.
        "usd": sum(call_usd(c, weights, missing) for c in every) if weights.get("prices") else None,
    }
    return figs


# --- aggregation -------------------------------------------------------------


def median(values):
    values = [v for v in values if v is not None]
    return statistics.median(values) if values else None


def aggregate(figs):
    """Medians over runs (research R10); failed tool calls as totals."""
    agg = {"n": len(figs)}
    agg["coord"] = {k: median([f["coord"][k] for f in figs]) for k in figs[0]["coord"]}
    agg["failed"] = Counter()
    for f in figs:
        agg["failed"].update(f["failed"])
    agg["types"] = {}
    for t in sorted({t for f in figs for t in f["types"]}):
        per = [f["types"][t] for f in figs if t in f["types"]]
        row = {k: median([p[k] for p in per]) for k in ("spawns", "calls", "ctx_first", "share", "model_s", "tool_s")}
        row["runs"] = len(per)
        recorded = [p["first_request"] for p in per if p["first_request"] is not None]
        row["first_request"] = None
        if recorded:
            fr = {k: median([r[k] for r in recorded]) for k in recorded[0] if k != "schemas"}
            names = {n for r in recorded for n in r["schemas"]}
            fr["schemas"] = {n: median([r["schemas"][n] for r in recorded if n in r["schemas"]]) for n in names}
            row["first_request"] = fr
        agg["types"][t] = row
    agg["wall"] = {k: median([f["wall"][k] for f in figs]) for k in figs[0]["wall"]}
    agg["answers"] = median([f["answers"] for f in figs])
    agg["tokens"] = {k: median([f["tokens"][k] for f in figs]) for k in figs[0]["tokens"]}
    return agg


# --- rendering ---------------------------------------------------------------

LABEL = 28
VALUE = 8
WALL_ROWS = (
    ("agents", "agents working"),
    ("user", "waiting for the user"),
    ("thinking", "coordinator thinking"),
    ("tools", "coordinator tools"),
)
FR_LABEL = 44


def row(label, value):
    return f"  {label:<{LABEL}}{value:>{VALUE}}"


def by_count(counts):
    return sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))


def render_block(heading, agg, single=False):
    """One skill block: medians over runs, or (single) one run's own values."""
    c = agg["coord"]
    lines = [heading, "", "Coordinator"]
    lines += [
        row("model calls", fnum(c["calls"])),
        row("spawn an agent", fnum(c["spawn"])),
        row("chores", fnum(c["chore"])),
        row("text only", fnum(c["text"])),
        row("text only after a spawn", fnum(c["after_spawn"])),
        row("context, first call", ftok(c["ctx_first"])),
        row("context, median of calls", ftok(c["ctx_median"])),
        row("context, max of calls", ftok(c["ctx_max"])),
        row("cost share", fpct(c["share"])),
    ]
    failed = ", ".join(f"{safe(name)} {n}" for name, n in by_count(agg["failed"])) or "none"
    failed_label = "failed tool calls" if single else f"failed tool calls (total over {count(agg['n'], 'run')})"
    lines.append(f"  {failed_label}  {failed}")

    # One run: no `runs` column, and `spawns` rather than `spawns/run`.
    order = sorted(agg["types"], key=lambda t: (-(agg["types"][t]["share"] or 0), t))
    runs_head = "" if single else f"{'runs':>6}"
    lines += [
        "",
        "Agents",
        f"  {'type':<24}{runs_head}{'spawns' if single else 'spawns/run':>12}{'calls/spawn':>13}{'ctx first':>11}"
        f"{'cost share':>12}{'model min':>11}{'tool min':>10}",
    ]
    for t in order:
        x = agg["types"][t]
        runs_cell = "" if single else f"{x['runs']:>6}"
        lines.append(
            f"  {safe(t):<24}{runs_cell}{fnum(x['spawns']):>12}{fnum(x['calls']):>13}{ftok(x['ctx_first']):>11}"
            f"{fpct(x['share']):>12}{fmin(x['model_s']):>11}{fmin(x['tool_s']):>10}"
        )

    w = agg["wall"]
    lines += ["", f"{'Wall clock':<{LABEL + 2}}{'min':>{VALUE}}{'share':>7}"]
    for key, label in WALL_ROWS:
        lines.append(f"  {label:<{LABEL}}{fmin(w[key]):>{VALUE}}{fpct(w[key + '_share']):>7}")
    lines.append(row("run duration", fmin(w["duration"])))
    lines.append(row("user answers", fnum(agg["answers"])))

    lines += ["", "First request (characters, from each type's first spawn in a run)"]
    for t in order:
        fr = agg["types"][t]["first_request"]
        if fr is None:
            lines.append(f"  {safe(t)}  not recorded")
            continue
        lines.append(f"  {safe(t)}")
        parts = (
            ("tools", "tools"),
            ("skills", "skills listing"),
            ("system", "system prompt (includes Claude Code's own)"),
            ("instructions", f"instructions ({fnum(fr['files'])} files)"),
        )
        for key, label in parts:
            lines.append(f"    {label:<{FR_LABEL}}{fnum(fr[key]):>{VALUE}}{fpct(fr[key + '_share']):>7}")
        lines.append(f"    {'total':<{FR_LABEL}}{fnum(fr['total']):>{VALUE}}")
        schemas = ", ".join(f"{safe(n)} {fnum(v)}" for n, v in by_count(fr["schemas"])) or "none"
        lines.append(f"    tool schemas: {schemas}")

    tk = agg["tokens"]
    lines += [
        "",
        "Tokens (per run)",
        row("input", ftok(tk["input"])),
        row("cache write", ftok(tk["cache_write"])),
        row("cache read", ftok(tk["cache_read"])),
        row("output", ftok(tk["output"])),
        row("cost units", funits(tk["units"])),
    ]
    if tk.get("usd") is not None:
        lines.append(row("USD", fusd(tk["usd"])))
    return lines


# --- comparison (--compare-since) --------------------------------------------

NO_RUNS = "no runs"


def fpp(x):
    """A difference of shares: whole percentage points."""
    return f"{x * 100:.0f}pp"


def signed(fmt, d):
    """A difference in the figure's own format, signed unless it shows as zero."""
    text = fmt(abs(d))
    if not re.search("[1-9]", text):
        return text
    return ("+" if d > 0 else "-") + text


def pick(agg, *keys):
    """One side's value, or None when the side or the item is missing."""
    v = agg
    for k in keys:
        if not isinstance(v, dict) or k not in v:
            return None
        v = v[k]
    return v


def render_compare(heading, before, since):
    """One skill block with before, since and diff (since - before) columns.

    A side with no run (None) prints `no runs`; an item missing on one side
    prints `-` there; either leaves the diff empty. No statistical wording.
    """

    def cells(keys, fmt, dfmt=None, diff=True):
        b, s = pick(before, *keys), pick(since, *keys)
        cb = NO_RUNS if before is None else fmt(b)
        cs = NO_RUNS if since is None else fmt(s)
        d = signed(dfmt or fmt, s - b) if diff and b is not None and s is not None else ""
        return f"{cb:>{VALUE}}{cs:>{VALUE}}{d:>{VALUE}}"

    def line(label, keys, fmt, dfmt=None, indent=2, width=LABEL, diff=True):
        return f"{' ' * indent}{label:<{width}}{cells(keys, fmt, dfmt, diff)}".rstrip()

    def head(title, width=LABEL + 2):
        return f"{title:<{width}}{'before':>{VALUE}}{'since':>{VALUE}}{'diff':>{VALUE}}"

    def union(*keys):
        return {k for side in (before, since) for k in (pick(side, *keys) or {})}

    def order(names, keys):
        """Since's value (at keys(name)) descending, then before's, then the name."""
        return sorted(names, key=lambda n: (-(pick(since, *keys(n)) or 0), -(pick(before, *keys(n)) or 0), n))

    lines = [heading, "", head("Coordinator")]
    for key, label, fmt, dfmt in (
        ("calls", "model calls", fnum, None),
        ("spawn", "spawn an agent", fnum, None),
        ("chore", "chores", fnum, None),
        ("text", "text only", fnum, None),
        ("after_spawn", "text only after a spawn", fnum, None),
        ("ctx_first", "context, first call", ftok, None),
        ("ctx_median", "context, median of calls", ftok, None),
        ("ctx_max", "context, max of calls", ftok, None),
        ("share", "cost share", fpct, fpp),
    ):
        lines.append(line(label, ("coord", key), fmt, dfmt))
    # Totals over different numbers of runs do not subtract: no diff here.
    lines.append("  failed tool calls (total over runs)")
    lines.append(line("runs", ("n",), fnum, indent=4, width=LABEL - 2, diff=False))
    tools = order(union("failed"), lambda n: ("failed", n))
    lines += [line(safe(n), ("failed", n), fnum, indent=4, width=LABEL - 2, diff=False) for n in tools]
    if not tools:
        lines.append("    none")

    types = order(union("types"), lambda t: ("types", t, "share"))
    lines += ["", head("Agents")]
    for t in types:
        lines.append(f"  {safe(t)}")
        for key, label, fmt, dfmt in (
            ("runs", "runs", fnum, None),
            ("spawns", "spawns/run", fnum, None),
            ("calls", "calls/spawn", fnum, None),
            ("ctx_first", "ctx first", ftok, None),
            ("share", "cost share", fpct, fpp),
            ("model_s", "model min", fmin, None),
            ("tool_s", "tool min", fmin, None),
        ):
            lines.append(line(label, ("types", t, key), fmt, dfmt, indent=4, width=LABEL - 2))

    lines += ["", head("Wall clock")]
    for key, label in WALL_ROWS:
        lines.append(line(f"{label}, min", ("wall", key), fmin))
        lines.append(line(f"{label}, share", ("wall", key + "_share"), fpct, fpp))
    lines.append(line("run duration, min", ("wall", "duration"), fmin))
    lines.append(line("user answers", ("answers",), fnum))

    lines += ["", "First request (characters, from each type's first spawn in a run)", head("", FR_LABEL + 4)]
    for t in types:
        fr = ("types", t, "first_request")
        if pick(before, *fr) is None and pick(since, *fr) is None:
            lines.append(f"  {safe(t)}  not recorded")
            continue
        lines.append(f"  {safe(t)}")
        for key, label in (
            ("tools", "tools"),
            ("skills", "skills listing"),
            ("system", "system prompt (includes Claude Code's own)"),
            ("files", "instructions files"),
            ("instructions", "instructions"),
            ("total", "total"),
        ):
            lines.append(line(label, (*fr, key), fnum, indent=4, width=FR_LABEL))
        lines.append("    tool schemas")
        for n in order(union(*fr, "schemas"), lambda n: (*fr, "schemas", n)):
            lines.append(line(safe(n), (*fr, "schemas", n), fnum, indent=6, width=FR_LABEL - 2))

    lines += ["", head("Tokens (per run)")]
    for key, label, fmt in (
        ("input", "input", ftok),
        ("cache_write", "cache write", ftok),
        ("cache_read", "cache read", ftok),
        ("output", "output", ftok),
        ("units", "cost units", funits),
        ("usd", "USD", fusd),
    ):
        if key == "usd" and pick(before, "tokens", "usd") is None and pick(since, "tokens", "usd") is None:
            continue  # no prices given: no money anywhere
        lines.append(line(label, ("tokens", key), fmt))
    return lines


def run_row(run, with_status):
    cells = [safe(run["session"]), run["date"], f"/{run['skill']}"]
    if with_status:
        cells.append("finished" if run["shipped"] else "unfinished")
    cells.append(safe(run["repo"]))
    return "  " + "  ".join(cells)


def window_text(since, until):
    """`, <since> to <until>` when the dates are bounded, else nothing."""
    if since is None and until is None:
        return ""
    return f", {since.isoformat() if since else 'start'} to {until.isoformat() if until else 'now'}"


def skill_blocks(runs, figs, compare_since):
    """The per-skill blocks over these runs: medians, or before / since."""
    sections = []
    for skill in ("feat", "fix"):
        done = [r for r in runs if r["skill"] == skill and r["status"] == "finished"]
        if not done:
            continue
        if compare_since is None:
            heading = f"== /{skill}: {count(len(done), 'finished run')} (medians) =="
            sections.append(render_block(heading, aggregate([figs[id(r)] for r in done])))
            continue
        # D itself falls in "since"; ISO dates compare as strings.
        d = compare_since.isoformat()
        before = [figs[id(r)] for r in done if r["date"] < d]
        since = [figs[id(r)] for r in done if r["date"] >= d]
        heading = f"== /{skill}: before {d}: {count(len(before), 'run')} | since {d}: {count(len(since), 'run')} =="
        sections.append(render_compare(
            heading, aggregate(before) if before else None, aggregate(since) if since else None))
    return sections


def header(runs, left, projects, where, weights, window):
    counts = Counter(r["status"] for r in runs)
    return [
        f"measure: /feat and /fix runs{where}",
        f"from {safe(projects)}{window}",
        f"runs: {len(runs)} counted ({counts['finished']} finished, {counts['unfinished']} unfinished, "
        f"{counts['resumed']} resumed), {len(left)} left out",
        weights_line(weights),
    ] + ([prices_line(weights["prices"])] if weights.get("prices") else [])


def missing_lines(missing):
    """The models weighted, or priced, as the highest value given."""
    lines = []
    if missing["models"]:
        lines.append("unweighted models: " + ", ".join(
            f"{safe(m)} (weighted as {wnum(w)})" for m, w in sorted(missing["models"].items())))
    if missing["prices"]:
        lines.append("unpriced models: " + ", ".join(
            f"{safe(m)} (priced as {wnum(p)}/Mtok)" for m, p in sorted(missing["prices"].items())))
    return lines


def left_row(item):
    version = f"Claude Code {safe(item['version'])}" if item["version"] else "unknown"
    cells = [safe(item["session"]), item["date"], item["reason"], f"({version})", safe(item["repo"])]
    return "  " + "  ".join(cells)


def left_lines(left):
    """The `left out:` list, printed once per command (none when empty)."""
    if not left:
        return []
    ordered = sorted(left, key=lambda x: (x["date"], x["repo"], x["session"]))
    return ["left out:"] + [left_row(x) for x in ordered]


def session_report(runs, left, projects, session, weights, window=""):
    """--session: the run's own figures in one block, or its left-out row."""
    missing = {"models": {}, "prices": {}}
    sections = [header(runs, left, projects, f", session {safe(session)}", weights, window)]
    for r in sorted(runs, key=lambda r: (r["date"], r["repo"])):
        heading = f"== /{r['skill']} run {safe(r['session'])}, {r['date']}, {r['status']} =="
        sections.append(render_block(heading, aggregate([run_figures(r, weights, missing)]), single=True))
    tail = missing_lines(missing) + left_lines(left)
    if tail:
        sections.append(tail)
    print("\n\n".join("\n".join(s) for s in sections))


def report(runs, left, projects, repo, weights, compare_since=None, window=""):
    """The report; repo None means --all: one block per repo, then all repos."""
    missing = {"models": {}, "prices": {}}
    figs = {id(r): run_figures(r, weights, missing) for r in runs}
    where = " on every repo (--all)" if repo is None else f" in {safe(repo)} and its worktrees"
    sections = [header(runs, left, projects, where, weights, window)]
    if repo is None:
        for path in sorted({r["repo"] for r in runs}):
            found = skill_blocks([r for r in runs if r["repo"] == path], figs, compare_since)
            if found:
                sections += [[f"## {safe(path)}"], *found]
        found = skill_blocks(runs, figs, compare_since)
        if found:
            sections += [["## all repos"], *found]
    else:
        sections += skill_blocks(runs, figs, compare_since)
    tail = missing_lines(missing)
    for status, title, with_status in (
        ("unfinished", "unfinished runs (not in the medians):", False),
        ("resumed", "resumed runs (not in the medians):", True),
    ):
        listed = sorted((r for r in runs if r["status"] == status), key=lambda r: (r["date"], r["session"]))
        if listed:
            tail.append(title)
            tail += [run_row(r, with_status) for r in listed]
    tail += left_lines(left)
    if tail:
        sections.append(tail)
    print("\n\n".join("\n".join(s) for s in sections))


# --- main --------------------------------------------------------------------


def main(argv=None):
    args = parse_args(sys.argv[1:] if argv is None else argv)
    projects = projects_dir()
    weights = DEFAULT_WEIGHTS
    if args.weights is not None:
        try:
            weights = load_weights(args.weights)
        except WeightsError as e:
            print(f"measure.py: error: weights file: {e}", file=sys.stderr)
            return 2
    # Only a recorded cwd climbs to an existing parent; a given path must exist.
    if args.project is not None and not os.path.isdir(args.project):
        print(f"measure.py: error: --project: no such directory: {safe(args.project)}", file=sys.stderr)
        return 2
    if args.session is not None:
        repo = None  # every project folder: --project and --all are ignored
        runs, left = collect(projects, lambda r: True, session=args.session)
    else:
        repo = None if args.all else resolve_repo(args.project if args.project is not None else os.getcwd())
        runs, left = collect(projects, (lambda r: True) if repo is None else (lambda r: r == repo))
    window = window_text(args.since, args.until)
    if args.since is not None or args.until is not None:
        lo = args.since.isoformat() if args.since else ""
        hi = args.until.isoformat() if args.until else "9999-12-31"

        def inside(item):  # inclusive, on the invocation's local date
            return re.fullmatch(r"\d{4}-\d{2}-\d{2}", item["date"] or "") is not None and lo <= item["date"] <= hi

        runs = [r for r in runs if inside(r)]
        left = [x for x in left if inside(x)]
    if not runs and not left:
        if args.session is not None:
            target = f"session {safe(args.session)}"
        else:
            target = "any repo" if repo is None else safe(repo)
        print(f"no runs found in {safe(projects)} for {target}{window}")
        return 0
    if args.session is not None:
        session_report(runs, left, projects, args.session, weights, window)
    else:
        report(runs, left, projects, repo, weights, args.compare_since, window)
    # --strict: any run of the selection left out fails the command (FR-017).
    return 1 if args.strict and left else 0


if __name__ == "__main__":
    sys.exit(main())
