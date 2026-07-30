#!/usr/bin/env python3
"""Run trigger evaluation for a skill description.

Tests whether a skill's description causes the agent to trigger (read the
skill) for a set of queries. Outputs results as JSON.
"""

import argparse
import json
import os
import select
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path

from scripts.utils import parse_skill_md


def _decide_from_line(line: str, skill_name: str) -> bool | None:
    """Inspect one stream-json line and decide the trigger outcome.

    Returns True/False once the first assistant tool call is known, or None
    to keep waiting. Kimi's stream-json emits one JSON object per line; the
    relevant shapes are:

      {"role": "assistant", "content": "..."}
      {"role": "assistant", "tool_calls": [{"type": "function", "id": "...",
        "function": {"name": "Read", "arguments": "{...}"}}]}

    Tool-result lines ("role": "tool") and meta lines are ignored. The first
    assistant line carrying tool_calls decides: a Skill or Read call
    targeting the skill means triggered; any other first tool call means
    not triggered.
    """
    line = line.strip()
    if not line:
        return None
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        return None
    if event.get("role") != "assistant":
        return None
    tool_calls = event.get("tool_calls") or []
    if not tool_calls:
        return None
    function = tool_calls[0].get("function", {})
    tool_name = function.get("name", "")
    arguments = function.get("arguments", "")
    if tool_name == "Skill" and skill_name in arguments:
        return True
    if tool_name == "Read" and skill_name in arguments and "SKILL.md" in arguments:
        return True
    return False


def run_single_query(
    query: str,
    skill_name: str,
    skill_description: str,
    timeout: int,
    model: str | None = None,
) -> bool:
    """Run a single query and return whether the skill was triggered.

    Creates a temporary skills directory containing only the skill under
    test (with the description being evaluated), then runs
    `kimi -p --skills-dir <tmpdir>` so the skill appears in the agent's
    available skills list. stdout is streamed line by line; the first
    assistant message with tool_calls decides the outcome, so we can kill
    the process early instead of waiting for the full run to finish.
    """
    with tempfile.TemporaryDirectory(prefix=f"{skill_name}-eval-") as tmpdir:
        skill_dir = Path(tmpdir) / skill_name
        skill_dir.mkdir()

        # Use YAML block scalar to avoid breaking on quotes in description
        indented_desc = "\n  ".join(skill_description.split("\n"))
        skill_md = (
            f"---\n"
            f"name: {skill_name}\n"
            f"description: |\n"
            f"  {indented_desc}\n"
            f"---\n\n"
            f"# {skill_name}\n\n"
            f"This skill handles: {skill_description}\n"
        )
        (skill_dir / "SKILL.md").write_text(skill_md)

        cmd = [
            "kimi",
            "-p", query,
            "--output-format", "stream-json",
            "--skills-dir", tmpdir,
        ]
        if model:
            cmd.extend(["-m", model])

        # stderr goes to a temp file (not DEVNULL) so a failed launch — bad
        # model alias, auth error, rate limit — leaves a diagnosable trace.
        # Otherwise those failures are indistinguishable from a genuine
        # "skill did not trigger" and silently pollute the trigger rate.
        err_file = tempfile.TemporaryFile()
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=err_file,
            cwd=tmpdir,
        )

        def warn_on_failure() -> None:
            if process.returncode not in (None, 0):
                err_file.seek(0)
                err = err_file.read().decode("utf-8", errors="replace").strip()
                print(
                    f"Warning: kimi -p exited {process.returncode} "
                    f"(counted as not-triggered): {err[:300]}",
                    file=sys.stderr,
                )

        def flush_buffer(buffer: str) -> bool | None:
            """Decision from any complete lines left in buffer, else final line."""
            while "\n" in buffer:
                line, buffer = buffer.split("\n", 1)
                decision = _decide_from_line(line, skill_name)
                if decision is not None:
                    return decision
            return _decide_from_line(buffer, skill_name)

        start_time = time.time()
        buffer = ""
        killed = False

        try:
            while time.time() - start_time < timeout:
                if process.poll() is not None:
                    remaining = process.stdout.read()
                    if remaining:
                        buffer += remaining.decode("utf-8", errors="replace")
                    decision = flush_buffer(buffer)
                    if decision is not None:
                        return decision
                    # Process ended without any tool call
                    return False

                ready, _, _ = select.select([process.stdout], [], [], 1.0)
                if not ready:
                    continue

                chunk = os.read(process.stdout.fileno(), 8192)
                if not chunk:
                    # EOF: flush before giving up — the deciding line may sit
                    # in the buffer without a trailing newline
                    decision = flush_buffer(buffer)
                    if decision is not None:
                        return decision
                    break
                buffer += chunk.decode("utf-8", errors="replace")

                while "\n" in buffer:
                    line, buffer = buffer.split("\n", 1)
                    decision = _decide_from_line(line, skill_name)
                    if decision is not None:
                        return decision
        finally:
            # Clean up process on any exit path (return, exception, timeout)
            if process.poll() is None:
                process.kill()
                process.wait()
                killed = True
            # Surface launch failures (bad model, auth, rate limit) on every
            # path where we didn't kill the process ourselves. Runs killed
            # after a decision or a timeout are expected outcomes, not errors.
            if not killed:
                warn_on_failure()
            err_file.close()

        return False


