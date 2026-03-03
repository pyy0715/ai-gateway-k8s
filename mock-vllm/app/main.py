"""Main entry point for mock vLLM server."""

import logging

from fastapi import FastAPI
from fastapi.responses import Response
import uvicorn

from app.config import config
from app import metrics
from app.handlers import health, models, chat

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Create FastAPI app
app = FastAPI(title="Mock vLLM Server", version="0.1.0")

# Include routers
app.include_router(health.router)
app.include_router(models.router)
app.include_router(chat.router)


# Custom metrics endpoint with vLLM-compatible format (colons, not underscores)
@app.get("/metrics")
async def metrics_endpoint():
    return metrics.metrics_response()


@app.on_event("startup")
async def startup_event():
    """Log startup info."""
    logger.info(
        f"Mock vLLM server starting - Pod: {config.pod_name}, "
        f"Model: {config.model_name}, "
        f"TTFT: {config.ttft_base_ms}ms, "
        f"KV-cache base: {config.kv_cache_base}, "
        f"Max concurrent: {config.max_concurrent}"
    )


def main():
    """Run the server."""
    uvicorn.run(app, host="0.0.0.0", port=config.port)


if __name__ == "__main__":
    main()
