# Spec helper for tungsten-wassat tests

use spec
use wassat

Test.configure -> (config)
  config.formatter = :documentation
