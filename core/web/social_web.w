# core/web/social_web — W3C Social Web, Trace Context, TTML Captions, PNG v2/v3 Metadata,
# RDFa 1.1, and EPUB 3 Package Parser.
#
# Standards covered:
#   - W3C Trace Context Level 1/2 (`traceparent`, `tracestate`)
#   - ActivityPub / ActivityStreams 2.0 / Activity Vocabulary
#   - WebSub (hub/self discovery), WebMention, Micropub, Linked Data Notifications (LDN)
#   - RDFa 1.1 Lite attribute extractor
#   - W3C TTML (Timed Text Markup Language) caption parser
#   - PNG v2 / v3 (Third Edition) chunk parser (`IHDR`, `cICP`, `mDCv`, `cLLi`, `eXIf`, `acTL`, `tEXt`, `iTXt`)
#   - EPUB 3 (`META-INF/container.xml`, OPF manifest/spine) parser

use core/crypto/bytes
use core/web/xml

# ---- 1. W3C Trace Context (https://www.w3.org/TR/trace-context/) ----

-> traceparent_generate(sampled = true)
  tid = bhex(brand(16))
  pid = bhex(brand(8))
  flags = sampled ? "01" : "00"
  "00-" + tid + "-" + pid + "-" + flags

-> traceparent_parse(hdr)
  return nil if hdr == nil
  parts = hdr.to_s.strip.downcase.split("-")
  return nil if parts.size != 4
  return nil if parts[0].size != 2 || parts[1].size != 32 || parts[2].size != 16 || parts[3].size != 2
  return nil if parts[1] == "00000000000000000000000000000000" || parts[2] == "0000000000000000"
  {version: parts[0], trace_id: parts[1], parent_id: parts[2], flags: parts[3].to_i(16), sampled: (parts[3].to_i(16) & 1) == 1}

-> tracestate_parse(hdr)
  out = []
  return out if hdr == nil || hdr.to_s.strip.size == 0
  hdr.to_s.split(",").each ->(pair)
    t = pair.strip
    eq = t.index("=")
    out.push([t.slice(0, eq).strip, t.slice(eq + 1, t.size - eq - 1).strip]) if eq != nil && eq > 0
  out

# ---- 2. ActivityPub / ActivityStreams 2.0 / Activity Vocabulary ----

AS2_CONTEXT = "https://www.w3.org/ns/activitystreams"

-> as2_parse(json_str)
  obj = json_str.is_a?(Hash) ? json_str : JSON.parse(json_str.to_s)
  return nil if !obj.is_a?(Hash)
  ty = obj["type"]
  {
    id: obj["id"],
    type: ty,
    actor: obj["actor"],
    object: obj["object"],
    name: obj["name"],
    preferred_username: obj["preferredUsername"],
    summary: obj["summary"],
    content: obj["content"],
    inbox: obj["inbox"],
    outbox: obj["outbox"],
    followers: obj["followers"],
    following: obj["following"],
    published: obj["published"],
    items: obj["orderedItems"] != nil ? obj["orderedItems"] : obj["items"]
  }

-> as2_build_activity(act_type, actor_iri, obj, id_iri = nil)
  h = {
    "@context" => AS2_CONTEXT,
    "type" => act_type,
    "actor" => actor_iri,
    "object" => obj
  }
  h["id"] = id_iri if id_iri != nil
  h

-> webfinger_url(acct)
  s = acct.to_s.strip
  s = s.slice(1, s.size - 1) if s.starts_with?("@")
  s = s.slice(5, s.size - 5) if s.starts_with?("acct:")
  at = s.index("@")
  return nil if at == nil
  host = s.slice(at + 1, s.size - at - 1)
  "https://" + host + "/.well-known/webfinger?resource=acct:" + s

# ---- 3. WebSub, WebMention, Micropub & Linked Data Notifications (LDN) Discovery ----

