# Exact F2 intersection of shell-width local-condition transcripts.
#
# Each input is emitted only after shell_width_s_units_verify has replayed a
# complete local BPS image, composed its annihilator with the localization
# matrix, and checked the resulting local constraint.  This program replays
# the finite linear-algebra composition across primes.  It deliberately does
# not treat the transcript headers as a proof of their arithmetic provenance;
# the producing runs remain part of the certificate boundary.

use algebra
use core/file

-> parse_bit_row(text, width)
  if text.size != width
    raise "shell-width constraint row has the wrong width"
  row = []
  text.chars.each -> (character)
    if character == "0"
      row.push(0)
    elsif character == "1"
      row.push(1)
    else
      raise "shell-width constraint row is not binary"
  row

-> header_value(line, prefix)
  return nil if !line.starts_with?(prefix)
  line.slice(
    prefix.size, line.size - prefix.size)

arguments = argv()
if arguments.size == 0
  << "usage: shell_width_local_intersection CONSTRAINT..."
  exit(2)

width = nil
norm_matrix = nil
local_rows = []
primes = []
all_claim_complete = true
all_claim_certified = true

arguments.each -> (path)
  local_width = nil
  local_prime = nil
  local_norm = []
  read_file(path).split("\n").each -> (line)
    value = header_value(line, "# prime=")
    local_prime = value.to_i if value != nil
    value = header_value(line, "# width=")
    local_width = value.to_i if value != nil
    value = header_value(
      line, "# complete_local_image=")
    if value != nil && value != "true"
      all_claim_complete = false
    value = header_value(
      line, "# local_constraint_certified=")
    if value != nil && value != "true"
      all_claim_certified = false
    value = header_value(
      line, "# norm_map_certified=")
    if value != nil && value != "true"
      all_claim_certified = false
    if line.starts_with?("N,")
      local_norm.push(
        parse_bit_row(
          line.slice(2, line.size - 2),
          local_width))
    elsif line.starts_with?("L,")
      local_rows.push(
        parse_bit_row(
          line.slice(2, line.size - 2),
          local_width))
  if local_width == nil || local_prime == nil
    raise "shell-width constraint transcript lacks a header"
  if width == nil
    width = local_width
    norm_matrix = local_norm
  else
    if width != local_width
      raise "shell-width constraint transcripts change width"
    if !F2LinearAlgebra.same_matrix?(
         norm_matrix, local_norm)
      raise "shell-width constraint transcripts change the norm map"
  if primes.include?(local_prime)
    raise "duplicate shell-width local prime"
  primes.push(local_prime)

if !all_claim_complete || !all_claim_certified
  raise "shell-width transcript does not claim a complete certified local image"

system = F2LinearSystem.new(width)
norm_matrix.each -> (row)
  system.add_equation(
    row, 0, "global norm")
local_rows.each -> (row)
  system.add_equation(
    row, 0, "complete local image")
certificate = system.certificate
if !certificate.certified?
  raise "shell-width local intersection failed F2 replay"

<< ["primes",
    GenusThreeThetaPermutation.sort_integers(primes)]
<< ["ambient_dimension", width]
<< ["norm_rows", norm_matrix.size]
<< ["local_rows", local_rows.size]
<< ["intersection_rank", certificate.rank]
<< ["intersection_dimension",
    certificate.kernel_dimension]
<< ["intersection_basis",
    certificate.kernel_basis]
<< ["finite_f2_replay_certified",
    certificate.certified?]
<< ["arithmetic_provenance",
    "claimed by separately replayed producing transcripts"]
<< ["bps_comparison_complete", false]
