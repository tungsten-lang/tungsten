# core/web — W3C / WHATWG / IETF Web Standards umbrella module.
#
# Re-exports:
#   - core/web/xml         (XML 1.0 + Namespaces, XLink, XInclude, XPointer, XPath 3.1, XQuery 3.1, XSLT 2.0/3.0)
#   - core/web/cbor        (CBOR RFC 8949 + COSE_Sign1 / COSE_Mac0 RFC 9052/9053)
#   - core/web/jose        (JWS/JWT/JWE RFC 7515-7519, DIDs, VC Data Model 1.1/2.0, Data Integrity, Bitstring Status, RDFC-1.0, JSON-LD, PMI)
#   - core/web/social_web  (W3C Trace Context, ActivityPub/AS2, WebSub/WebMention/Micropub/LDN, RDFa, TTML, PNG v2/v3, EPUB 3)

use core/web/xml
use core/web/cbor
use core/web/jose
use core/web/social_web
