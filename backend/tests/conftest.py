from __future__ import annotations

"""Shared test fixtures.

Tests run against the configured database (the docker-compose Postgres in local
dev). Each test runs inside a single connection-bound transaction that is rolled
back at teardown, so the database is never mutated — this is SQLAlchemy's
"join a Session into an external transaction" pattern. ``create_savepoint`` makes
the endpoints' own ``commit()`` calls operate on savepoints instead of ending the
outer transaction.
"""

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session

from app.api.deps import get_db
from app.db.session import engine
from app.main import app


@pytest.fixture()
def db_session():
    connection = engine.connect()
    trans = connection.begin()
    session = Session(bind=connection, join_transaction_mode="create_savepoint")
    try:
        yield session
    finally:
        session.close()
        trans.rollback()
        connection.close()


@pytest.fixture()
def client(db_session):
    def _override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = _override_get_db
    try:
        # Note: no `with` — we don't want app startup (super-admin seeding) to run
        # against the real DB; dependency overrides apply regardless.
        yield TestClient(app)
    finally:
        app.dependency_overrides.pop(get_db, None)
