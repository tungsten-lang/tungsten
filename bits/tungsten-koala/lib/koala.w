# Koala — data science and machine learning for Tungsten
# A friendlier pandas, with linear algebra, ML pipelines, and interop.

in Tungsten

use version
use data_frame
use series
use index
use group_by
use join
use pivot
use rolling
use resample
use matrix
use vector
use tensor
use linalg
use stats
use pipeline
use transformer
use estimator
use scaler
use encoder
use imputer
use splitter
use metrics
use io
use plot
use notebook

+ Koala
  # Read a CSV file into a DataFrame.
  #
  #     df = Koala.read_csv("data.csv")
  #     df = Koala.read_csv("data.csv", header: true, delimiter: ",")
  -> .read_csv(path, **options)
    IO:CSV.read(path, **options)

  # Read a Parquet file into a DataFrame.
  -> .read_parquet(path, **options)
    IO:Parquet.read(path, **options)

  # Read a JSON file into a DataFrame.
  -> .read_json(path, **options)
    IO:JSON.read(path, **options)

  # Read an Excel file into a DataFrame.
  -> .read_excel(path, **options)
    IO:Excel.read(path, **options)

  # Read from a SQL query into a DataFrame.
  #
  #     df = Koala.read_sql("SELECT * FROM users", conn)
  -> .read_sql(query, connection, **options)
    IO:SQL.read(query, connection, **options)

  # Read Apache Arrow format into a DataFrame.
  -> .read_arrow(path, **options)
    IO:Arrow.read(path, **options)

  # Load a dataset from HuggingFace Hub.
  #
  #     dataset = Koala.from_huggingface("squad", split: "train")
  #     dataset = Koala.from_huggingface("imdb", split: "test", streaming: true)
  -> .from_huggingface(name, **options)
    IO:HuggingFace.load_dataset(name, **options)

  # Search HuggingFace Hub for datasets.
  #
  #     results = Koala.search_huggingface("sentiment analysis", limit: 10)
  -> .search_huggingface(query, **options)
    IO:HuggingFace.search(query, **options)

  # Create a DataFrame from a hash of columns.
  #
  #     df = Koala.frame(name: ["Alice", "Bob"], age: [30, 25])
  -> .frame(**columns)
    DataFrame.new(**columns)

  # Create an identity matrix of size n.
  -> .eye(n)
    Matrix.identity(n)

  # Create a zero matrix of given dimensions.
  -> .zeros(rows, cols = rows)
    Matrix.zeros(rows, cols)

  # Create a matrix of ones.
  -> .ones(rows, cols = rows)
    Matrix.ones(rows, cols)

  # Create a random matrix with values in [0, 1).
  -> .random(rows, cols = rows)
    Matrix.random(rows, cols)

  # Create a vector from values.
  -> .vec(*values)
    Vector.new(values)
