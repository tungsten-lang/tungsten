# Spec helper for tungsten-wassat tests

use spec
use ../lib/wassat

Test.configure -> (config)
  config.formatter = :documentation
