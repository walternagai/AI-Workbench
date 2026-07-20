#!/usr/bin/env python3
"""Minimal ONNX Runtime throughput benchmark used by benchmarks/vision/run.sh."""
import sys
import time
import numpy as np
import onnxruntime as ort


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: bench_onnx.py <model.onnx>", file=sys.stderr)
        return 1

    model_path = sys.argv[1]
    session = ort.InferenceSession(model_path, providers=ort.get_available_providers())
    input_meta = session.get_inputs()[0]
    shape = [d if isinstance(d, int) else 1 for d in input_meta.shape]
    dummy = np.random.rand(*shape).astype(np.float32)

    # Warmup
    for _ in range(3):
        session.run(None, {input_meta.name: dummy})

    n_runs = 20
    start = time.perf_counter()
    for _ in range(n_runs):
        session.run(None, {input_meta.name: dummy})
    elapsed = time.perf_counter() - start

    print(f"provider: {session.get_providers()[0]}")
    print(f"avg_latency_ms: {(elapsed / n_runs) * 1000:.2f}")
    print(f"throughput_fps: {n_runs / elapsed:.2f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
