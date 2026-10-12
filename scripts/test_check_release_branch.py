import unittest

from scripts.check_release_branch import check_release_branch


class ReleaseBranchTests(unittest.TestCase):
    def test_default_branch_accepts_stable_and_candidate_versions(self):
        for version in ("0.26.0", "0.26.0-rc1"):
            check_release_branch(version, "branch", "main", "main")

    def test_feature_branch_accepts_numbered_candidates(self):
        for version in ("0.26.0-rc1", "0.26.0-rc12"):
            check_release_branch(version, "branch", "fix/msvc-runtime-inputs", "main")

    def test_feature_branch_rejects_other_publications(self):
        for version in ("0.26.0", "0.26.0-beta1", "0.26.0-rc0", "0.26.0-rc01",
                        "0.26.0-rc1+build", "0.26.0-rc1\n"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                check_release_branch(version, "branch", "feature", "main")

    def test_tag_dispatch_rejected_even_for_default_branch_name(self):
        for ref in ("main", "0.26.0-rc1"):
            with self.subTest(ref=ref), self.assertRaises(ValueError):
                check_release_branch("0.26.0-rc1", "tag", ref, "main")
