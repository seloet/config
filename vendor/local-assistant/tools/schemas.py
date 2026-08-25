from __future__ import annotations
from pydantic import BaseModel, Field


class OpenApplicationArgs(BaseModel):
    application: str = Field(min_length=1)


class SetVolumeArgs(BaseModel):
    percent: int = Field(ge=0, le=100)


class GetTimeArgs(BaseModel):
    pass


class CreateNoteArgs(BaseModel):
    text: str = Field(min_length=1, max_length=2000)
    title: str | None = None


class SearchFilesArgs(BaseModel):
    query: str = Field(min_length=1)
    max_results: int = Field(default=20, ge=1, le=200)


class PlayPauseMediaArgs(BaseModel):
    action: str | None = Field(
        default=None,
        description="play | pause | toggle | next | previous | stop. "
                    "None (default) toggles play/pause.",
    )

    def model_post_init(self, __context) -> None:
        if self.action is not None and self.action not in {
            "play", "pause", "toggle", "next", "previous", "stop",
        }:
            raise ValueError(
                "action must be one of play/pause/toggle/next/previous/stop"
            )


class LockScreenArgs(BaseModel):
    pass
