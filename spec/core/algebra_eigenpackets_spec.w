# Simultaneous exact Hecke eigenpackets, including a number-field packet.
#
# The packet dimensions and q-expansions are differential fixtures from
# SageMath 10.9.  Tungsten's own certificate independently replays the exact
# matrix decomposition through Sturm's bound.

use algebra

-> packet_check(name, got, want)
  if got != want
    raise "FAIL " + name + ": got " + got.to_s + ", want " + want.to_s
  << "PASS " + name

d55 = Gamma0.new(55).eigenpackets(100_000_000)
packet_check("level55.packet_count", d55.size, 2)
packet_check("level55.packet_degrees",
             (d55.packets.map ->
               item.coefficient_field_degree).join(","),
             "1,2")
packet_check("level55.separator_is_T2",
             d55.separator_coefficients[2], 1)
packet_check("level55.certificate", d55.certified?, true)

rational_packet = nil
quadratic_packet = nil
d55.packets.each -> (packet)
  if packet.rational?
    rational_packet = packet
  else
    quadratic_packet = packet

packet_check("level55.rational.a2",
             rational_packet.hecke_eigenvalue(2),
             Rational.new(1))
packet_check("level55.rational.q_expansion",
             rational_packet.q_expansion(4),
             QExpansion.new([0, 1, 1, 0]))

field = quadratic_packet.coefficient_field
theta = field.generator
packet_check("level55.quadratic.field_degree", field.degree, 2)
packet_check("level55.quadratic.a2",
             quadratic_packet.hecke_eigenvalue(2), theta)
packet_check("level55.quadratic.a3",
             quadratic_packet.hecke_eigenvalue(3),
             field.coerce(2) - theta*2)
packet_check("level55.quadratic.a3_certificate",
             quadratic_packet.hecke_eigenvalue_certified?(3),
             true)
expected_coefficients = [
  field.zero, field.one, theta,
  field.coerce(2) - theta*2
]
expected_expansion = FieldQExpansion.new(
  field, expected_coefficients)
packet_check("level55.quadratic.q_expansion",
             quadratic_packet.q_expansion(4),
             expected_expansion)
packet_check("level55.quadratic.q_expansion_certificate",
             quadratic_packet.q_expansion_certificate(4).verified?,
             true)
packet_check("level55.quadratic.hard_precision",
             quadratic_packet.q_expansion(4).precision, 4)

bad_certificate = (
  WeightTwoHeckeEigenpacketDecompositionCertificate.new(
    "not a decomposition"))
packet_check("eigenpackets.tamper_rejected",
             bad_certificate.verified?, false)
