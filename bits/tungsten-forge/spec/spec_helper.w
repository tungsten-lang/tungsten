# Forge spec helper

use spec
use forge

TungstenSpec.configure ->
  before_each ->
    Forge.instance = nil  # reset between tests
