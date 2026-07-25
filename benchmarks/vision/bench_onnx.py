#!/usr/bin/env python3
"""ONNX Runtime throughput benchmark with configurable iterations.

Usage:
    python bench_onnx.py <model.onnx> [--runs 20] [--seed 0] [--warmup 3]

Reports provider, min/mean/max latency and throughput across N runs.
"""
import argparse
import statistics
import sys
import time

import numpy as np
import onnxruntime as ort


def main() -> int:
    parser = argparse.ArgumentParser(description="ONNX Runtime benchmark")
    parser.add_argument("model", help="Path to .onnx model file")
    parser.add_argument("--runs", type=int, default=20,
                        help="Number of benchmark runs (default: 20)")
    parser.add_argument("--warmup", type=int, default=3,
                        help="Number of warmup runs (default: 3)")
    parser.add_argument("--seed", type=int, default=None,
                        help="Random seed for reproducibility")
    args = parser.parse_args()

    model_path = args.model
    session = ort.InferenceSession(model_path,
                                   providers=ort.get_available_providers())
    input_meta = session.get_inputs()[0]
    shape = [d if isinstance(d, int) else 1 for d in input_meta.shape]
    rng = np.random.RandomState(args.seed)
    dummy = rng.rand(*shape).astype(np.float32)

    print(f"model:   {model_path}")
    print(f"provider: {session.get_providers()[0]}")
    print(f"shape:   {shape}")
    print(f"runs:    {args.runs} (+ {args.warmup} warmup)")

    # Warmup
    for _ in range(args.warmup):
        session.run(None, {input_meta.name: dummy})

    times: list[float] = []
    for i in range(args.runs):
        start = time.perf_counter()
        session.run(None, {input_meta.name: dummy})
        elapsed = time.perf_counter() - start
        times.append(elapsed)

    latencies_ms = [t * 1000 for t in times]
    avg = statistics.mean(latencies_ms)
    stdev = statistics.stdev(latencies_ms) if len(latencies_ms) > 1 else 0.0
    fps = 1.0 / statistics.mean(times)

    print(f"min_latency_ms:  {min(latencies_ms):.2f}")
    print(f"avg_latency_ms:  {avg:.2f}")
    print(f"max_latency_ms:  {max(latencies_ms):.2f}")
    print(f"stdev_latency_ms: {stdev:.2f}")
    print(f"throughput_fps:  {fps:.2f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
