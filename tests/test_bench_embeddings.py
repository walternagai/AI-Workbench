"""Tests for benchmarks/embeddings/bench_embeddings.py"""
from __future__ import annotations

from unittest import mock

import pytest

from benchmarks.embeddings.bench_embeddings import (
    compute_stats,
    format_report,
    parse_args,
)

# ---------------------------------------------------------------------------
# parse_args
# ---------------------------------------------------------------------------


class TestParseArgs:
    def test_defaults(self) -> None:
        args = parse_args([])
        assert args.model == "all-MiniLM-L6-v2"
        assert args.batch_size == 64
        assert args.iterations == 10

    def test_custom(self) -> None:
        args = parse_args(["--model", "my-model",
                           "--batch-size", "32",
                           "--iterations", "5"])
        assert args.model == "my-model"
        assert args.batch_size == 32
        assert args.iterations == 5

    def test_batch_size_must_be_int(self) -> None:
        with pytest.raises(SystemExit):
            parse_args(["--batch-size", "not-a-number"])


# ---------------------------------------------------------------------------
# compute_stats
# ---------------------------------------------------------------------------


class TestComputeStats:
    def test_normal(self) -> None:
        times = [1.0, 2.0, 3.0, 4.0, 5.0]
        stats = compute_stats(times)
        assert stats["min"] == 1.0
        assert stats["mean"] == 3.0
        assert stats["max"] == 5.0
        assert stats["stdev"] == pytest.approx(1.5811388)

    def test_single_iteration(self) -> None:
        """stdev must be 0.0 when only one sample."""
        stats = compute_stats([2.5])
        assert stats["min"] == 2.5
        assert stats["mean"] == 2.5
        assert stats["max"] == 2.5
        assert stats["stdev"] == 0.0

    def test_empty(self) -> None:
        """All fields 0.0 when no data."""
        stats = compute_stats([])
        assert stats == {"min": 0.0, "mean": 0.0, "max": 0.0, "stdev": 0.0}

    def test_two_values(self) -> None:
        """Exact boundary: n == 2 must compute stdev without error."""
        stats = compute_stats([10.0, 12.0])
        assert stats["min"] == 10.0
        assert stats["mean"] == 11.0
        assert stats["max"] == 12.0
        assert stats["stdev"] == pytest.approx(1.41421356)


# ---------------------------------------------------------------------------
# format_report
# ---------------------------------------------------------------------------


class TestFormatReport:
    def test_full_output(self) -> None:
        args = mock.Mock(batch_size=64, iterations=10)
        times = [1.0, 2.0, 3.0]
        report = format_report(args, times)
        lines = report.split("\n")
        assert "sentences:       64" in lines
        assert "runs:            10" in lines
        assert "avg_latency_s:   2.000" in lines
        assert "min_latency_s:   1.000" in lines
        assert "max_latency_s:   3.000" in lines
        assert any("stdev_latency_s:" in l for l in lines)
        assert any("avg_throughput:  32.00" in l for l in lines)

    def test_with_precomputed_stats(self) -> None:
        """Passing a stats dict skips recomputation."""
        args = mock.Mock(batch_size=10)
        stats = {"min": 0.5, "mean": 1.0, "max": 2.0, "stdev": 0.3}
        report = format_report(args, times=[], stats=stats)
        assert "avg_latency_s:   1.000" in report
        assert "avg_throughput:  10.00" in report


# ---------------------------------------------------------------------------
# main (smoke test with mocked model)
# ---------------------------------------------------------------------------


class TestMain:
    def test_main_success(self) -> None:
        """Run main() with mocked SentenceTransformer and capture output."""
        fake_model = mock.Mock()
        fake_model.encode.return_value = [0.1] * 64

        with (
            mock.patch(
                "benchmarks.embeddings.bench_embeddings.SentenceTransformer",
                return_value=fake_model,
            ),
            mock.patch("sys.stdout", new_callable=mock.MagicMock) as stdout,
        ):
            from benchmarks.embeddings.bench_embeddings import main
            main(["--model", "fake", "--batch-size", "4", "--iterations", "2"])

        output = "".join(c[0][0] for c in stdout.write.call_args_list)
        assert "model: fake" in output
        assert "batch_size: 4" in output
        assert "runs:            2" in output
        assert "avg_latency_s:" in output
        # The model was called 3 times: warmup (8 sentences → batch of 8)
        # and 2 encode calls (batch of 4 each)
        assert fake_model.encode.call_count == 3
