// Narrow macOS ImageIO/CoreGraphics operations for the Tungsten label program.
// All selection, thresholding, rotation and page geometry decisions live in .w.
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static CGImageRef image_at(const char *path) {
  CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path, strlen(path), false);
  if (!url) return NULL;
  CGImageSourceRef source = CGImageSourceCreateWithURL(url, NULL);
  CFRelease(url);
  if (!source) return NULL;
  CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
  CFRelease(source);
  return image;
}
static int info(const char *path, const char *output) {
  CGImageRef image = image_at(path); if (!image) return 1;
  FILE *f = fopen(output, "w"); int ok = f && fprintf(f, "%zu %zu\n", CGImageGetWidth(image), CGImageGetHeight(image)) > 0;
  if (f && fclose(f)) ok = 0;
  CGImageRelease(image); return ok ? 0 : 1;
}
static int gray(const char *path, const char *raw) {
  CGImageRef image = image_at(path); if (!image) return 1;
  size_t w = CGImageGetWidth(image), h = CGImageGetHeight(image);
  CGColorSpaceRef color = CGColorSpaceCreateDeviceGray();
  CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, w, color, kCGImageAlphaNone);
  CGColorSpaceRelease(color);
  if (!ctx) { CGImageRelease(image); return 1; }
  CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
  CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), image);
  FILE *f = fopen(raw, "wb"); int ok = f && fwrite(CGBitmapContextGetData(ctx), 1, w*h, f) == w*h;
  if (f && fclose(f)) ok = 0;
  CGContextRelease(ctx); CGImageRelease(image); return ok ? 0 : 1;
}
static int pdf(int argc, char **argv) {
  // pdf IMAGE RAW_OR_DASH OUTPUT PAGE_W PAGE_H DRAW_W DRAW_H TX TY [CROP_X CROP_Y CROP_W CROP_H]
  // The crop rectangle is in image pixels from the top-left corner.
  if (argc != 11 && argc != 15) return 1;
  CGImageRef image = image_at(argv[2]); if (!image) return 1;
  if (strcmp(argv[3], "-")) {
    size_t w = CGImageGetWidth(image), h = CGImageGetHeight(image);
    FILE *f = fopen(argv[3], "rb");
    if (!f) { CGImageRelease(image); return 1; }
    CGColorSpaceRef color = CGColorSpaceCreateDeviceGray();
    CGContextRef bitmap = CGBitmapContextCreate(NULL, w, h, 8, w, color, kCGImageAlphaNone);
    CGColorSpaceRelease(color);
    if (!bitmap) { fclose(f); CGImageRelease(image); return 1; }
    int ok = fread(CGBitmapContextGetData(bitmap), 1, w*h, f) == w*h && fgetc(f) == EOF;
    fclose(f);
    CGImageRef replacement = ok ? CGBitmapContextCreateImage(bitmap) : NULL;
    CGContextRelease(bitmap); CGImageRelease(image); image = replacement;
    if (!image) return 1;
  }
  if (argc == 15) {
    CGRect rect = CGRectMake(atof(argv[11]), atof(argv[12]), atof(argv[13]), atof(argv[14]));
    CGImageRef cropped = CGImageCreateWithImageInRect(image, rect);
    CGImageRelease(image); image = cropped;
    if (!image) return 1;
  }
  CGRect page = CGRectMake(0, 0, atof(argv[5]), atof(argv[6]));
  CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)argv[4], strlen(argv[4]), false);
  CGContextRef ctx = url ? CGPDFContextCreateWithURL(url, &page, NULL) : NULL;
  if (url) CFRelease(url);
  if (!ctx) { CGImageRelease(image); return 1; }
  CGPDFContextBeginPage(ctx, NULL);
  CGContextSetRGBFillColor(ctx, 1, 1, 1, 1); CGContextFillRect(ctx, page);
  CGContextTranslateCTM(ctx, atof(argv[9]), atof(argv[10]));
  CGContextRotateCTM(ctx, -1.5707963267948966);
  CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
  CGContextDrawImage(ctx, CGRectMake(0, 0, atof(argv[7]), atof(argv[8])), image);
  CGPDFContextEndPage(ctx); CGPDFContextClose(ctx);
  CGContextRelease(ctx); CGImageRelease(image); return 0;
}
int main(int argc, char **argv) {
  if (argc == 4 && !strcmp(argv[1], "info")) return info(argv[2], argv[3]);
  if (argc == 4 && !strcmp(argv[1], "gray")) return gray(argv[2], argv[3]);
  if (argc > 1 && !strcmp(argv[1], "pdf")) return pdf(argc, argv);
  fprintf(stderr, "image-native: invalid arguments\n"); return 2;
}