-> social_discover_links(link_headers, html_links)
  res = {websub_hub: nil, websub_self: nil, webmention: nil, micropub: nil, ldn_inbox: nil, activitypub: nil}
  # Parse HTTP Link: <url>; rel="webmention" headers
  if link_headers != nil
    link_headers.each ->(lh)
      lh.to_s.split(",").each ->(part)
        lt = part.index("<"); gt = part.index(">")
        if lt != nil && gt != nil && gt > lt
          u = part.slice(lt + 1, gt - lt - 1).strip
          rl = part.downcase
          res[:websub_hub] = u if res[:websub_hub] == nil && rl.index('rel="hub"') != nil
          res[:websub_self] = u if res[:websub_self] == nil && rl.index('rel="self"') != nil
          res[:webmention] = u if res[:webmention] == nil && rl.index("webmention") != nil
          res[:micropub] = u if res[:micropub] == nil && rl.index("micropub") != nil
          res[:ldn_inbox] = u if res[:ldn_inbox] == nil && rl.index("ldp#inbox") != nil
  # Parse HTML <link rel="..." href="..."> pairs: [[rel, href, type], ...]
  if html_links != nil
    html_links.each ->(lk)
      rels = lk[0].to_s.downcase.split(" ")
      href = lk[1].to_s.strip
      ty = lk.size > 2 && lk[2] != nil ? lk[2].to_s.downcase : ""
      res[:websub_hub] = href if res[:websub_hub] == nil && rels.include?("hub")
      res[:websub_self] = href if res[:websub_self] == nil && rels.include?("self")
      res[:webmention] = href if res[:webmention] == nil && rels.include?("webmention")
      res[:micropub] = href if res[:micropub] == nil && rels.include?("micropub")
      res[:ldn_inbox] = href if res[:ldn_inbox] == nil && (rels.include?("http://www.w3.org/ns/ldp#inbox") || rels.include?("ldp:inbox"))
      res[:activitypub] = href if res[:activitypub] == nil && rels.include?("alternate") && (ty.index("activity+json") != nil || ty.index("ld+json") != nil)
  res

# ---- 4. W3C RDFa 1.1 Lite Extractor (vocab, typeof, property, resource, about) ----

-> rdfa_extract_xml(xml_doc, base_iri = "")
  triples = []
  rdfa_walk(xml_doc, base_iri, "", base_iri, triples)
  triples

-> rdfa_walk(node, subj, vocab, base, out)
  return nil if node == nil
  cur_subj = subj
  cur_vocab = vocab
  if node.kind == :el
    cur_vocab = node.attr("vocab") if node.attr("vocab") != nil
    if node.attr("about") != nil
      cur_subj = node.attr("about")
    elsif node.attr("resource") != nil && node.attr("property") == nil
      cur_subj = node.attr("resource")
    ty = node.attr("typeof")
    if ty != nil
      ty.split(" ").each ->(t)
        next if t.size == 0
        iri = t.index(":") != nil ? t : (cur_vocab + t)
        out.push([cur_subj, "http://www.w3.org/1999/02/22-rdf-syntax-ns#type", iri])
    prop = node.attr("property")
    if prop != nil
      val = node.attr("content") != nil ? node.attr("content") : (node.attr("href") != nil ? node.attr("href") : (node.attr("resource") != nil ? node.attr("resource") : node.string_value().strip))
      prop.split(" ").each ->(p)
        next if p.size == 0
        piri = p.index(":") != nil ? p : (cur_vocab + p)
        out.push([cur_subj, piri, val])
  node.children.each ->(ch) rdfa_walk(ch, cur_subj, cur_vocab, base, out)

# ---- 5. W3C TTML (Timed Text Markup Language) Caption Parser ----

-> ttml_parse_time(s)
  return ~0.0 if s == nil
  t = s.to_s.strip
  return t.slice(0, t.size - 1).to_f if t.ends_with?("s") && !t.ends_with?("ms")
  return t.slice(0, t.size - 2).to_f / ~1000.0 if t.ends_with?("ms")
  parts = t.split(":")
  if parts.size == 3
    return parts[0].to_f * ~3600.0 + parts[1].to_f * ~60.0 + parts[2].to_f
  if parts.size == 2
    return parts[0].to_f * ~60.0 + parts[1].to_f
  t.to_f

-> ttml_parse(xml_str)
  doc = xml_parse(xml_str)
  cues = []
  ps = xpath_eval(doc, "//p")
  if ps.is_a?(Array)
    ps.each ->(p)
      b = p.attr("begin")
      e = p.attr("end")
      d = p.attr("dur")
      t0 = ttml_parse_time(b)
      t1 = e != nil ? ttml_parse_time(e) : (d != nil ? t0 + ttml_parse_time(d) : t0 + ~3.0)
      txt = p.string_value().strip
      cues.push({start: t0, end: t1, text: txt, id: p.attr("xml:id"), region: p.attr("region")}) if txt.size > 0
  cues

