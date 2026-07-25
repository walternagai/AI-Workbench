#!/usr/bin/env python3
"""ONNX Runtime throughput benchmark with configurable iterations.

Usage:
    python bench_onnx.py <model.onnx> [--runs 20] [--seed 0] [--warmup 3]

Reports provider, min/mean/max latency and throughput across N runs.
"""
from __future__ import annotations

import argparse
import statistics
import sys
import time
from typing import Any, List, Optional, Sequence, Union

import numpy as np
import onnxruntime as ort


# ---------------------------------------------------------------------------
# Pure helpers (testable without model files / GPU)
# ---------------------------------------------------------------------------

def resolve_shape(shape: Sequence[Union[int, str, None]]) -> List[int]:
    """Convert a model-input shape to a concrete shape for dummy data.

    Dynamic dimensions (``None``, ``'N'``, ``-1``, etc.) are replaced
    with ``1`` so a minimal tensor can be constructed.
    """
    resolved: List[int] = []
    for d in shape:
        if isinstance(d, int) and d > 0:
            resolved.append(d)
        else:
            resolved.append(1)
    return resolved


def compute_latency_stats(times: List[float]) -> dict:
    """Return ms-based stats and FPS from a list of elapsed seconds.

    ``stdev`` is 0.0 when fewer than 2 samples are provided (avoids
    ``StatisticsError``).
    """
    n = len(times)
    if n == 0:
        return {"min_ms": 0.0, "mean_ms": 0.0, "max_ms": 0.0,
                "stdev_ms": 0.0, "fps": 0.0}
    latencies_ms = [t * 1000.0 for t in times]
    mean_ms = statistics.mean(latencies_ms)
    stdev_ms = statistics.stdev(latencies_ms) if n > 1 else 0.0
    return {
        "min_ms": min(latencies_ms),
        "mean_ms": mean_ms,
        "max_ms": max(latencies_ms),
        "stdev_ms": stdev_ms,
        "fps": 1.0 / statistics.mean(times),
    }


def format_report(times: List[float],
                  stats: Optional[dict] = None) -> str:
    """Build the latency/throughput lines printed at the end of a run."""
    if stats is None:
        stats = compute_latency_stats(times)

    lines = [
        f"min_latency_ms:   {stats['min_ms']:.2f}",
        f"avg_latency_ms:   {stats['mean_ms']:.2f}",
        f"max_latency_ms:   {stats['max_ms']:.2f}",
        f"stdev_latency_ms: {stats['stdev_ms']:.2f}",
        f"throughput_fps:   {stats['fps']:.2f}",
    ]
    return "\n".join(lines)


def parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    """Parse CLI arguments; accepts an optional list for testing."""
    parser = argparse.ArgumentParser(description="ONNX Runtime benchmark")
    parser.add_argument("model", help="Path to .onnx model file")
    parser.add_argument("--runs", type=int, default=20,
                        help="Number of benchmark runs (default: 20)")
    parser.add_argument("--warmup", type=int, default=3,
                        help="Number of warmup runs (default: 3)")
    parser.add_argument("--seed", type=int, default=None,
                        help="Random seed for reproducibility")
    return parser.parse_args(argv)


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

def main(argv: Optional[List[str]] = None) -> int:
    args = parse_args(argv)

    model_path = args.model
    session = ort.InferenceSession(model_path,
                                   providers=ort.get_available_providers())
    input_meta = session.get_inputs()[0]
    shape = resolve_shape(input_meta.shape)
    rng: Any = np.random.RandomState(args.seed)
    dummy = rng.rand(*shape).astype(np.float32)

    print(f"model:   {model_path}")
    print(f"provider: {session.get_providers()[0]}")
    print(f"shape:   {shape}")
    print(f"runs:    {args.runs} (+ {args.warmup} warmup)")

    # Warmup
    for _ in range(args.warmup):
        session.run(None, {input_meta.name: dummy})

    times: List[float] = []
    for _ in range(args.runs):
        start = time.perf_counter()
        session.run(None, {input_meta.name: dummy})
        elapsed = time.perf_counter() - start
        times.append(elapsed)

    print(format_report(times))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