def run_eval(
    eval_set: list[dict],
    skill_name: str,
    description: str,
    num_workers: int,
    timeout: int,
    runs_per_query: int = 1,
    trigger_threshold: float = 0.5,
    model: str | None = None,
) -> dict:
    """Run the full eval set and return results."""
    results = []

    with ProcessPoolExecutor(max_workers=num_workers) as executor:
        future_to_info = {}
        for item in eval_set:
            for run_idx in range(runs_per_query):
                future = executor.submit(
                    run_single_query,
                    item["query"],
                    skill_name,
                    description,
                    timeout,
                    model,
                )
                future_to_info[future] = (item, run_idx)

        query_triggers: dict[str, list[bool]] = {}
        query_items: dict[str, dict] = {}
        for future in as_completed(future_to_info):
            item, _ = future_to_info[future]
            query = item["query"]
            query_items[query] = item
            if query not in query_triggers:
                query_triggers[query] = []
            try:
                query_triggers[query].append(future.result())
            except Exception as e:
                print(f"Warning: query failed: {e}", file=sys.stderr)
                query_triggers[query].append(False)

    for query, triggers in query_triggers.items():
        item = query_items[query]
        trigger_rate = sum(triggers) / len(triggers)
        should_trigger = item["should_trigger"]
        if should_trigger:
            did_pass = trigger_rate >= trigger_threshold
        else:
            did_pass = trigger_rate < trigger_threshold
        results.append({
            "query": query,
            "should_trigger": should_trigger,
            "trigger_rate": trigger_rate,
            "triggers": sum(triggers),
            "runs": len(triggers),
            "pass": did_pass,
        })

    passed = sum(1 for r in results if r["pass"])
    total = len(results)

    return {
        "skill_name": skill_name,
        "description": description,
        "results": results,
        "summary": {
            "total": total,
            "passed": passed,
            "failed": total - passed,
        },
    }


def main():
    parser = argparse.ArgumentParser(description="Run trigger evaluation for a skill description")
    parser.add_argument("--eval-set", required=True, help="Path to eval set JSON file")
    parser.add_argument("--skill-path", required=True, help="Path to skill directory")
    parser.add_argument("--description", default=None, help="Override description to test")
    parser.add_argument("--num-workers", type=int, default=10, help="Number of parallel workers (each runs a `kimi -p`; lower this if you hit model rate limits)")
    parser.add_argument("--timeout", type=int, default=60, help="Timeout per query in seconds")
    parser.add_argument("--runs-per-query", type=int, default=3, help="Number of runs per query")
    parser.add_argument("--trigger-threshold", type=float, default=0.5, help="Trigger rate threshold")
    parser.add_argument("--model", default=None, help="Model alias for kimi -p (default: user's configured model)")
    parser.add_argument("--verbose", action="store_true", help="Print progress to stderr")
    args = parser.parse_args()

    eval_set = json.loads(Path(args.eval_set).read_text())
    skill_path = Path(args.skill_path)

    if not (skill_path / "SKILL.md").exists():
        print(f"Error: No SKILL.md found at {skill_path}", file=sys.stderr)
        sys.exit(1)

    name, original_description, content = parse_skill_md(skill_path)
    description = args.description or original_description

    if args.verbose:
        print(f"Evaluating: {description}", file=sys.stderr)

    output = run_eval(
        eval_set=eval_set,
        skill_name=name,
        description=description,
        num_workers=args.num_workers,
        timeout=args.timeout,
        runs_per_query=args.runs_per_query,
        trigger_threshold=args.trigger_threshold,
        model=args.model,
    )

    if args.verbose:
        summary = output["summary"]
        print(f"Results: {summary['passed']}/{summary['total']} passed", file=sys.stderr)
        for r in output["results"]:
            status = "PASS" if r["pass"] else "FAIL"
            rate_str = f"{r['triggers']}/{r['runs']}"
            print(f"  [{status}] rate={rate_str} expected={r['should_trigger']}: {r['query'][:70]}", file=sys.stderr)

    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
