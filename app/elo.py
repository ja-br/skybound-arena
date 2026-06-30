"""ELO rating math. Pure functions, no I/O."""

K = 32


def expected_score(rating_a: int, rating_b: int) -> float:
    """Probability that A beats B, per the standard ELO logistic curve."""
    return 1 / (1 + 10 ** ((rating_b - rating_a) / 400))


def updated_ratings(rating_a: int, rating_b: int, a_won: bool) -> tuple[int, int]:
    """Return (new_rating_a, new_rating_b) after a decisive match.

    score = 1 for the winner, 0 for the loser. Ratings are rounded to ints to
    match the DynamoDB `rating` Number attribute (the leaderboard GSI sort key).
    """
    score_a = 1.0 if a_won else 0.0
    score_b = 1.0 - score_a
    new_a = rating_a + K * (score_a - expected_score(rating_a, rating_b))
    new_b = rating_b + K * (score_b - expected_score(rating_b, rating_a))
    return round(new_a), round(new_b)
