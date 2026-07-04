# Database configuration for %name%
{
  development: {
    adapter:  "postgres",
    host:     "localhost",
    database: "%name%_development",
    pool:     5
  },
  test: {
    adapter:  "postgres",
    host:     "localhost",
    database: "%name%_test",
    pool:     5
  },
  production: {
    adapter:  "postgres",
    url:      ENV["DATABASE_URL"],
    pool:     ENV["DB_POOL"] || 25
  }
}
