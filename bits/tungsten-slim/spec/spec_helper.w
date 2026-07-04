# Spec helper for tungsten-slim tests

use spec
use slim

Test.configure -> (config)
  config.formatter = :documentation
