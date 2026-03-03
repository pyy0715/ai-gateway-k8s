"""Models endpoint."""

from fastapi import APIRouter
from pydantic import BaseModel
from typing import Literal

from app.config import config

router = APIRouter()


class ModelInfo(BaseModel):
    id: str
    object: Literal["model"] = "model"
    created: int = 0
    owned_by: str = "mock-vllm"


class ModelsResponse(BaseModel):
    object: Literal["list"] = "list"
    data: list[ModelInfo]


@router.get("/v1/models", response_model=ModelsResponse)
async def list_models():
    """List available models."""
    return ModelsResponse(
        data=[
            ModelInfo(
                id=config.model_name,
                created=0,
                owned_by="mock-vllm",
            )
        ]
    )
