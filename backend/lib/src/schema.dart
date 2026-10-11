/// Skema database. Dijalankan satu per satu saat server mulai (CREATE TABLE IF NOT EXISTS).
const List<String> schemaStatements = <String>[
  '''
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  email TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  avatar_url TEXT,
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
  image_url TEXT
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
  created_at TEXT DEFAULT (datetime('now'))
)''',
  '''
CREATE TABLE IF NOT EXISTS tickets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ticket_code TEXT UNIQUE NOT NULL,
  order_id TEXT NOT NULL REFERENCES transactions(order_id),
  event_id INTEGER NOT NULL REFERENCES events(id),
  user_id INTEGER NOT NULL REFERENCES users(id)
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
  created_at TEXT DEFAULT (datetime('now'))
)''',
];
