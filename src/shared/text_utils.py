"""Shared text helpers for the AI document analyser."""
from __future__ import annotations

from typing import Iterable


def compact_whitespace(text: str) -> str:
    """Collapse repeated whitespace while preserving readable text."""
    return " ".join((text or "").split())


def truncate(text: str, max_chars: int = 4000) -> str:
    """Return a safe preview string with a maximum character length."""
    if max_chars <= 0:
        return ""
    cleaned = compact_whitespace(text)
    if len(cleaned) <= max_chars:
        return cleaned
    return cleaned[: max_chars - 3] + "..."


def redact_entities(text: str, entities: Iterable[dict]) -> str:
    """Redact text spans returned by Amazon Comprehend.

    Comprehend returns offsets against the original string. Replacing from the end
    avoids shifting offsets for earlier entities.
    """
    redacted = text or ""
    sorted_entities = sorted(
        entities or [],
        key=lambda item: int(item.get("BeginOffset", 0)),
        reverse=True,
    )

    for entity in sorted_entities:
        begin = int(entity.get("BeginOffset", 0))
        end = int(entity.get("EndOffset", begin))
        entity_type = entity.get("Type", "PII")
        if 0 <= begin <= end <= len(redacted):
            redacted = redacted[:begin] + f"[{entity_type}_REDACTED]" + redacted[end:]

    return redacted
