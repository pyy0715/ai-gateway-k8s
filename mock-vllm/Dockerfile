FROM python:3.11-slim

WORKDIR /app

# Install curl for health checks and debugging
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Copy dependency files first for better caching
COPY pyproject.toml ./

# Install dependencies only (not the project itself)
RUN uv pip install --system fastapi uvicorn[standard] pydantic pydantic-settings

# Copy application code
COPY app/ ./app/

EXPOSE 8000

# Run the server
CMD ["python", "-m", "app.main"]
