# Exact 20×22×25 GF(2) direct-walk witness

One 100-million-move directed walk from the checked-in r6076 tensor reached
**r6073** with nonce 251700. The source and result are retained in
`manifest.json`; run `python3 verify.py` to reconstruct both full tensors in
Python and Ruby. A further 100-million-move continuation (nonce 251701) tied
at r6073 and is not retained.

Matched third-slot control: the mode-8 basis rewrite of the same r6076
source, with the same 100-million-move budget and nonce 251700, returned
its unchanged r6076 tensor. Its independently checked SHA-256 is
`a5e5c609229672df137adae91f24ff54fdd58bec4ebd39b5ed9f85bede554126`.
This one-control result motivates a bounded direct-source opportunity; it
does not establish a general yield advantage.

The pinned comparison was 6075, but a live
[Lille catalogue](https://fmm.univ-lille.fr/) recheck on 2026-09-25 listed
6062. The new rank is a local GF(2) improvement of three, still 11 above that
live comparison. No world-record, global novelty, or optimality claim is made.
