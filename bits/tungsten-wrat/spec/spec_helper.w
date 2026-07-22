# Spec helper for tungsten-wrat tests

use spec
use wrat

Test.configure -> (config)
  config.formatter = :documentation
