# Block assembly: coinbase construction and block serialization.
#
# To mine you must build the block you are mining, because the merkle root
# in the header commits to it. The one transaction a miner always builds
# itself is the coinbase — the transaction that pays the reward.
#
# Consensus rules this file implements:
#
#   BIP34   the coinbase scriptSig must begin with a push of the block
#           height as a minimally-encoded script number.
#   BIP141  if the template carries a witness commitment, the coinbase
#           needs an OP_RETURN output holding it, and the coinbase's
#           witness must be a single 32-byte zero item.
#
# Serialization notes: a coinbase's single input has a null 32-byte prevout
# hash and prevout index 0xFFFFFFFF. The txid of a segwit-marked
# transaction is the hash of its NON-witness serialization, which is why
# `btc_coinbase_txid_hex` builds a second, stripped form.

use bitcoin

# ---- coinbase -------------------------------------------------------------

# Build a coinbase transaction.
#
#   height          block height, for the BIP34 push
#   value           reward in satoshis (subsidy + fees)
#   script_pubkey   output script, hex
#   extra_nonce     arbitrary bytes appended to scriptSig, hex — the second
#                   search space when the 32-bit nonce is exhausted
#   commitment      witness commitment scriptPubKey from the template, hex,
#                   or "" when the template has none
#
# Returns the full transaction hex (witness-serialized when a commitment is
# present, since that is the form that goes into the block).
# The one coinbase serializer. `serialize_witness` selects which of the two
# encodings of the SAME transaction to emit:
#
#   1  the witness form — marker/flag plus the witness stack. This is what
#      goes into the block.
#   0  the stripped form — identical except those two parts are omitted.
#      Its double-SHA is the txid, which is why segwit did not invalidate
#      existing txid references.
#
# Both forms come from this single function on purpose. When they were two
# near-identical copies, any edit to one could silently produce a txid that
# did not correspond to the serialized transaction — a consensus bug a node
# would reject the block for, with nothing in the miner to point at it.
-> btc_coinbase_serialize(height, value, script_pubkey, extra_nonce, commitment, serialize_witness)
  btc_coinbase_serialize_ex(height, value, script_pubkey, extra_nonce, commitment, serialize_witness, -1)

# The full serializer. `txtime` covers the peercoin lineage: those chains
# insert a uint32 timestamp between a transaction's version and its input
# count, and a coinbase whose nTime disagrees with the block is rejected.
# Bitcoin-lineage chains have no such field — pass txtime = -1 to omit it.
-> btc_coinbase_serialize_ex(height, value, script_pubkey, extra_nonce, commitment, serialize_witness, txtime)
  has_witness = commitment.size > 0
  # BIP34: the scriptSig must begin with a push of the block height.
  script_sig = btc_push_hex(btc_script_num_hex(height))
  if extra_nonce.size > 0
    script_sig = script_sig + btc_push_hex(extra_nonce)
  tx = "01000000"
  if txtime >= 0
    tx = tx + btc_u32_le_hex(txtime)
  if has_witness && serialize_witness == 1
    # Segwit marker + flag, between version and input count.
    tx = tx + "0001"
  # Exactly one input, with the null prevout that marks a coinbase.
  tx = tx + "01"
  tx = tx + "0000000000000000000000000000000000000000000000000000000000000000"
  tx = tx + "ffffffff"
  tx = tx + btc_varint_hex(script_sig.size / 2) + script_sig
  tx = tx + "ffffffff"
  nout = 1
  if has_witness
    nout = 2
  tx = tx + btc_varint_hex(nout)
  tx = tx + btc_u64_le_hex(value)
  tx = tx + btc_varint_hex(script_pubkey.size / 2) + script_pubkey
  if has_witness
    # BIP141 witness commitment: a zero-value OP_RETURN output.
    tx = tx + btc_u64_le_hex(0)
    tx = tx + btc_varint_hex(commitment.size / 2) + commitment
  if has_witness && serialize_witness == 1
    # One witness stack item of 32 zero bytes — the witness reserved value.
    tx = tx + "01" + "20" + "0000000000000000000000000000000000000000000000000000000000000000"
  tx + "00000000"

# The transaction as it appears in the block.
-> btc_coinbase_hex(height, value, script_pubkey, extra_nonce, commitment)
  btc_coinbase_serialize(height, value, script_pubkey, extra_nonce, commitment, 1)

# Its txid: double-SHA of the stripped serialization, displayed reversed.
-> btc_coinbase_txid_hex(height, value, script_pubkey, extra_nonce, commitment, k)
  btc_txid(btc_coinbase_serialize(height, value, script_pubkey, extra_nonce, commitment, 0), k)

# Coin-flavored forms of the same pair; `txtime` as in the serializer.
-> btc_coinbase_hex_ex(height, value, script_pubkey, extra_nonce, commitment, txtime)
  btc_coinbase_serialize_ex(height, value, script_pubkey, extra_nonce, commitment, 1, txtime)

-> btc_coinbase_txid_hex_ex(height, value, script_pubkey, extra_nonce, commitment, txtime, k)
  btc_txid(btc_coinbase_serialize_ex(height, value, script_pubkey, extra_nonce, commitment, 0, txtime), k)

# ---- block ----------------------------------------------------------------

# Serialize a complete block: 80-byte header, transaction count, then the
# coinbase followed by the template's transactions (already hex).
-> btc_block_hex(header, coinbase_hex, tx_hexes)
  out = btc_bytes_to_hex(header, 80)
  out = out + btc_varint_hex(tx_hexes.size + 1)
  out = out + coinbase_hex
  i = 0
  while i < tx_hexes.size
    out = out + tx_hexes[i]
    i += 1
  out

# A standard P2WPKH output script for a 20-byte key hash: OP_0 <20 bytes>.
-> btc_p2wpkh_script(hash160_hex)
  "0014" + hash160_hex

# Bitcoin's block subsidy: 50 BTC halving every 210000 blocks, reaching zero
# after 64 halvings.
-> btc_subsidy(height)
  halvings = height / 210000
  if halvings >= 64
    return 0
  5000000000 / (1 << halvings)
