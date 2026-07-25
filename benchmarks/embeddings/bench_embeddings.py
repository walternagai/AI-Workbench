#!/usr/bin/env python3
"""Sentence-transformers throughput benchmark with configurable iterations.

Usage:
    python bench_embeddings.py [--model all-MiniLM-L6-v2] [--batch-size 64]
                               [--iterations 10]

Reports min/mean/max latency and throughput across N iterations.
"""
from __future__ import annotations

import argparse
import statistics
import time
from typing import List, Optional

from sentence_transformers import SentenceTransformer


# ---------------------------------------------------------------------------
# Pure helpers (testable without GPU / model weights)
# ---------------------------------------------------------------------------

def compute_stats(times: List[float]) -> dict:
    """Return min / mean / max / stdev from a list of elapsed times (seconds).

    stdev is 0.0 when fewer than 2 samples are provided (avoids
    StatisticsError).
    """
    n = len(times)
    if n == 0:
        return {"min": 0.0, "mean": 0.0, "max": 0.0, "stdev": 0.0}
    mean = statistics.mean(times)
    stdev = statistics.stdev(times) if n > 1 else 0.0
    return {
        "min": min(times),
        "mean": mean,
        "max": max(times),
        "stdev": stdev,
    }


def format_report(args: argparse.Namespace, times: List[float],
                  stats: Optional[dict] = None) -> str:
    """Build the multi-line output string printed at the end of a run."""
    if stats is None:
        stats = compute_stats(times)

    lines = [
        f"sentences:       {args.batch_size}",
        f"runs:            {args.iterations}",
        f"avg_latency_s:   {stats['mean']:.3f}",
        f"min_latency_s:   {stats['min']:.3f}",
        f"max_latency_s:   {stats['max']:.3f}",
        f"stdev_latency_s: {stats['stdev']:.3f}",
        f"avg_throughput:  {args.batch_size / stats['mean']:.2f} sentences/s",
    ]
    return "\n".join(lines)


def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    """Parse CLI arguments; accepts an optional list for testing."""
    parser = argparse.ArgumentParser(description="Sentence-transformers benchmark")
    parser.add_argument("--model", default="all-MiniLM-L6-v2",
                        help="HuggingFace model name (default: all-MiniLM-L6-v2)")
    parser.add_argument("--batch-size", type=int, default=64,
                        help="Number of sentences per batch (default: 64)")
    parser.add_argument("--iterations", type=int, default=10,
                        help="Number of benchmark runs (default: 10)")
    return parser.parse_args(argv)


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

def main(argv: Optional[List[str]] = None) -> None:
    args = parse_args(argv)

    print(f"model: {args.model}")
    print(f"batch_size: {args.batch_size}")
    print(f"iterations: {args.iterations}")

    model = SentenceTransformer(args.model)
    sentences = [f"AI-Workbench benchmark sentence number {i}"
                 for i in range(args.batch_size)]

    # Warmup: one small batch to prime caches/JIT
    model.encode(sentences[:8], show_progress_bar=False)

    times: List[float] = []
    for i in range(args.iterations):
        start = time.perf_counter()
        model.encode(sentences, show_progress_bar=False)
        elapsed = time.perf_counter() - start
        times.append(elapsed)
        print(f"  run {i + 1:2d}: {elapsed:.3f}s  "
              f"({args.batch_size / elapsed:.2f} sentences/s)")

    print()
    print(format_report(args, times))


if __name__ == "__main__":
    main()
