"""Tests for cli/lessons/db.py — lessons database layer."""

from __future__ import annotations

import sqlite3
from pathlib import Path

import pytest

from cli.lessons.db import (
    get_metadata,
    get_or_create_project,
    get_or_create_tag,
    init_lessons_db,
    insert_lesson,
    set_metadata,
    tag_lesson,
    update_lesson,
)


@pytest.fixture
def db(tmp_path: Path) -> sqlite3.Connection:
    """Create a fresh lessons DB in a temp directory."""
    return init_lessons_db(tmp_path / "test-lessons.db")


# ---------------------------------------------------------------------------
# Schema initialization
# ---------------------------------------------------------------------------


class TestInitDb:
    def test_creates_all_tables(self, db: sqlite3.Connection) -> None:
        tables = {
            row[0]
            for row in db.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            ).fetchall()
        }
        assert {"projects", "tags", "lessons", "metadata", "lesson_tags"} <= tables

    def test_creates_fts_table(self, db: sqlite3.Connection) -> None:
        tables = {
            row[0]
            for row in db.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            ).fetchall()
        }
        assert "lessons_fts" in tables

    def test_wal_mode(self, db: sqlite3.Connection) -> None:
        mode = db.execute("PRAGMA journal_mode").fetchone()[0]
        assert mode == "wal"

    def test_foreign_keys_on(self, db: sqlite3.Connection) -> None:
        fk = db.execute("PRAGMA foreign_keys").fetchone()[0]
        assert fk == 1

    def test_idempotent(self, tmp_path: Path) -> None:
        db_path = tmp_path / "idempotent.db"
        conn1 = init_lessons_db(db_path)
        conn1.close()
        conn2 = init_lessons_db(db_path)
        tables = {
            row[0]
            for row in conn2.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            ).fetchall()
        }
        assert "lessons" in tables
        conn2.close()


# ---------------------------------------------------------------------------
# Project helpers
# ---------------------------------------------------------------------------


class TestProjects:
    def test_create_and_get(self, db: sqlite3.Connection) -> None:
        pid = get_or_create_project(db, "my-project")
        assert pid > 0
        assert get_or_create_project(db, "my-project") == pid

    def test_unique_names(self, db: sqlite3.Connection) -> None:
        p1 = get_or_create_project(db, "alpha")
        p2 = get_or_create_project(db, "beta")
        assert p1 != p2


# ---------------------------------------------------------------------------
# Tag helpers
# ---------------------------------------------------------------------------


class TestTags:
    def test_create_and_get(self, db: sqlite3.Connection) -> None:
        tid = get_or_create_tag(db, "git", keywords="git,push,pull")
        assert tid > 0
        assert get_or_create_tag(db, "git") == tid

    def test_updates_keywords(self, db: sqlite3.Connection) -> None:
        tid = get_or_create_tag(db, "git", keywords="git")
        get_or_create_tag(db, "git", keywords="git,push,pull,merge")
        row = db.execute("SELECT keywords FROM tags WHERE id = ?", (tid,)).fetchone()
        assert row[0] == "git,push,pull,merge"

    def test_default_status(self, db: sqlite3.Connection) -> None:
        tid = get_or_create_tag(db, "test-tag")
        row = db.execute("SELECT status FROM tags WHERE id = ?", (tid,)).fetchone()
        assert row[0] == "active"


# ---------------------------------------------------------------------------
# Lesson CRUD
# ---------------------------------------------------------------------------


