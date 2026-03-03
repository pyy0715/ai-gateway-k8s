"""Prometheus metrics for mock vLLM server."""

import asyncio
from fastapi import Response
from app.config import config

# Internal state
_running_requests = 0
_waiting_requests = 0


def get_kv_cache_usage() -> float:
    """Calculate KV-cache usage based on running requests."""
    base = config.kv_cache_base
    per_request = config.kv_cache_per_request
    usage = base + (_running_requests * per_request)
    return min(1.0, usage)


async def acquire_request_slot() -> bool:
    """Try to acquire a request slot. Returns True if running, False if queued."""
    global _running_requests, _waiting_requests

    if _running_requests < config.max_concurrent:
        _running_requests += 1
        return True
    else:
        _waiting_requests += 1
        # Wait until a slot is available
        while _running_requests >= config.max_concurrent:
            await asyncio.sleep(0.01)
        _waiting_requests -= 1
        _running_requests += 1
        return False


def release_request_slot():
    """Release a request slot."""
    global _running_requests
    _running_requests = max(0, _running_requests - 1)


def get_metrics_text() -> str:
    """Generate Prometheus metrics in vLLM-compatible format with colons.

    EPP expects metric names like: vllm:num_requests_running
    prometheus_client converts colons to underscores, We generate text directly.
    """
    lines = []

    # vLLM-compatible metrics with colons
    labels = f'model_name="{config.model_name}"'

    lines.append(f"vllm:num_requests_running{{{labels}}} {_running_requests}")
    lines.append(f"vllm:num_requests_waiting{{{labels}}} {_waiting_requests}")
    lines.append(f"vllm:kv_cache_usage_perc{{{labels}}} {get_kv_cache_usage():.6f}")
    lines.append(f"vllm:gpu_cache_usage_perc{{{labels}}} {get_kv_cache_usage():.6f}")

    # Additional metrics for observability (underscores OK for these)
    lines.append(f"mock_vllm:pod_name{{pod_name=\"{config.pod_name}\"}} 1")
    lines.append(f"mock_vllm:ttft_ms{{pod_name=\"{config.pod_name}\"}} {config.ttft_base_ms}")
    lines.append(f"mock_vllm:max_concurrent{{pod_name=\"{config.pod_name}\"}} {config.max_concurrent}")

    return "\n".join(lines) + "\n"


def metrics_response() -> Response:
    """FastAPI response for /metrics endpoint."""
    return Response(
        content=get_metrics_text(),
        media_type="text/plain; version=0.0.4; charset=utf-8",
    )
