import math
import unittest

from step4_risk_counterfactual import (
    InputValidationError,
    bounded_attributable,
    mx_to_q5,
    q30_70_from_q5,
)


class Step4UnitTests(unittest.TestCase):
    def test_q30_70_matches_product_definition(self):
        q5 = [0.01] * 8
        self.assertAlmostEqual(q30_70_from_q5(q5), 1.0 - 0.99**8)

    def test_q30_70_requires_all_eight_age_groups(self):
        with self.assertRaises(InputValidationError):
            q30_70_from_q5([0.01] * 7)

    def test_zero_risk_leaves_no_burden(self):
        value, reason = bounded_attributable(0.0, 10.0)
        self.assertEqual(value, 0.0)
        self.assertEqual(reason, "none")

    def test_mx_to_q5_uses_stage3_life_table_conversion(self):
        mx = 4.4587723328266646e-5
        self.assertAlmostEqual(mx_to_q5(mx), 2.229137685977325e-4, places=16)

    def test_negative_attributable_burden_is_bounded_at_zero(self):
        value, reason = bounded_attributable(-1.0, 10.0)
        self.assertEqual(value, 0.0)
        self.assertEqual(reason, "lower_bound_zero")

    def test_attributable_burden_cannot_exceed_baseline(self):
        value, reason = bounded_attributable(11.0, 10.0)
        self.assertEqual(value, 10.0)
        self.assertEqual(reason, "upper_bound_baseline")

    def test_valid_q_range(self):
        q = q30_70_from_q5([0.001, 0.002, 0.003, 0.004, 0.005, 0.006, 0.007, 0.008])
        self.assertTrue(math.isfinite(q))
        self.assertGreater(q, 0)
        self.assertLess(q, 1)


if __name__ == "__main__":
    unittest.main()

