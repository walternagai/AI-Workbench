#!/usr/bin/env python3
"""Minimal sentence-transformers throughput benchmark."""
import time
from sentence_transformers import SentenceTransformer


def main() -> None:
    model = SentenceTransformer("all-MiniLM-L6-v2")
    sentences = ["AI-Workbench benchmark sentence number %d" % i for i in range(64)]

    model.encode(sentences[:8])  # warmup

    start = time.perf_counter()
    model.encode(sentences)
    elapsed = time.perf_counter() - start

    print(f"sentences: {len(sentences)}")
    print(f"elapsed_s: {elapsed:.3f}")
    print(f"throughput_sentences_per_s: {len(sentences) / elapsed:.2f}")


if __name__ == "__main__":
    main()
