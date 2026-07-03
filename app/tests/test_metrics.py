"""EMF document shape. Pure construction, no AWS."""

from metrics import emf_document


def test_emf_envelope_and_root_members():
    doc = emf_document(
        {"MatchmakingLatencyMs": 12.4},
        {"MatchmakingLatencyMs": "Milliseconds"},
        {"outcome": "MATCHED"},
    )

    aws = doc["_aws"]
    assert isinstance(aws["Timestamp"], int)  # epoch millis

    cw = aws["CloudWatchMetrics"][0]
    assert cw["Namespace"]  # populated from settings
    assert {"Name": "MatchmakingLatencyMs", "Unit": "Milliseconds"} in cw["Metrics"]

    # Dimension KEYS live in the Dimensions set...
    dim_keys = cw["Dimensions"][0]
    assert {"service", "env", "outcome"} <= set(dim_keys)
    # ...and their VALUES are root members.
    assert doc["outcome"] == "MATCHED"
    assert doc["service"]
    assert doc["env"]
    # Metric VALUE is a root member.
    assert doc["MatchmakingLatencyMs"] == 12.4


def test_default_dimensions_are_service_and_env():
    doc = emf_document({"PlayersCreated": 1}, {"PlayersCreated": "Count"})
    assert doc["_aws"]["CloudWatchMetrics"][0]["Dimensions"][0] == ["service", "env"]


def test_fields_are_root_members_but_not_dimensions():
    doc = emf_document(
        {"RequestCount": 1},
        {"RequestCount": "Count"},
        fields={"route": "/players/{player_id}", "status_class": "4xx"},
    )
    dim_keys = doc["_aws"]["CloudWatchMetrics"][0]["Dimensions"][0]
    # route/status_class enrich the log line...
    assert doc["route"] == "/players/{player_id}"
    assert doc["status_class"] == "4xx"
    # ...but are NOT dimensions (would otherwise blow up cardinality).
    assert "route" not in dim_keys
    assert "status_class" not in dim_keys
    assert dim_keys == ["service", "env"]
