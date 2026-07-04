use Tungsten:Spec
use Tungsten:Carbide:Adapters:%class_name%Adapter

describe %class_name%Adapter ->
  let :config, {host: "localhost", database: "test_db"}
  let :adapter, %class_name%Adapter.new(config)

  describe "#connect" ->
    it "establishes a connection" ->
      adapter.connect
      expect(adapter.connected?).to be_true

  describe "#disconnect" ->
    it "closes all connections in the pool" ->
      adapter.connect
      adapter.disconnect
      expect(adapter.connected?).to be_false

  describe "#execute" ->
    it "runs a raw SQL statement" ->
      adapter.connect
      result = adapter.execute("SELECT 1 AS num")
      expect(result).to_not be_nil

  describe "#transaction" ->
    it "commits on success" ->
      adapter.connect
      adapter.transaction -> (conn)
        conn.execute("INSERT INTO test_table (name) VALUES ($1)", "test")
      # Verify the insert persisted

    it "rolls back on error" ->
      adapter.connect
      expect ->
        adapter.transaction -> (conn)
          conn.execute("INSERT INTO test_table (name) VALUES ($1)", "test")
          <! "rollback!"
      self.to raise_error

  describe "#tables" ->
    it "returns a list of table names" ->
      adapter.connect
      tables = adapter.tables
      expect(tables).to be_a(Array)
