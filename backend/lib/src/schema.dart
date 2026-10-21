/// Skema database. Dijalankan satu per satu saat server mulai (CREATE TABLE IF NOT EXISTS).
const List<String> schemaStatements = <String>[
  '''
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  avatar_url TEXT,
  role TEXT NOT NULL DEFAULT 'user',
  created_at TEXT DEFAULT (datetime('now'))
)''',
  '''
CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  artist TEXT,
  spotify_artist_id TEXT,
  category TEXT,
  venue_name TEXT,
  latitude REAL,
  longitude REAL,
  is_outdoor INTEGER DEFAULT 0,
  start_time_utc TEXT NOT NULL,
  end_time_utc TEXT NOT NULL,
  price_idr INTEGER NOT NULL,
  stock INTEGER NOT NULL,
  image_url TEXT,
  status TEXT NOT NULL DEFAULT 'active'
)''',
  '''
CREATE TABLE IF NOT EXISTS transactions (
  order_id TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id),
  event_id INTEGER NOT NULL REFERENCES events(id),
  qty INTEGER NOT NULL,
  gross_amount INTEGER NOT NULL,
  status TEXT DEFAULT 'pending',
  snap_token TEXT,
  tier_id INTEGER,
  tier_name TEXT,
  holder_name TEXT,
  holder_nik TEXT,
  holder_age INTEGER,
  holder_gender TEXT,
  created_at TEXT DEFAULT (datetime('now'))
)''',
  '''
CREATE TABLE IF NOT EXISTS ticket_tiers (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  event_id INTEGER NOT NULL REFERENCES events(id),
  name TEXT NOT NULL,
  description TEXT,
  price_idr INTEGER NOT NULL,
  stock INTEGER NOT NULL,
  sort_order INTEGER DEFAULT 0
)''',
  '''
CREATE TABLE IF NOT EXISTS tickets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ticket_code TEXT UNIQUE NOT NULL,
  order_id TEXT NOT NULL REFERENCES transactions(order_id),
  event_id INTEGER NOT NULL REFERENCES events(id),
  user_id INTEGER NOT NULL REFERENCES users(id),
  used_at TEXT,
  checked_in_by INTEGER REFERENCES users(id)
)''',
  '''
CREATE TABLE IF NOT EXISTS blocks (
  idx INTEGER PRIMARY KEY,
  timestamp TEXT NOT NULL,
  ticket_code TEXT NOT NULL,
  user_id INTEGER NOT NULL,
  prev_hash TEXT NOT NULL,
  hash TEXT NOT NULL
)''',
  '''
CREATE TABLE IF NOT EXISTS notifications (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id),
  title TEXT,
  body TEXT,
  is_read INTEGER DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now'))
)''',
  '''
CREATE TABLE IF NOT EXISTS promos (
  code TEXT PRIMARY KEY,
  description TEXT NOT NULL,
  discount_percent INTEGER NOT NULL,
  active INTEGER DEFAULT 1
)''',
  '''
CREATE TABLE IF NOT EXISTS course_feedback (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id),
  rating INTEGER NOT NULL,
  message TEXT NOT NULL,
  created_at TEXT DEFAULT (datetime('now'))
)''',
  '''
CREATE TABLE IF NOT EXISTS emergency_alerts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER NOT NULL REFERENCES users(id),
  event_id INTEGER REFERENCES events(id),
  ticket_code TEXT,
  latitude REAL,
  longitude REAL,
  responded_at TEXT,
  responded_by INTEGER REFERENCES users(id),
  created_at TEXT DEFAULT (datetime('now'))
)''',
  '''
CREATE TABLE IF NOT EXISTS admin_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  admin_id INTEGER NOT NULL REFERENCES users(id),
  action TEXT NOT NULL,
  target TEXT,
  detail TEXT,
  created_at TEXT DEFAULT (datetime('now'))
)''',
];

