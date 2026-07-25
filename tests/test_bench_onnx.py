"""Tests for benchmarks/vision/bench_onnx.py"""
from __future__ import annotations

from unittest import mock

import pytest

from benchmarks.vision.bench_onnx import (
    compute_latency_stats,
    format_report,
    parse_args,
    resolve_shape,
)

# ---------------------------------------------------------------------------
# parse_args
# ---------------------------------------------------------------------------


class TestParseArgs:
    def test_defaults(self) -> None:
        args = parse_args(["model.onnx"])
        assert args.model == "model.onnx"
        assert args.runs == 20
        assert args.warmup == 3
        assert args.seed is None

    def test_custom(self) -> None:
        args = parse_args(["m.onnx", "--runs", "10",
                           "--warmup", "1", "--seed", "42"])
        assert args.model == "m.onnx"
        assert args.runs == 10
        assert args.warmup == 1
        assert args.seed == 42

    def test_model_required(self) -> None:
        with pytest.raises(SystemExit):
            parse_args([])


# ---------------------------------------------------------------------------
# resolve_shape
# ---------------------------------------------------------------------------


class TestResolveShape:
    def test_all_static(self) -> None:
        assert resolve_shape([1, 3, 224, 224]) == [1, 3, 224, 224]

    def test_mixed(self) -> None:
        """Dynamic batch dimension (None) is replaced with 1."""
        assert resolve_shape([None, 3, 64, 64]) == [1, 3, 64, 64]

    def test_string_dim(self) -> None:
        """'N' is treated as dynamic → 1."""
        assert resolve_shape(["N", 128]) == [1, 128]

    def test_negative_dim(self) -> None:
        """-1 is treated as dynamic → 1."""
        assert resolve_shape([-1, 256]) == [1, 256]

    def test_empty(self) -> None:
        assert resolve_shape([]) == []

    def test_zero(self) -> None:
        """Zero is treated as dynamic (not > 0) → replaced by 1."""
        assert resolve_shape([0]) == [1]


# ---------------------------------------------------------------------------
# compute_latency_stats
# ---------------------------------------------------------------------------


class TestComputeLatencyStats:
    def test_normal(self) -> None:
        times = [0.1, 0.2, 0.3]
        stats = compute_latency_stats(times)
        assert stats["min_ms"] == 100.0
        assert stats["mean_ms"] == pytest.approx(200.0)
        assert stats["max_ms"] == 300.0
        assert stats["fps"] == pytest.approx(5.0)       # 1 / 0.2

    def test_single_run(self) -> None:
        stats = compute_latency_stats([0.5])
        assert stats["min_ms"] == 500.0
        assert stats["mean_ms"] == 500.0
        assert stats["max_ms"] == 500.0
        assert stats["stdev_ms"] == 0.0
        assert stats["fps"] == 2.0

    def test_empty(self) -> None:
        stats = compute_latency_stats([])
        assert all(v == 0.0 for v in stats.values())

    def test_precision(self) -> None:
        """Very small latencies (<1 ms) should still produce correct ms."""
        times = [0.001, 0.002, 0.003]
        stats = compute_latency_stats(times)
        assert stats["min_ms"] == 1.0
        assert stats["mean_ms"] == 2.0
        assert stats["max_ms"] == 3.0


# ---------------------------------------------------------------------------
# format_report
# ---------------------------------------------------------------------------


class TestFormatReport:
    def test_full_output(self) -> None:
        times = [0.1, 0.2]
        report = format_report(times)
        lines = report.split("\n")
        assert "min_latency_ms:   100.00" in lines
        assert "avg_latency_ms:   150.00" in lines
        assert "max_latency_ms:   200.00" in lines
        assert any("stdev_latency_ms:" in l for l in lines)
        assert "throughput_fps:   6.67" in lines

    def test_with_precomputed_stats(self) -> None:
        stats = {"min_ms": 5.0, "mean_ms": 10.0, "max_ms": 15.0,
                 "stdev_ms": 2.0, "fps": 100.0}
        report = format_report([], stats=stats)
        assert "avg_latency_ms:   10.00" in report
        assert "throughput_fps:   100.00" in report


# ---------------------------------------------------------------------------
# main (smoke test with mocked InferenceSession)
# ---------------------------------------------------------------------------


class TestMain:
    def test_main_success(self) -> None:
        """Run main() with mocked onnxruntime session and capture output."""
        fake_input = mock.Mock()
        fake_input.name = "input"
        fake_input.shape = [1, 3, 224, 224]

        fake_session = mock.Mock()
        fake_session.get_inputs.return_value = [fake_input]
        fake_session.get_providers.return_value = ["CPUExecutionProvider"]
        fake_session.run.return_value = [None]

        with (
            mock.patch(
                "benchmarks.vision.bench_onnx.ort.InferenceSession",
                return_value=fake_session,
            ),
            mock.patch("sys.stdout", new_callable=mock.MagicMock) as stdout,
        ):
            from benchmarks.vision.bench_onnx import main
            result = main(["model.onnx", "--runs", "2", "--warmup", "1",
                           "--seed", "0"])

        assert result == 0
        output = "".join(c[0][0] for c in stdout.write.call_args_list)
        assert "model:   model.onnx" in output
        assert "provider: CPUExecutionProvider" in output
        assert "shape:   [1, 3, 224, 224]" in output
        assert "runs:    2 (+ 1 warmup)" in output
        assert "avg_latency_ms:" in output
        # Warmup (1) + runs (2) = 3 calls to session.run
        assert fake_session.run.call_count == 3