class TestLessons:
    def test_insert_lesson(self, db: sqlite3.Connection) -> None:
        lid = insert_lesson(
            db,
            lesson_id="proj_20260324T1200_001",
            project_name="my-project",
            date="2026-03-24",
            text="Always use absolute paths",
            tag_names=["pattern", "git"],
        )
        assert lid == "proj_20260324T1200_001"
        row = db.execute("SELECT text, tier, active FROM lessons WHERE id = ?", (lid,)).fetchone()
        assert row == ("Always use absolute paths", "recent", 1)

    def test_insert_creates_tags(self, db: sqlite3.Connection) -> None:
        insert_lesson(
            db,
            lesson_id="proj_20260324T1200_001",
            project_name="my-project",
            date="2026-03-24",
            text="Test lesson",
            tag_names=["alpha", "beta"],
        )
        tags = db.execute(
            """SELECT t.name FROM tags t
               JOIN lesson_tags lt ON t.id = lt.tag_id
               WHERE lt.lesson_id = ?
               ORDER BY t.name""",
            ("proj_20260324T1200_001",),
        ).fetchall()
        assert [r[0] for r in tags] == ["alpha", "beta"]

    def test_insert_updates_tag_counts(self, db: sqlite3.Connection) -> None:
        insert_lesson(
            db,
            lesson_id="proj_20260324T1200_001",
            project_name="proj",
            date="2026-03-24",
            text="Lesson one",
            tag_names=["shared"],
        )
        insert_lesson(
            db,
            lesson_id="proj_20260324T1200_002",
            project_name="proj",
            date="2026-03-24",
            text="Lesson two",
            tag_names=["shared"],
        )
        count = db.execute(
            "SELECT lesson_count FROM tags WHERE name = 'shared'"
        ).fetchone()[0]
        assert count == 2

    def test_insert_with_tier(self, db: sqlite3.Connection) -> None:
        insert_lesson(
            db,
            lesson_id="proj_20260324T1200_001",
            project_name="proj",
            date="2026-03-24",
            text="Key lesson",
            tag_names=["pattern"],
            tier="key",
            promoted="2026-03-24",
        )
        row = db.execute("SELECT tier, promoted FROM lessons WHERE id = ?", ("proj_20260324T1200_001",)).fetchone()
        assert row == ("key", "2026-03-24")

    def test_update_lesson(self, db: sqlite3.Connection) -> None:
        insert_lesson(
            db,
            lesson_id="proj_20260324T1200_001",
            project_name="proj",
            date="2026-03-24",
            text="Some lesson",
            tag_names=["gotcha"],
        )
        update_lesson(db, "proj_20260324T1200_001", tier="key", promoted="2026-03-24")
        row = db.execute("SELECT tier, promoted FROM lessons WHERE id = ?", ("proj_20260324T1200_001",)).fetchone()
        assert row == ("key", "2026-03-24")

    def test_update_active_refreshes_counts(self, db: sqlite3.Connection) -> None:
        insert_lesson(
            db,
            lesson_id="proj_20260324T1200_001",
            project_name="proj",
            date="2026-03-24",
            text="Active lesson",
            tag_names=["test-tag"],
        )
        count_before = db.execute("SELECT lesson_count FROM tags WHERE name = 'test-tag'").fetchone()[0]
        assert count_before == 1
        update_lesson(db, "proj_20260324T1200_001", active=0)
        count_after = db.execute("SELECT lesson_count FROM tags WHERE name = 'test-tag'").fetchone()[0]
        assert count_after == 0

    def test_duplicate_id_raises(self, db: sqlite3.Connection) -> None:
        insert_lesson(
            db,
            lesson_id="proj_20260324T1200_001",
            project_name="proj",
            date="2026-03-24",
            text="First",
            tag_names=["a"],
        )
        with pytest.raises(sqlite3.IntegrityError):
            insert_lesson(
                db,
                lesson_id="proj_20260324T1200_001",
                project_name="proj",
                date="2026-03-24",
                text="Duplicate",
                tag_names=["b"],
            )


# ---------------------------------------------------------------------------
# Tag lesson junction
# ---------------------------------------------------------------------------


class TestTagLesson:
    def test_tag_lesson_ignores_duplicates(self, db: sqlite3.Connection) -> None:
        insert_lesson(
            db,
            lesson_id="proj_20260324T1200_001",
            project_name="proj",
            date="2026-03-24",
            text="Test",
            tag_names=["alpha"],
        )
        tid = get_or_create_tag(db, "alpha")
        # Should not raise on duplicate
        tag_lesson(db, "proj_20260324T1200_001", [tid])
        count = db.execute(
            "SELECT COUNT(*) FROM lesson_tags WHERE lesson_id = ?",
            ("proj_20260324T1200_001",),
        ).fetchone()[0]
        assert count == 1


# ---------------------------------------------------------------------------
# Metadata
# ---------------------------------------------------------------------------


class TestMetadata:
    def test_set_and_get(self, db: sqlite3.Connection) -> None:
        set_metadata(db, "last_manage_run", "2026-03-24T12:00:00")
        assert get_metadata(db, "last_manage_run") == "2026-03-24T12:00:00"

    def test_upsert(self, db: sqlite3.Connection) -> None:
        set_metadata(db, "key1", "old")
        set_metadata(db, "key1", "new")
        assert get_metadata(db, "key1") == "new"

    def test_missing_key(self, db: sqlite3.Connection) -> None:
        assert get_metadata(db, "nonexistent") is None