/// Skema untuk Postgres (Supabase). Setara dengan [schemaStatements].
/// created_at disimpan sebagai TEXT berformat 'YYYY-MM-DD HH:MM:SS' (UTC), sama dengan SQLite,
/// supaya JSON dan perbandingan tanggal di kode berperilaku identik di kedua mesin.
const List<String> pgSchemaStatements = <String>[
  '''
CREATE TABLE IF NOT EXISTS users (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  avatar_url TEXT,
  role TEXT NOT NULL DEFAULT 'user',
  created_at TEXT DEFAULT to_char(timezone('utc', now()), 'YYYY-MM-DD HH24:MI:SS')
)''',
  '''
CREATE TABLE IF NOT EXISTS events (
  id BIGSERIAL PRIMARY KEY,
  title TEXT NOT NULL,
  artist TEXT,
  spotify_artist_id TEXT,
  category TEXT,
  venue_name TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  is_outdoor INTEGER DEFAULT 0,
  start_time_utc TEXT NOT NULL,
  end_time_utc TEXT NOT NULL,
  price_idr INTEGER NOT NULL,
  stock INTEGER NOT NULL,
  image_url TEXT,
  status TEXT NOT NULL DEFAULT 'active'
)''',
  '''
CREATE TABLE IF NOT EXISTS transactions (
  order_id TEXT PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id),
  event_id BIGINT NOT NULL REFERENCES events(id),
  qty INTEGER NOT NULL,
  gross_amount INTEGER NOT NULL,
  status TEXT DEFAULT 'pending',
  snap_token TEXT,
  tier_id BIGINT,
  tier_name TEXT,
  holder_name TEXT,
  holder_nik TEXT,
  holder_age INTEGER,
  holder_gender TEXT,
  created_at TEXT DEFAULT to_char(timezone('utc', now()), 'YYYY-MM-DD HH24:MI:SS')
)''',
  '''
CREATE TABLE IF NOT EXISTS ticket_tiers (
  id BIGSERIAL PRIMARY KEY,
  event_id BIGINT NOT NULL REFERENCES events(id),
  name TEXT NOT NULL,
  description TEXT,
  price_idr INTEGER NOT NULL,
  stock INTEGER NOT NULL,
  sort_order INTEGER DEFAULT 0
)''',
  '''
CREATE TABLE IF NOT EXISTS tickets (
  id BIGSERIAL PRIMARY KEY,
  ticket_code TEXT UNIQUE NOT NULL,
  order_id TEXT NOT NULL REFERENCES transactions(order_id),
  event_id BIGINT NOT NULL REFERENCES events(id),
  user_id BIGINT NOT NULL REFERENCES users(id),
  used_at TEXT,
  checked_in_by BIGINT REFERENCES users(id)
)''',
  '''
CREATE TABLE IF NOT EXISTS blocks (
  idx INTEGER PRIMARY KEY,
  timestamp TEXT NOT NULL,
  ticket_code TEXT NOT NULL,
  user_id BIGINT NOT NULL,
  prev_hash TEXT NOT NULL,
  hash TEXT NOT NULL
)''',
  '''
CREATE TABLE IF NOT EXISTS notifications (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id),
  title TEXT,
  body TEXT,
  is_read INTEGER DEFAULT 0,
  created_at TEXT DEFAULT to_char(timezone('utc', now()), 'YYYY-MM-DD HH24:MI:SS')
)''',
  '''
CREATE TABLE IF NOT EXISTS promos (
  code TEXT PRIMARY KEY,
  description TEXT NOT NULL,
  discount_percent INTEGER NOT NULL,
  active INTEGER DEFAULT 1
)''',
  '''
CREATE TABLE IF NOT EXISTS course_feedback (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id),
  rating INTEGER NOT NULL,
  message TEXT NOT NULL,
  created_at TEXT DEFAULT to_char(timezone('utc', now()), 'YYYY-MM-DD HH24:MI:SS')
)''',
  '''
CREATE TABLE IF NOT EXISTS emergency_alerts (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id),
  event_id BIGINT REFERENCES events(id),
  ticket_code TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  responded_at TEXT,
  responded_by BIGINT REFERENCES users(id),
  created_at TEXT DEFAULT to_char(timezone('utc', now()), 'YYYY-MM-DD HH24:MI:SS')
)''',
  '''
CREATE TABLE IF NOT EXISTS admin_logs (
  id BIGSERIAL PRIMARY KEY,
  admin_id BIGINT NOT NULL REFERENCES users(id),
  action TEXT NOT NULL,
  target TEXT,
  detail TEXT,
  created_at TEXT DEFAULT to_char(timezone('utc', now()), 'YYYY-MM-DD HH24:MI:SS')
)''',
];
