"""JSON formatter behaviour. Pure formatting, no AWS."""

import json
import logging

from logging_config import JsonFormatter


def _record(name: str = "skybound.api", msg: str = "request", **extra):
    rec = logging.LogRecord(name, logging.INFO, __file__, 1, msg, None, None)
    for key, value in extra.items():
        setattr(rec, key, value)
    return rec


def test_formats_json_with_structured_extras():
    out = JsonFormatter().format(
        _record(request_id="abc", status=200, duration_ms=1.5, path="/players")
    )
    payload = json.loads(out)
    assert payload["level"] == "INFO"
    assert payload["msg"] == "request"
    assert payload["request_id"] == "abc"
    assert payload["status"] == 200
    assert payload["duration_ms"] == 1.5
    assert payload["path"] == "/players"


def test_metric_lines_pass_through_untouched():
    raw = '{"_aws": {"Timestamp": 1}, "RequestCount": 1}'
    out = JsonFormatter().format(_record(name="skybound.metrics", msg=raw))
    assert out == raw  # already EMF JSON — must not be re-wrapped