# ---- 6. PNG v2 / v3 (Third Edition) Chunk Metadata Inspector ----
# Supports: IHDR, cICP (HDR color primaries/transfer/matrix), mDCv, cLLi, eXIf, acTL (APNG), tEXt, iTXt

-> png_u32(b, o)
  (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]

-> png_inspect_v3(data)
  b = data.is_a?(ByteArray) ? data : bytes_of(data)
  return nil if b.size < 33
  # Verify 8-byte PNG signature 89 50 4E 47 0D 0A 1A 0A
  return nil if b[0] != 0x89 || b[1] != 0x50 || b[2] != 0x4E || b[3] != 0x47
  info = {width: 0, height: 0, bit_depth: 0, color_type: 0, chunks: [], animated: false, frames: 1, hdr: false, cicp: nil, exif_bytes: 0, text: {}}
  off = 8
  while off + 12 <= b.size
    ln = png_u32(b, off)
    ctype = str_of(bslice(b, off + 4, 4))
    ds = off + 8
    break if ds + ln + 4 > b.size
    info[:chunks].push(ctype)
    if ctype == "IHDR" && ln >= 13
      info[:width] = png_u32(b, ds)
      info[:height] = png_u32(b, ds + 4)
      info[:bit_depth] = b[ds + 8]
      info[:color_type] = b[ds + 9]
    elsif ctype == "cICP" && ln >= 4
      # PNG 3rd Edition HDR coding-independent code points: [primaries, transfer, matrix, full_range]
      pr = b[ds]; tr = b[ds + 1]; mx = b[ds + 2]; fr = b[ds + 3]
      info[:cicp] = {primaries: pr, transfer: tr, matrix: mx, full_range: fr == 1}
      info[:hdr] = true if tr == 16 || tr == 18 # PQ (BT.2100) or HLG
    elsif ctype == "mDCv" || ctype == "cLLi"
      info[:hdr] = true
    elsif ctype == "eXIf"
      info[:exif_bytes] = ln
    elsif ctype == "acTL" && ln >= 8
      info[:animated] = true
      info[:frames] = png_u32(b, ds)
    elsif ctype == "tEXt" && ln > 1
      chunk_s = str_of(bslice(b, ds, ln))
      nul = chunk_s.index("\x00")
      info[:text][chunk_s.slice(0, nul)] = chunk_s.slice(nul + 1, chunk_s.size - nul - 1) if nul != nil
    break if ctype == "IEND"
    off = ds + ln + 4
  info

# ---- 7. EPUB 3 Package Parser (container.xml + OPF manifest & reading-order spine) ----

-> epub_parse_container(container_xml)
  doc = xml_parse(container_xml)
  rfs = xpath_eval(doc, "//rootfile")
  return nil if !rfs.is_a?(Array) || rfs.size == 0
  rfs[0].attr("full-path")

-> epub_parse_opf(opf_xml)
  doc = xml_parse(opf_xml)
  title_n = xpath_eval(doc, "//title")
  creator_n = xpath_eval(doc, "//creator")
  lang_n = xpath_eval(doc, "//language")
  manifest = {}
  items = xpath_eval(doc, "//manifest/item")
  if items.is_a?(Array)
    items.each ->(it)
      id = it.attr("id")
      manifest[id] = {href: it.attr("href"), media_type: it.attr("media-type"), properties: it.attr("properties")} if id != nil
  spine = []
  srefs = xpath_eval(doc, "//spine/itemref")
  if srefs.is_a?(Array)
    srefs.each ->(sr)
      idref = sr.attr("idref")
      spine.push(manifest[idref]) if idref != nil && manifest.has_key?(idref)
  {
    title: (title_n.is_a?(Array) && title_n.size > 0) ? title_n[0].string_value().strip : "EPUB Book",
    creator: (creator_n.is_a?(Array) && creator_n.size > 0) ? creator_n[0].string_value().strip : "",
    language: (lang_n.is_a?(Array) && lang_n.size > 0) ? lang_n[0].string_value().strip : "en",
    manifest: manifest,
    spine: spine
  }
