"""Structured JSON logging.

Installs a JSON formatter on the root logger so the app's stdout is one JSON
object per line — which the ECS `awslogs` driver ships to CloudWatch Logs,
where the lines are queryable in Logs Insights. EMF metric lines (logger
`skybound.metrics`) are already JSON and are passed through untouched so the
metric document is never double-encoded.

Pure stdlib `logging`; no AWS, safe to call at import.
"""

import json
import logging

# Structured fields handlers may attach via `logger.info(msg, extra={...})`.
_EXTRA_FIELDS = (
    "request_id",
    "player_id",
    "match_id",
    "duration_ms",
    "method",
    "path",
    "status",
    "outcome",
)


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        # Metric lines are already EMF JSON — emit verbatim.
        if record.name == "skybound.metrics":
            return record.getMessage()

        payload = {
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
        }
        for field in _EXTRA_FIELDS:
            value = getattr(record, field, None)
            if value is not None:
                payload[field] = value
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)
        return json.dumps(payload)


def configure_logging() -> None:
    """Point the root logger at a single JSON-formatted stdout handler."""
    handler = logging.StreamHandler()
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(logging.INFO)
