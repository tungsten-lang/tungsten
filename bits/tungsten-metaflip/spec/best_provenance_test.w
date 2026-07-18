use ../lib/metaflip/fleet/provenance

-> fflpt_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL best provenance " + label
    exit(1)
  1

meta = i64[fflp_size()]
ok = fflp_set(meta, 2, 17, 3, 1, 291, 0, 77123, 248, 3120, 1, 44551, 38, 99117, 247, 3095, 803) ## i64
z = fflpt_expect("record accepted", ok == 1)
z = fflpt_expect("kind names", fflp_kind_name(2) == "cpu" && fflp_kind_name(5) == "late-gpu" && fflp_kind_name(7) == "global-isotropy" && fflp_kind_name(99) == "unknown")

fields = fflp_status_fields(meta, "near1 seed\nsource=spoof", "near1 balanced")
z = fflpt_expect("source is tokenized", fields.include?("best_source=near1_seed_source_spoof") && !fields.include?("\nsource=") && !fields.include?(" source=spoof"))
z = fflpt_expect("responsible worker retained", fields.include?("best_source_kind=cpu") && fields.include?("best_worker=17"))
z = fflpt_expect("restart lineage retained", fields.include?("best_round=291") && fields.include?("best_worker_moves=0") && fields.include?("best_parent_id=77123") && fields.include?("best_debt=1") && fields.include?("best_basin=44551"))
z = fflpt_expect("candidate identity retained", fields.include?("best_id=99117") && fields.include?("best_event_rank=247") && fields.include?("best_event_bits=3095"))

post = i64[fflp_size()]
z = fflpt_expect("postprocessor record accepted", fflp_set(post, 7, 4, 10, 2, 300, 113101, 99117, 247, 3095, 0, 0 - 1, 6, 99119, 247, 3094, 809) == 1)
post_fields = fflp_status_fields(post, "gpu-slot4/generic/global-isotropy", "global-isotropy-after-generic")
z = fflpt_expect("postprocessor checkpoint identity retained", post_fields.include?("best_source_kind=global-isotropy") && post_fields.include?("best_replay_seed=113101") && post_fields.include?("best_parent_id=99117") && post_fields.include?("best_parent_bits=3095") && post_fields.include?("best_id=99119") && post_fields.include?("best_event_bits=3094"))

long = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"
token = fflp_token(long, 32)
z = fflpt_expect("token is bounded", token.size() == 32)
z = fflpt_expect("empty token fails closed", fflp_token("", 96) == "unknown" && fflp_token("x", 0) == "unknown")

event = fflp_event_body("run 7=bad", 7, 19, meta, "door 3", "balanced lane")
z = fflpt_expect("event header", event.starts_with?("schema=1 event=best_adoption run_tag=run_7_bad tensor=7x7 cpu_seed_nonce=19"))
z = fflpt_expect("event is exactly one line", event.ends_with?("\n") && event.slice(0, event.size() - 1).include?("\n") == false)

short = i64[2]
z = fflpt_expect("short record rejected", fflp_set(short, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16) == 0)
z = fflpt_expect("short status fails closed", fflp_status_fields(short, "unsafe value", "unsafe strategy") == " best_source_kind=unknown best_source=unknown best_strategy=unknown")

<< "best provenance: ok"
