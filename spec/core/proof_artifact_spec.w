# Hash-bound proof-artifact integrity and dependency closure.
# Run in both engines:
#   bin/tungsten run spec/core/proof_artifact_spec.w
#   bin/tungsten compile spec/core/proof_artifact_spec.w \
#     --out /tmp/proof-artifact-spec --no-lto

use proof_artifact

-> artifact_check(name, condition)
  raise "FAIL " + name if !condition
  << "PASS " + name

source_hash = Digest.sha256("theorem source")
leaf_payload = "p cnf 1 2\n1 0\n-1 0\n"
leaf = ProofArtifactBundle.new({
  :artifact_id => "ramsey-leaf",
  :format => :lrat,
  :payload => leaf_payload,
  :sha256 => Digest.sha256(leaf_payload),
  :producer => "tungsten-wrat",
  :producer_version => "0.0.2",
  :source_bindings => [["problem", source_hash]]})

artifact_check("sha.valid", ProofArtifacts.valid_sha256?(leaf.actual_sha256))
artifact_check("content", leaf.content_integrity_verified?)
artifact_check("dependencies.empty", leaf.dependency_integrity_verified?)
artifact_check("integrity", leaf.integrity_verified?)
artifact_check("scope", leaf.claim_status == :integrity_only)
artifact_check("kernel.not_claimed", !leaf.kernel_checked?)

parent_payload = "named theorem manifest"
parent = ProofArtifactBundle.new({
  :artifact_id => "astra-result",
  :format => :lean_manifest,
  :payload => parent_payload,
  :sha256 => Digest.sha256(parent_payload),
  :producer => "lake",
  :producer_version => "Lean 4.32.0",
  :source_bindings => [["paper", source_hash]],
  :dependencies => [leaf]})
artifact_check("dependency_closure", parent.integrity_verified?)
artifact_check("dependency_count", parent.dependencies.size == 1)

tampered = ProofArtifactBundle.new({
  :artifact_id => "tampered",
  :format => :lrat,
  :payload => "different payload",
  :sha256 => leaf.actual_sha256,
  :producer => "fixture",
  :producer_version => "1"})
artifact_check("tamper.rejected", !tampered.integrity_verified?)

<< "proof_artifact_spec: all checks passed"
