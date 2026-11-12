// ippeveprinter hard-codes Normal in its legacy printer attributes. Override
// that one IPP default to High while leaving formats and all other attributes
// untouched. Loaded only by the AirPrint service; the Rollo queue is separate.
#include <cups/ipp.h>
#include <string.h>
static ipp_attribute_t *quality_default(ipp_t *ipp, ipp_tag_t group, ipp_tag_t tag, const char *name, int value) {
 if (group == IPP_TAG_PRINTER && tag == IPP_TAG_ENUM && name && !strcmp(name, "print-quality-default") && value == 4) value = 5;
 return ippAddInteger(ipp, group, tag, name, value);
}
__attribute__((used)) static struct { const void *replacement; const void *replacee; } interpose[] __attribute__((section("__DATA,__interpose"))) = {{(const void *)quality_default,(const void *)ippAddInteger}};
