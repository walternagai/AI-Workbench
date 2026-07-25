#!/usr/bin/env python3
"""Sentence-transformers throughput benchmark with configurable iterations.

Usage:
    python bench_embeddings.py [--model all-MiniLM-L6-v2] [--batch-size 64]
                               [--iterations 10]

Reports min/mean/max latency and throughput across N iterations.
"""
import argparse
import statistics
import time

from sentence_transformers import SentenceTransformer


def main() -> None:
    parser = argparse.ArgumentParser(description="Sentence-transformers benchmark")
    parser.add_argument("--model", default="all-MiniLM-L6-v2",
                        help="HuggingFace model name (default: all-MiniLM-L6-v2)")
    parser.add_argument("--batch-size", type=int, default=64,
                        help="Number of sentences per batch (default: 64)")
    parser.add_argument("--iterations", type=int, default=10,
                        help="Number of benchmark runs (default: 10)")
    args = parser.parse_args()

    print(f"model: {args.model}")
    print(f"batch_size: {args.batch_size}")
    print(f"iterations: {args.iterations}")

    model = SentenceTransformer(args.model)
    sentences = [f"AI-Workbench benchmark sentence number {i}"
                 for i in range(args.batch_size)]

    # Warmup: one small batch to prime caches/JIT
    model.encode(sentences[:8], show_progress_bar=False)

    times: list[float] = []
    for i in range(args.iterations):
        start = time.perf_counter()
        model.encode(sentences, show_progress_bar=False)
        elapsed = time.perf_counter() - start
        times.append(elapsed)
        print(f"  run {i + 1:2d}: {elapsed:.3f}s  "
              f"({args.batch_size / elapsed:.2f} sentences/s)")

    avg = statistics.mean(times)
    stdev = statistics.stdev(times) if len(times) > 1 else 0.0
    print(f"\nsentences:       {args.batch_size}")
    print(f"runs:            {args.iterations}")
    print(f"avg_latency_s:   {avg:.3f}")
    print(f"min_latency_s:   {min(times):.3f}")
    print(f"max_latency_s:   {max(times):.3f}")
    print(f"stdev_latency_s: {stdev:.3f}")
    print(f"avg_throughput:  {args.batch_size / avg:.2f} sentences/s")


if __name__ == "__main__":
    main()
