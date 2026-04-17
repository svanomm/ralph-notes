#!/usr/bin/env python3
"""Shared Pydantic models for Ralph Note frontmatter validation."""

from __future__ import annotations

import re
from typing import Annotated, Literal, Union

import yaml
from pydantic import BaseModel, Field, TypeAdapter, field_validator


# ── Frontmatter models ──────────────────────────────────────────────


class NoteFrontmatter(BaseModel):
    type: Literal["note"]
    id: Literal["PLACEHOLDER"]
    title: str = Field(min_length=1, max_length=80)
    answers: str
    source: str = Field(min_length=1)
    tags: list[str] = Field(min_length=1)
    created: Literal["PLACEHOLDER"]

    @field_validator("title")
    @classmethod
    def title_max_words(cls, v: str) -> str:
        if len(v.split()) > 10:
            raise ValueError("title must be 10 words or fewer")
        return v

    @field_validator("source")
    @classmethod
    def source_in_docs(cls, v: str) -> str:
        if not v.startswith("docs/"):
            raise ValueError("source must reference a file in docs/")
        return v

    @field_validator("answers")
    @classmethod
    def answers_format(cls, v: str) -> str:
        if not re.match(r"^Q-\d{8}-\d{6}-\d{3}$", v):
            raise ValueError(
                f"answers must be a valid question ID (Q-YYYYMMDD-HHMMSS-mmm), got '{v}'"
            )
        return v


class QuestionFrontmatter(BaseModel):
    type: Literal["question"]
    id: Literal["PLACEHOLDER"]
    question: str = Field(min_length=1)
    parent: str | None = None
    source: Literal["asker"]
    status: Literal["open"]
    created: Literal["PLACEHOLDER"]

    @field_validator("parent")
    @classmethod
    def parent_format(cls, v: str | None) -> str | None:
        if v is not None and not re.match(r"^Q-\d{8}-\d{6}-\d{3}$", v):
            raise ValueError(
                f"parent must be a valid question ID (Q-YYYYMMDD-HHMMSS-mmm), got '{v}'"
            )
        return v


Frontmatter = Annotated[
    Union[NoteFrontmatter, QuestionFrontmatter],
    Field(discriminator="type"),
]
_validate = TypeAdapter(Frontmatter).validate_python


# ── Helpers ──────────────────────────────────────────────────────────


def parse_frontmatter(text: str) -> dict:
    """Extract and parse YAML frontmatter from a Markdown file."""
    match = re.match(r"^---\n(.+?)\n---", text, re.DOTALL)
    if not match:
        raise ValueError("No valid YAML frontmatter (expected --- delimiters)")
    raw = yaml.safe_load(match.group(1))
    if not isinstance(raw, dict):
        raise ValueError("Frontmatter must be a YAML mapping")
    return raw
