import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi import HTTPException

from backend import polls_api as polls
from backend import school_api as core


def actor(user_id, role, class_id=None):
    return {"id": user_id, "role": role, "class_id": class_id}


class PollTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.patches = [
            patch.object(core, "DB_PATH", Path(self.tmp.name) / "polls.sqlite3"),
            patch.object(core, "TOKEN_SECRET", "test-secret-that-is-long-enough-for-hmac-signing"),
        ]
        for p in self.patches:
            p.start()
        core.init_db()
        polls._init()
        with core._db() as db:
            for uid, role, cls in [("t1", "teacher", "8А"), ("a1", "admin", None), ("s1", "student", "8А"),
                                   ("s2", "student", "8Б"), ("s3", "student", "8А")]:
                db.execute(
                    "INSERT INTO users(id,username,password_hash,role,display_name,class_id,created_at) VALUES(?,?,?,?,?,?,?)",
                    (uid, uid, core._hash_password("a sufficiently long test password"), role, uid, cls, core._utc_now()),
                )

    def tearDown(self):
        for p in self.patches:
            p.stop()
        self.tmp.cleanup()

    def make(self, **kw):
        body = dict(title="Куда поедем?", options=["Музей", "Театр"], scope="school")
        body.update(kw)
        return polls.create_poll_for(actor("t1", "teacher", "8А"), polls.PollCreate(**body))

    def test_class_poll_is_visible_only_to_that_class(self):
        self.make(scope="class", class_id="8А")
        self.assertEqual(len(polls.list_polls_for(actor("s1", "student", "8А"))["data"]), 1)
        self.assertEqual(polls.list_polls_for(actor("s2", "student", "8Б"))["data"], [])
        with self.assertRaises(HTTPException):
            polls.vote_for(actor("s2", "student", "8Б"), self.make(scope="class", class_id="8А")["id"],
                           polls.VoteBody(option_ids=["x"]))

    def test_vote_hides_results_until_voted_and_can_be_changed(self):
        poll = self.make()
        student = actor("s1", "student", "8А")
        before = polls.list_polls_for(student)["data"][0]
        self.assertIsNone(before["options"][0]["votes"])
        first, second = [o["id"] for o in poll["options"]]
        after = polls.vote_for(student, poll["id"], polls.VoteBody(option_ids=[first]))
        self.assertEqual([o["votes"] for o in after["options"]], [1, 0])
        changed = polls.vote_for(student, poll["id"], polls.VoteBody(option_ids=[second]))
        self.assertEqual([o["votes"] for o in changed["options"]], [0, 1])
        self.assertEqual(changed["total_voters"], 1)

    def test_single_choice_rejects_multiple_options_and_unknown_option(self):
        poll = self.make()
        ids = [o["id"] for o in poll["options"]]
        student = actor("s1", "student", "8А")
        with self.assertRaises(HTTPException):
            polls.vote_for(student, poll["id"], polls.VoteBody(option_ids=ids))
        with self.assertRaises(HTTPException):
            polls.vote_for(student, poll["id"], polls.VoteBody(option_ids=["nope"]))

    def test_closed_poll_rejects_votes_and_only_author_or_admin_can_close(self):
        poll = self.make()
        with self.assertRaises(HTTPException):
            polls.close_poll_for(actor("s1", "student", "8А"), poll["id"])
        polls.close_poll_for(actor("t1", "teacher"), poll["id"])
        with self.assertRaises(HTTPException) as ctx:
            polls.vote_for(actor("s1", "student", "8А"), poll["id"],
                           polls.VoteBody(option_ids=[poll["options"][0]["id"]]))
        self.assertEqual(ctx.exception.status_code, 409)

    def test_duplicate_options_are_rejected(self):
        with self.assertRaises(HTTPException):
            self.make(options=["Да", "да"])

    def test_class_poll_without_class_is_rejected_and_delete_requires_manager(self):
        with self.assertRaises(HTTPException):
            polls.create_poll_for(actor("a1", "admin"), polls.PollCreate(
                title="x", options=["a", "b"], scope="class"))
        poll = self.make()
        with self.assertRaises(HTTPException):
            polls.delete_poll_for(actor("s1", "student", "8А"), poll["id"])
        polls.delete_poll_for(actor("a1", "admin"), poll["id"])
        self.assertEqual(polls.list_polls_for(actor("a1", "admin"))["data"], [])


if __name__ == "__main__":
    unittest.main()
