"""CloudWatch Embedded Metric Format (EMF) helper.

The app emits metrics by printing EMF JSON to stdout. In AWS the ECS `awslogs`
driver ships that stdout to CloudWatch Logs, which auto-extracts EMF documents
into CloudWatch metrics with no agent and no extra API call — the metric rides
the log pipeline the app already uses. Nothing here touches AWS or the network,
so it is safe at import time and offline (unit tests, local docker-compose).

See: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Embedded_Metric_Format_Specification.html
"""

import json
import logging
import time

from config import settings

# Dedicated logger; its records pass through the JSON formatter untouched (they
# are already JSON), so the EMF document is never double-encoded.
_log = logging.getLogger("skybound.metrics")


def emf_document(
    metrics: dict[str, float],
    units: dict[str, str],
    dimensions: dict[str, str] | None = None,
    fields: dict[str, str] | None = None,
) -> dict:
    """Build one EMF document.

    `metrics` maps metric name -> numeric value; `units` maps metric name ->
    CloudWatch unit. `service` and `env` are always dimensions; `dimensions`
    adds more (keep them low-cardinality — every unique combination is a
    separate custom metric). `fields` are extra root members that enrich the
    log line but are NOT dimensions — use them for high-cardinality context
    (route, status class) so the metric aggregates cleanly while the detail
    stays queryable in Logs Insights.
    """
    dims = {"service": settings.service_name, "env": settings.env_name}
    if dimensions:
        dims.update(dimensions)

    root: dict = dict(fields) if fields else {}
    root.update(dims)      # dimension values win over fields
    root.update(metrics)   # metric values win over both

    return {
        "_aws": {
            "Timestamp": int(time.time() * 1000),  # epoch milliseconds
            "CloudWatchMetrics": [
                {
                    "Namespace": settings.metrics_namespace,
                    # Only these keys become dimensions; other root members are
                    # logged but not dimensioned.
                    "Dimensions": [list(dims.keys())],
                    "Metrics": [{"Name": name, "Unit": units[name]} for name in metrics],
                }
            ],
        },
        **root,
    }


def emit(
    metrics: dict[str, float],
    units: dict[str, str],
    dimensions: dict[str, str] | None = None,
    fields: dict[str, str] | None = None,
) -> None:
    """Emit one EMF document to stdout (unless metrics are disabled)."""
    if not settings.metrics_enabled:
        return
    _log.info(json.dumps(emf_document(metrics, units, dimensions, fields)))
