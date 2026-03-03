"""Chat completions endpoint."""

import asyncio
import time
import uuid
from fastapi import APIRouter
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from typing import Literal, Optional

from app.config import config
from app import metrics  # acquire_request_slot, release_request_slot 사용

router = APIRouter()


class ChatMessage(BaseModel):
    role: str
    content: str


class ChatCompletionRequest(BaseModel):
    model: str
    messages: list[ChatMessage]
    temperature: float = 1.0
    max_tokens: int = 100
    stream: bool = False


class ChatCompletionChoice(BaseModel):
    index: int = 0
    message: ChatMessage
    finish_reason: Literal["stop"] = "stop"


class Usage(BaseModel):
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int


class ChatCompletionResponse(BaseModel):
    id: str
    object: Literal["chat.completion"] = "chat.completion"
    created: int
    model: str
    choices: list[ChatCompletionChoice]
    usage: Usage


class DeltaMessage(BaseModel):
    role: Optional[str] = None
    content: Optional[str] = None


class StreamChoice(BaseModel):
    index: int = 0
    delta: DeltaMessage
    finish_reason: Optional[Literal["stop"]] = None


class ChatCompletionChunk(BaseModel):
    id: str
    object: Literal["chat.completion.chunk"] = "chat.completion.chunk"
    created: int
    model: str
    choices: list[StreamChoice]


def generate_mock_response(messages: list[ChatMessage]) -> str:
    """Generate a mock response based on input."""
    # Simple mock response
    last_message = messages[-1].content if messages else "Hello"
    return f"Mock response to: {last_message[:50]}..."


@router.post("/v1/chat/completions")
async def chat_completions(request: ChatCompletionRequest):
    """Handle chat completion requests."""
    start_time = time.time()
    request_id = f"chatcmpl-{uuid.uuid4().hex[:8]}"

    # Acquire slot (may wait if at capacity)
    was_queued = not await metrics.acquire_request_slot()

    try:
        # Simulate time-to-first-token
        await asyncio.sleep(config.ttft_base_ms / 1000.0)

        response_text = generate_mock_response(request.messages)

        if request.stream:
            return StreamingResponse(
                stream_response(request_id, request.model, response_text),
                media_type="text/event-stream",
            )
        else:
            # Simulate inter-token latency for full response
            await asyncio.sleep(config.itl_base_ms * 10 / 1000.0)

            return ChatCompletionResponse(
                id=request_id,
                created=int(time.time()),
                model=request.model,
                choices=[
                    ChatCompletionChoice(
                        message=ChatMessage(
                            role="assistant",
                            content=response_text,
                        )
                    )
                ],
                usage=Usage(
                    prompt_tokens=sum(len(m.content.split()) for m in request.messages),
                    completion_tokens=len(response_text.split()),
                    total_tokens=sum(len(m.content.split()) for m in request.messages)
                    + len(response_text.split()),
                ),
            )
    finally:
        metrics.release_request_slot()


async def stream_response(request_id: str, model: str, response_text: str):
    """Stream response in SSE format."""
    created = int(time.time())

    # First chunk with role
    chunk = ChatCompletionChunk(
        id=request_id,
        created=created,
        model=model,
        choices=[
            StreamChoice(delta=DeltaMessage(role="assistant", content=""))
        ],
    )
    yield f"data: {chunk.model_dump_json()}\n\n"

    # Stream content word by word
    words = response_text.split()
    for i, word in enumerate(words):
        chunk = ChatCompletionChunk(
            id=request_id,
            created=created,
            model=model,
            choices=[
                StreamChoice(delta=DeltaMessage(content=word + " "))
            ],
        )
        yield f"data: {chunk.model_dump_json()}\n\n"
        await asyncio.sleep(config.itl_base_ms / 1000.0)

    # Final chunk
    chunk = ChatCompletionChunk(
        id=request_id,
        created=created,
        model=model,
        choices=[StreamChoice(delta=DeltaMessage(), finish_reason="stop")],
    )
    yield f"data: {chunk.model_dump_json()}\n\n"
    yield "data: [DONE]\n\n"
