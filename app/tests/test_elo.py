"""Unit tests for the ELO rating math."""

from elo import K, expected_score, updated_ratings


def test_even_match_is_fifty_fifty():
    assert expected_score(1000, 1000) == 0.5


def test_equal_ratings_swing_by_half_k():
    # Two 1000-rated players: winner +K/2, loser -K/2 (here ±16).
    new_winner, new_loser = updated_ratings(1000, 1000, a_won=True)
    assert new_winner == 1000 + K // 2
    assert new_loser == 1000 - K // 2


def test_zero_sum_total_rating_is_preserved():
    a, b = 1200, 1000
    new_a, new_b = updated_ratings(a, b, a_won=True)
    # Rounding can shift the sum by at most 1 point.
    assert abs((new_a + new_b) - (a + b)) <= 1


def test_underdog_win_gains_more_than_favorite_win():
    underdog_gain = updated_ratings(1000, 1400, a_won=True)[0] - 1000
    favorite_gain = updated_ratings(1400, 1000, a_won=True)[0] - 1400
    assert underdog_gain > favorite_gain


def test_favorite_beating_underdog_gains_little():
    new_a, _ = updated_ratings(1600, 1000, a_won=True)
    assert 0 < new_a - 1600 <= 4
