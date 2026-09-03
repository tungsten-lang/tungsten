# Hash-bound external proof artifacts.
#
# This module verifies content integrity, source bindings, and dependency
# closure for externally produced proof objects. It does not execute Lean,
# WRAT, or another proof kernel, and `kernel_checked?` therefore remains false.

use core/digest

+ ProofArtifacts
  -> .valid_sha256?(value)
    return false if value.class_name != "String" || value.size != 64
    index = 0
    while index < value.size
      byte = value[index]
      valid = ((byte >= "0" && byte <= "9") ||
               (byte >= "a" && byte <= "f"))
      return false if !valid
      index += 1
    true

  -> .copy_vector(values)
    out = []
    values.each -> (value)
      out.push(value)
    out

  -> .copy_bindings(bindings)
    out = []
    bindings.each -> (binding)
      out.push([binding[0], binding[1]])
    out


+ ProofArtifactBundle
  # Required record keys:
  #   :artifact_id, :format, :payload, :sha256, :producer, :producer_version
  # Optional:
  #   :source_bindings => [[name, sha256], ...]
  #   :dependencies    => [ProofArtifactBundle, ...]
  -> new(record)
    if record.class_name != "Hash"
      raise "proof artifact bundle needs a record"
    required = [:artifact_id, :format, :payload, :sha256,
                :producer, :producer_version]
    required.each -> (key)
      if !record.has_key?(key)
        raise "proof artifact bundle is missing " + key.to_s
    @artifact_id = record[:artifact_id]
    @format = record[:format]
    @payload = record[:payload]
    @expected_sha256 = record[:sha256]
    @producer = record[:producer]
    @producer_version = record[:producer_version]
    bindings = record.has_key?(:source_bindings) ? record[:source_bindings] : []
    dependencies = record.has_key?(:dependencies) ? record[:dependencies] : []
    if bindings.class_name != "Array" || dependencies.class_name != "Array"
      raise "proof artifact bindings and dependencies must be arrays"
    @source_bindings = ProofArtifacts.copy_bindings(bindings)
    @dependencies = ProofArtifacts.copy_vector(dependencies)
    if @payload.class_name != "String"
      raise "proof artifact payload must be a String"
    if !ProofArtifacts.valid_sha256?(@expected_sha256)
      raise "proof artifact SHA-256 must be 64 lowercase hexadecimal digits"
    @source_bindings.each -> (binding)
      if (binding.class_name != "Array" || binding.size != 2 ||
          !ProofArtifacts.valid_sha256?(binding[1]))
        raise "proof artifact source binding must be \[name, sha256]"
    @dependencies.each -> (dependency)
      if dependency.class_name != "ProofArtifactBundle"
        raise "proof artifact dependency has the wrong type"

  -> artifact_id
    @artifact_id

  -> format
    @format

  -> producer
    @producer

  -> producer_version
    @producer_version

  -> expected_sha256
    @expected_sha256

  -> actual_sha256
    Digest.sha256(@payload)

  -> source_bindings
    ProofArtifacts.copy_bindings(@source_bindings)

  -> dependencies
    ProofArtifacts.copy_vector(@dependencies)

  -> content_integrity_verified?
    actual_sha256 == @expected_sha256

  -> dependency_integrity_verified?
    @dependencies.each -> (dependency)
      return false if !dependency.integrity_verified?
    true

  -> integrity_verified?
    content_integrity_verified? && dependency_integrity_verified?

  -> verified?
    integrity_verified?

  -> proof_kind
    :external_proof_artifact_integrity_only

  -> claim_status
    :integrity_only

  -> kernel_checked?
    false
