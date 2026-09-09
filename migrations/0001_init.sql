-- Esquema inicial. Pegar y ejecutar en Cloudflare Dashboard >
-- Workers & Pages > D1 > (tu base) > Console, una sola vez.

CREATE TABLE accounts (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  mt5_login     TEXT NOT NULL UNIQUE,
  label         TEXT,
  broker        TEXT,
  currency      TEXT,
  token_hash    TEXT NOT NULL,
  created_at    TEXT NOT NULL,
  last_seen_at  TEXT
);

CREATE TABLE open_positions (
  account_id   INTEGER NOT NULL REFERENCES accounts(id),
  ticket       TEXT NOT NULL,
  symbol       TEXT,
  type         TEXT,
  volume       REAL,
  open_price   REAL,
  open_time    TEXT,
  sl           REAL,
  tp           REAL,
  profit       REAL,
  swap         REAL,
  magic        INTEGER,
  comment      TEXT,
  updated_at   TEXT NOT NULL,
  PRIMARY KEY (account_id, ticket)
);

CREATE TABLE closed_trades (
  account_id   INTEGER NOT NULL REFERENCES accounts(id),
  ticket       TEXT NOT NULL,
  symbol       TEXT,
  type         TEXT,
  volume       REAL,
  open_price   REAL,
  close_price  REAL,
  open_time    TEXT,
  close_time   TEXT,
  profit       REAL,
  commission   REAL,
  swap         REAL,
  magic        INTEGER,
  comment      TEXT,
  inserted_at  TEXT NOT NULL,
  PRIMARY KEY (account_id, ticket)
);

CREATE TABLE account_snapshots (
  account_id    INTEGER NOT NULL REFERENCES accounts(id),
  ts            TEXT NOT NULL,
  balance       REAL,
  equity        REAL,
  margin        REAL,
  free_margin   REAL,
  margin_level  REAL,
  PRIMARY KEY (account_id, ts)
);

CREATE INDEX idx_closed_trades_account ON closed_trades(account_id, close_time);
CREATE INDEX idx_snapshots_account ON account_snapshots(account_id, ts);
