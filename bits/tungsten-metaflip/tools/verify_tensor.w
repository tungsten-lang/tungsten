# Independent GF(2) reconstruction of matrix-multiplication tensor certificates.
# Does not invoke the searcher's verifier. Port of tools/verify_tensor.rb.
#
#   verify_tensor.w [--shape NxMxP] [--gate dense|sparse|both] [--strict]
#                   [--batch LISTFILE] [--keep-going] CERTIFICATE...
#
# Prints, as JSON.pretty_generate does, one record per certificate
# (exact, shape, rank, density, sha256, path); on any failure prints
# `Tensor verification failed: MESSAGE` on stderr and exits 1, having printed
# no records. The shape comes from --shape or from the deepest NxMxP component
# of the certificate's absolute path.
#
# Beyond the Ruby original:
#   --gate G       which exactness gate(s) decide: dense (the Ruby formulation),
#                  sparse (the Python `exact` formulation) or both (default; they
#                  must agree). All three give the same records and verdicts.
#   --strict       accept only canonical MFW1 (Scheme.parse, the Python read_blob
#                  rule); the shape is then optional.
#   --batch LIST   also verify every path listed in LIST, one per line, optionally
#                  followed by a TAB and its NxMxP (# comments, blank lines skipped):
#                  a thousand certificates cost one process start, not a thousand.
#   --keep-going   verify all certificates, print the records of the good ones and
#                  one failure line per bad one on stderr; exit 1 if any failed.
#
# The certificate formats and the checks are documented in
# lib/metaflip/gf2/tensor_verifier.w.
use ../lib/metaflip/gf2/tensor_verifier

result = Metaflip:Gf2:TensorVerifier.main(argv())
<- result[1]
ccall("w_eputs", result[2].strip) if result[2] != ""
exit(result[0])