# ---------------------------------------------------------------------------
# FTS5 search
# ---------------------------------------------------------------------------


class TestFTS:
    def test_fts_finds_lesson(self, db: sqlite3.Connection) -> None:
        insert_lesson(
            db,
            lesson_id="proj_20260324T1200_001",
            project_name="proj",
            date="2026-03-24",
            text="Always use absolute paths when running commands",
            tag_names=["pattern"],
        )
        rows = db.execute(
            """SELECT l.id, highlight(lessons_fts, 0, '>>>', '<<<')
               FROM lessons_fts
               JOIN lessons l ON l.rowid = lessons_fts.rowid
               WHERE lessons_fts MATCH '"absolute" "paths"'"""
        ).fetchall()
        assert len(rows) == 1
        assert rows[0][0] == "proj_20260324T1200_001"

    def test_fts_no_match(self, db: sqlite3.Connection) -> None:
        insert_lesson(
            db,
            lesson_id="proj_20260324T1200_001",
            project_name="proj",
            date="2026-03-24",
            text="Some unrelated lesson",
            tag_names=["gotcha"],
        )
        rows = db.execute(
            "SELECT * FROM lessons_fts WHERE lessons_fts MATCH '\"zzzznotfound\"'"
        ).fetchall()
        assert len(rows) == 0

    def test_fts_updated_after_text_change(self, db: sqlite3.Connection) -> None:
        insert_lesson(
            db,
            lesson_id="proj_20260324T1200_001",
            project_name="proj",
            date="2026-03-24",
            text="Original text about testing",
            tag_names=["pattern"],
        )
        db.execute(
            "UPDATE lessons SET text = 'New text about deployment' WHERE id = ?",
            ("proj_20260324T1200_001",),
        )
        db.commit()
        # Old text should not match
        old = db.execute(
            "SELECT * FROM lessons_fts WHERE lessons_fts MATCH '\"testing\"'"
        ).fetchall()
        assert len(old) == 0
        # New text should match
        new = db.execute(
            "SELECT * FROM lessons_fts WHERE lessons_fts MATCH '\"deployment\"'"
        ).fetchall()
        assert len(new) == 1

    def test_fts_deleted_after_lesson_delete(self, db: sqlite3.Connection) -> None:
        insert_lesson(
            db,
            lesson_id="proj_20260324T1200_001",
            project_name="proj",
            date="2026-03-24",
            text="Lesson to be deleted",
            tag_names=["gotcha"],
        )
        db.execute("DELETE FROM lessons WHERE id = ?", ("proj_20260324T1200_001",))
        db.commit()
        rows = db.execute(
            "SELECT * FROM lessons_fts WHERE lessons_fts MATCH '\"deleted\"'"
        ).fetchall()
        assert len(rows) == 0


# ---------------------------------------------------------------------------
# Foreign key constraints
# ---------------------------------------------------------------------------


class TestConstraints:
    def test_tier_check(self, db: sqlite3.Connection) -> None:
        get_or_create_project(db, "proj")
        with pytest.raises(sqlite3.IntegrityError):
            db.execute(
                """INSERT INTO lessons (id, project_id, date, tier, active, text)
                   VALUES ('x', 1, '2026-01-01', 'invalid_tier', 1, 'test')"""
            )

    def test_tag_status_check(self, db: sqlite3.Connection) -> None:
        with pytest.raises(sqlite3.IntegrityError):
            db.execute(
                """INSERT INTO tags (name, status) VALUES ('bad', 'invalid_status')"""
            )

    def test_cascade_delete_lesson_removes_tags(self, db: sqlite3.Connection) -> None:
        insert_lesson(
            db,
            lesson_id="proj_20260324T1200_001",
            project_name="proj",
            date="2026-03-24",
            text="Will be deleted",
            tag_names=["alpha", "beta"],
        )
        db.execute("DELETE FROM lessons WHERE id = ?", ("proj_20260324T1200_001",))
        db.commit()
        count = db.execute(
            "SELECT COUNT(*) FROM lesson_tags WHERE lesson_id = ?",
            ("proj_20260324T1200_001",),
        ).fetchone()[0]
        assert count == 0
