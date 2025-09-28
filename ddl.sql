-- WOOF-KNOW (СПРИ) — DDL минимальной схемы SQLite (R0.1–R0.3)
-- Цели: локальный кэш/граф знаний, кандидаты ретрива, логи Q&A.
-- Замечания:
-- - UUIDv7/UUID хранить как TEXT (генерируется приложением).
-- - Времена в UTC, ISO-8601 с миллисекундами: STRFTIME('%Y-%m-%dT%H:%M:%fZ','now').
-- - Включаем внешние ключи, журнал WAL на уровне подключения (PRAGMA в коде).

PRAGMA foreign_keys = ON;

BEGIN IMMEDIATE TRANSACTION;

-- 0) Технические таблицы
CREATE TABLE IF NOT EXISTS meta (
  key TEXT PRIMARY KEY,
  val TEXT
);

-- Версионирование схемы (expand–migrate–contract)
CREATE TABLE IF NOT EXISTS schema_migrations (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  version TEXT NOT NULL,              -- SemVer
  applied_at TEXT NOT NULL DEFAULT (STRFTIME('%Y-%m-%dT%H:%M:%fZ','now')),
  checksum TEXT NOT NULL              -- sha256 sql файла миграции
);

INSERT INTO meta(key, val) VALUES ('schema_version', '0.1.0')
  ON CONFLICT(key) DO UPDATE SET val=excluded.val;

-- 1) Граф документов и структурные связи
CREATE TABLE IF NOT EXISTS node (
  id TEXT PRIMARY KEY,                -- uuid
  title TEXT NOT NULL,
  kind TEXT NOT NULL CHECK(kind IN ('file','sheet','section','page')),
  path TEXT,                          -- исходный путь/идентификатор
  meta TEXT,                          -- JSON (валидируется на уровне приложения)
  created_at TEXT NOT NULL DEFAULT (STRFTIME('%Y-%m-%dT%H:%M:%fZ','now'))
);
CREATE INDEX IF NOT EXISTS node_kind_idx ON node(kind);
CREATE INDEX IF NOT EXISTS node_path_idx ON node(path);

CREATE TABLE IF NOT EXISTS edge (
  src_id TEXT NOT NULL,
  dst_id TEXT NOT NULL,
  type TEXT NOT NULL CHECK(type IN ('cites','refers','parent','next')),
  weight REAL NOT NULL DEFAULT 1.0,
  PRIMARY KEY(src_id, dst_id, type),
  FOREIGN KEY(src_id) REFERENCES node(id) ON DELETE CASCADE,
  FOREIGN KEY(dst_id) REFERENCES node(id) ON DELETE CASCADE
);

