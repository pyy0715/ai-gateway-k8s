"""Configuration for mock vLLM server."""

import os
from dataclasses import dataclass


@dataclass
class Config:
    """Server configuration from environment variables."""

    # Time-to-first-token in milliseconds
    ttft_base_ms: float = 100.0

    # Inter-token latency in milliseconds
    itl_base_ms: float = 50.0

    # Base KV-cache utilization (0.0 - 1.0)
    kv_cache_base: float = 0.1

    # KV-cache increase per active request
    kv_cache_per_request: float = 0.05

    # Maximum concurrent requests before queueing
    max_concurrent: int = 5

    # Model name to expose
    model_name: str = "mock-model"

    # Server port
    port: int = 8000

    # Pod identifier for debugging
    pod_name: str = "unknown"

    @classmethod
    def from_env(cls) -> "Config":
        """Load configuration from environment variables."""
        return cls(
            ttft_base_ms=float(os.getenv("MOCK_VLLM_TTFT_BASE_MS", "100")),
            itl_base_ms=float(os.getenv("MOCK_VLLM_ITL_BASE_MS", "50")),
            kv_cache_base=float(os.getenv("MOCK_VLLM_KV_CACHE_BASE", "0.1")),
            kv_cache_per_request=float(
                os.getenv("MOCK_VLLM_KV_CACHE_PER_REQUEST", "0.05")
            ),
            max_concurrent=int(os.getenv("MOCK_VLLM_MAX_CONCURRENT", "5")),
            model_name=os.getenv("MOCK_VLLM_MODEL_NAME", "mock-model"),
            port=int(os.getenv("PORT", "8000")),
            pod_name=os.getenv("POD_NAME", os.getenv("HOSTNAME", "unknown")),
        )


config = Config.from_env()