-- 2) Фрагменты (чанки) текста и якоря
CREATE TABLE IF NOT EXISTS chunk (
  id TEXT PRIMARY KEY,                -- uuid
  node_id TEXT NOT NULL,
  text TEXT NOT NULL,
  hash TEXT NOT NULL,                 -- детерминированный content-hash
  "order" INTEGER NOT NULL,          -- порядок в документе
  spans TEXT,                         -- JSON: page/sheet/row/offset/len
  created_at TEXT NOT NULL DEFAULT (STRFTIME('%Y-%m-%dT%H:%M:%fZ','now')),
  FOREIGN KEY(node_id) REFERENCES node(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS chunk_node_idx ON chunk(node_id);
CREATE UNIQUE INDEX IF NOT EXISTS chunk_node_order_uidx ON chunk(node_id, "order");
CREATE INDEX IF NOT EXISTS chunk_hash_idx ON chunk(hash);

-- (Опция) FTS5 индекс по чанкам, если доступен модуль.
-- CREATE VIRTUAL TABLE chunk_fts USING fts5(text, content='chunk', content_rowid='rowid');
-- INSERT INTO chunk_fts(rowid, text) SELECT rowid, text FROM chunk; -- первичная загрузка

-- 3) Кандидаты ретрива на вопрос (кэш)
CREATE TABLE IF NOT EXISTS candidate (
  q_hash TEXT NOT NULL,               -- хэш нормализованного вопроса
  node_id TEXT NOT NULL,
  score REAL NOT NULL,
  created_at TEXT NOT NULL DEFAULT (STRFTIME('%Y-%m-%dT%H:%M:%fZ','now')),
  PRIMARY KEY(q_hash, node_id),
  FOREIGN KEY(node_id) REFERENCES node(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS candidate_score_idx ON candidate(q_hash, score DESC);

-- 4) Логи вопросов/ответов и обратная связь
CREATE TABLE IF NOT EXISTS qa_log (
  id TEXT PRIMARY KEY,                -- uuid события
  question TEXT NOT NULL,
  answer TEXT,                        -- может быть NULL при no_answer=1
  no_answer INTEGER NOT NULL DEFAULT 0 CHECK(no_answer IN (0,1)),
  scores TEXT,                        -- JSON массив метрик/score
  show_sources INTEGER NOT NULL DEFAULT 0 CHECK(show_sources IN (0,1)),
  ext_allowed INTEGER NOT NULL DEFAULT 0 CHECK(ext_allowed IN (0,1)),
  feedback INTEGER DEFAULT 0 CHECK(feedback IN (-1,0,1)),
  llm_model TEXT,                     -- фиксируем версию модели/темплейта
  latency_ms INTEGER,                 -- фактическая латентность
  ts TEXT NOT NULL DEFAULT (STRFTIME('%Y-%m-%dT%H:%M:%fZ','now'))
);
CREATE INDEX IF NOT EXISTS qa_log_ts_idx ON qa_log(ts);
CREATE INDEX IF NOT EXISTS qa_log_no_answer_idx ON qa_log(no_answer);

-- 5) Настройки/состояние системы (read-only для R0.2 UI)
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  val TEXT NOT NULL
);
-- Примеры ключей: privacy.profile, llm.provider, llm.model, llm.temperature, llm.timeout_s, limits.rate_per_min

-- 6) Представления (views) для удобной аналитики
CREATE VIEW IF NOT EXISTS v_node_chunks AS
  SELECT n.id AS node_id, n.title, n.kind, n.path, c.id AS chunk_id, c."order", c.hash, LENGTH(c.text) AS len
  FROM node n JOIN chunk c ON c.node_id = n.id;

CREATE VIEW IF NOT EXISTS v_kpi AS
  SELECT
    COUNT(*) AS total,
    SUM(no_answer) AS no_answer_cnt,
    ROUND(100.0 * SUM(no_answer) / NULLIF(COUNT(*),0), 2) AS no_answer_pct,
    ROUND(100.0 * SUM(CASE WHEN feedback=1 THEN 1 ELSE 0 END) / NULLIF(COUNT(*),0), 2) AS positive_pct
  FROM qa_log;

-- 7) Служебные ограничения и дефолты
-- Зафиксировать дефолтный профиль приватности strict_local
INSERT INTO settings(key, val) VALUES ('privacy.profile', 'strict_local')
  ON CONFLICT(key) DO NOTHING;

-- Индикативные настройки LLM (могут быть переопределены через settings API или файл конфигурации)
INSERT INTO settings(key, val) VALUES
  ('llm.provider','ollama'),
  ('llm.model','llama3.1:8b'),
  ('llm.temperature','0.2'),
  ('llm.timeout_s','60')
ON CONFLICT(key) DO NOTHING;

COMMIT;

-- Рекомендации по подключению (в приложении):
-- PRAGMA journal_mode=WAL;
-- PRAGMA synchronous=NORMAL;   -- производительность vs надёжность
-- PRAGMA foreign_keys=ON;
-- Периодические бэкапы: VACUUM INTO 'backup/spree-YYYYMMDD.sqlite';
