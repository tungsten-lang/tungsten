// Standalone Metal regression gate; no model weights or Python dependencies.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <stdexcept>
#include <string>
#include <vector>

static id<MTLDevice> device;
static id<MTLCommandQueue> queue;
static void check(bool ok, const std::string &message) {
  if (!ok) throw std::runtime_error(message);
}
static id<MTLLibrary> library(const char *path, bool fast) {
  NSError *error = nil;
  NSString *source = [NSString stringWithContentsOfFile:@(path)
                            encoding:NSUTF8StringEncoding error:&error];
  check(source != nil, "read shader: " + std::string(path));
  MTLCompileOptions *options = [MTLCompileOptions new];
  options.fastMathEnabled = fast;
  id<MTLLibrary> lib = [device newLibraryWithSource:source options:options error:&error];
  check(lib != nil, "compile " + std::string(path) + ": " +
        (error ? std::string(error.localizedDescription.UTF8String) : ""));
  return lib;
}
static id<MTLComputePipelineState> pipeline(id<MTLLibrary> lib, const char *name) {
  NSError *error = nil;
  id<MTLFunction> fn = [lib newFunctionWithName:@(name)];
  check(fn != nil, "missing kernel: " + std::string(name));
  auto p = [device newComputePipelineStateWithFunction:fn error:&error];
  check(p != nil, "pipeline: " + std::string(name));
  check(p.threadExecutionWidth == 32, "these kernels require 32-lane SIMD groups");
  return p;
}
static id<MTLBuffer> buffer(size_t size) {
  auto b = [device newBufferWithLength:size options:MTLResourceStorageModeShared];
  check(b != nil, "buffer allocation failed");
  memset(b.contents, 0xcd, size);
  return b;
}
static double run(id<MTLComputePipelineState> p, NSArray<id<MTLBuffer>> *buffers,
                  unsigned groups, unsigned threads, int d=0, int streams=0,
                  int repeats=1) {
  auto command = [queue commandBuffer];
  auto encoder = [command computeCommandEncoder];
  [encoder setComputePipelineState:p];
  for (NSUInteger i = 0; i < buffers.count; ++i) [encoder setBuffer:buffers[i] offset:0 atIndex:i];
  if (d) {
    float eps = 1.e-6f;
    [encoder setBytes:&d length:sizeof(d) atIndex:3];
    [encoder setBytes:&streams length:sizeof(streams) atIndex:4];
    [encoder setBytes:&eps length:sizeof(eps) atIndex:5];
  }
  for (int r = 0; r < repeats; ++r)
    [encoder dispatchThreadgroups:MTLSizeMake(groups,1,1)
               threadsPerThreadgroup:MTLSizeMake(threads,1,1)];
  [encoder endEncoding];
  [command commit]; [command waitUntilCompleted];
  check(command.status == MTLCommandBufferStatusCompleted,
        command.error ? command.error.localizedDescription.UTF8String : "GPU command failed");
  return (command.GPUEndTime - command.GPUStartTime) * 1.e6 / repeats;
}
static void equal_bytes(id<MTLBuffer> a, id<MTLBuffer> b, size_t bytes,
                        const std::string &label) {
  auto x = (const uint32_t *)a.contents, y = (const uint32_t *)b.contents;
  for (size_t i = 0; i < bytes/4; ++i) {
    if (x[i] != y[i]) {
      fprintf(stderr, "%s mismatch at %zu: %08x != %08x\n", label.c_str(), i, x[i], y[i]);
      throw std::runtime_error(label + " is not bit exact");
    }
  }
}
static float random_value(uint32_t &state) {
  state = state * 1664525u + 1013904223u;
  return float(int(state >> 8) - 8388608) / 1048576.0f;
}
static double median(std::vector<double> x) {
  std::sort(x.begin(),x.end()); return (x[1]+x[2])/2;
}
static void print_samples(const std::vector<double> &reference, const std::vector<double> &candidate) {
  printf(",\"reference_samples_us\":[%.5f,%.5f,%.5f,%.5f],\"candidate_samples_us\":[%.5f,%.5f,%.5f,%.5f]}\n",
         reference[0],reference[1],reference[2],reference[3],candidate[0],candidate[1],candidate[2],candidate[3]);
}
static double run_qsa(id<MTLComputePipelineState> p, NSArray<id<MTLBuffer>> *buffers,
                      int rows, bool grouped) {
  auto command=[queue commandBuffer]; auto encoder=[command computeCommandEncoder];
  [encoder setComputePipelineState:p];
  for(NSUInteger i=0;i<buffers.count;++i) [encoder setBuffer:buffers[i] offset:0 atIndex:i];
  int gqa=12, heads=24, kv=512, stride=2051; float scale=1.f/16.f;
  [encoder setBytes:&gqa length:4 atIndex:6]; [encoder setBytes:&heads length:4 atIndex:7];
  [encoder setBytes:&kv length:4 atIndex:8]; [encoder setBytes:&scale length:4 atIndex:9];
  [encoder setBytes:&stride length:4 atIndex:10]; [encoder setBytes:&rows length:4 atIndex:11];
  [encoder dispatchThreadgroups:MTLSizeMake(rows*heads/(grouped?2:1),1,1)
             threadsPerThreadgroup:MTLSizeMake(256,1,1)];
  [encoder endEncoding]; [command commit]; [command waitUntilCompleted];
  check(command.status==MTLCommandBufferStatusCompleted,"QSA command failed");
  return (command.GPUEndTime-command.GPUStartTime)*1.e6;
}
static void benchmark(const char *kind, unsigned rows,
                      id<MTLComputePipelineState> ref, id<MTLComputePipelineState> cand,
                      NSArray<id<MTLBuffer>> *rb, NSArray<id<MTLBuffer>> *cb,
                      unsigned groups, unsigned ref_threads, int d=0, int streams=0, unsigned cand_threads=32) {
  std::vector<double> rt, ct;
  int repeats = rows <= 128 ? 64 : 8;
  for (int cycle=0; cycle<2; ++cycle) {
    rt.push_back(run(ref,rb,groups,ref_threads,d,streams,repeats));
    ct.push_back(run(cand,cb,groups,cand_threads,d,streams,repeats));
    ct.push_back(run(cand,cb,groups,cand_threads,d,streams,repeats));
    rt.push_back(run(ref,rb,groups,ref_threads,d,streams,repeats));
  }
  printf("{\"kind\":\"%s\",\"rows\":%u,\"reference_us\":%.5f,\"candidate_us\":%.5f,\"speedup\":%.5f,\"repeats_per_sample\":%d,\"reference_threads\":%u,\"candidate_threads\":%u,\"d\":%d,\"streams\":%d",
         kind,rows,median(rt),median(ct),median(rt)/median(ct),repeats,ref_threads,cand_threads,d,streams);
  print_samples(rt,ct);
}

int main() {
  @autoreleasepool {
    try {
      device = MTLCreateSystemDefaultDevice(); check(device != nil,"Metal device unavailable");
      queue = [device newCommandQueue];
      fprintf(stderr,"Metal device: %s\n",device.name.UTF8String);
      NSData *metadata = [NSJSONSerialization dataWithJSONObject:@{
        @"kind": @"environment", @"device": device.name,
        @"os": NSProcessInfo.processInfo.operatingSystemVersionString,
        @"compiler": @(__clang_version__), @"timed_fast_math": @YES,
        @"order": @"ABBA ABBA", @"scope": @"isolated kernels, warm data; not full-model throughput"
      } options:NSJSONWritingSortedKeys error:nil];
      fwrite(metadata.bytes,1,metadata.length,stdout); putchar('\n');
      size_t compared=0;
      for (bool fast : {false,true}) {
        auto old = library("bits/tungsten-llama/lib/kernels/qwen4_fn/fn_multi.metal",fast);
        auto router = library("bits/tungsten-llama/lib/kernels/qwen4_fn/router_softmax_topk10_warp.metal",fast);
        auto norm = library("bits/tungsten-llama/lib/kernels/qwen4_fn/grouped_rms_norm_warp.metal",fast);
        auto rr=pipeline(old,"router_softmax_topk10_multi"), rc=pipeline(router,"router_softmax_topk10_multi_warp");
        auto sr=pipeline(library("bits/tungsten-llama/lib/kernels/qwen4_fn/router_softmax_topk10.metal",fast),"router_softmax_topk10");
        auto sc=pipeline(router,"router_softmax_topk10_warp");
        auto nr=pipeline(old,"grouped_rms_norm_multi");
        std::vector<id<MTLComputePipelineState>> norms = {pipeline(norm,"grouped_rms_norm_multi_warp"), pipeline(norm,"grouped_rms_norm_multi_t64"), pipeline(norm,"grouped_rms_norm_multi_t128")};
        auto ar=pipeline(library("bits/tungsten-llama/lib/kernels/qwen4_fn/qsa.metal",fast),"qsa_sdpa_selected_par");
        auto ac=pipeline(library("bits/tungsten-llama/lib/kernels/qwen4_fn/qsa_selected_group2.metal",fast),"qsa_sdpa_selected_group2");
        for (int rows : {1,7,64,128,1024}) {
          @autoreleasepool {
            auto q=buffer(rows*24*256*4), k=buffer(4096*512*4), v=buffer(4096*512*4);
            auto a=buffer(q.length), b=buffer(q.length), sel=buffer(rows*2051*4), ns=buffer(rows*4);
            uint32_t state=rows+831;
            for (id<MTLBuffer> bf in @[q,k,v])
              for(size_t i=0;i<bf.length/4;++i) ((float *)bf.contents)[i]=random_value(state)*.125f;
            for(int t=0;t<rows;++t) for(int i=0;i<2051;++i) ((int *)sel.contents)[t*2051+i]=(i*37+t*11)%4096;
            for (int visible : {0,1,31,32,255,256,257,1024,2048,2051}) {
              for(int t=0;t<rows;++t) ((int *)ns.contents)[t]=std::max(0,visible-t%4);
              run_qsa(ar,@[q,k,v,a,sel,ns],rows,false); run_qsa(ac,@[q,k,v,b,sel,ns],rows,true);
              equal_bytes(a,b,q.length,"QSA rows="+std::to_string(rows)+" visible="+std::to_string(visible)+" fast="+std::to_string(fast));
              compared+=q.length;
              if(fast && (rows==64 || rows==128 || rows==1024) && (visible==256 || visible==2048)) {
                std::vector<double> rt,ct;
                for(int c=0;c<2;++c) {
                  rt.push_back(run_qsa(ar,@[q,k,v,a,sel,ns],rows,false));
                  ct.push_back(run_qsa(ac,@[q,k,v,b,sel,ns],rows,true));
                  ct.push_back(run_qsa(ac,@[q,k,v,b,sel,ns],rows,true));
                  rt.push_back(run_qsa(ar,@[q,k,v,a,sel,ns],rows,false));
                }
                printf("{\"kind\":\"qsa-group2\",\"rows\":%d,\"visible\":%d,\"reference_us\":%.5f,\"candidate_us\":%.5f,\"speedup\":%.5f,\"repeats_per_sample\":1",rows,visible,median(rt),median(ct),median(rt)/median(ct));
                print_samples(rt,ct);
              }
            }
          }
        }
        for (unsigned rows : {1u,2u,3u,7u,8u,9u,16u,32u,64u,128u,1024u}) {
          @autoreleasepool {
            auto x=buffer(rows*512*4), ri=buffer(rows*10*4), ci=buffer(rows*10*4);
            auto rw=buffer(rows*10*4), cw=buffer(rows*10*4);
            for (int pattern=0; pattern<6; ++pattern) {
              uint32_t state=1009u+rows*41u+pattern;
              auto values=(float *)x.contents;
              for (unsigned t=0;t<rows;++t) for (int i=0;i<512;++i) {
                float v=random_value(state);
                if (pattern==1) v=0;
                if (pattern==2) v=float((i*17+t)%19)-9;
                if (pattern==3) v=i==511 ? 1000.f : -1000.f;
                if (pattern==4) v=1.f+float(i%31)*0x1p-23f;
                if (pattern==5) v=(i%7==0) ? 0x1p120f : -0x1p120f;
                values[t*512+i]=v;
              }
              run(rr,@[x,ri,rw],rows,512); run(rc,@[x,ci,cw],rows,32);
              auto label=std::string("router rows=")+std::to_string(rows)+" pattern="+std::to_string(pattern)+" fast="+std::to_string(fast);
              equal_bytes(ri,ci,rows*10*4,label+" ids");
              equal_bytes(rw,cw,rows*10*4,label+" weights");
              compared+=rows*10*8;
              if (rows==1) {
                run(sr,@[x,ri,rw],1,512); run(sc,@[x,ci,cw],1,32);
                equal_bytes(ri,ci,40,label+" serial ids");
                equal_bytes(rw,cw,40,label+" serial weights");
                compared+=80;
              }
              if (fast && pattern==0 && (rows==1 || rows==8 || rows==32 || rows==128 || rows==1024))
                benchmark("router",rows,rr,rc,@[x,ri,rw],@[x,ci,cw],rows,512);
            }
            for (int d : {127,128,640,2560,10240}) {
              @autoreleasepool {
                int streams = d==10240 ? 1 : 4;
                size_t count=size_t(rows)*streams*d;
                auto input=buffer(count*4), weight=buffer(streams*d*4);
                auto a=buffer(count*4), b=buffer(count*4);
                uint32_t state=rows*173+d;
                for(size_t i=0;i<count;++i) ((float *)input.contents)[i]=random_value(state);
                for(int i=0;i<streams*d;++i) ((float *)weight.contents)[i]=1.f+random_value(state)*.05f;
                run(nr,@[input,weight,a],rows*streams,256,d,streams);
                for (unsigned nvariant=0;nvariant<norms.size();++nvariant) {
                auto nc=norms[nvariant]; unsigned nt=32u<<nvariant;
                run(nc,@[input,weight,b],rows*streams,nt,d,streams);
                equal_bytes(a,b,count*4,"norm rows="+std::to_string(rows)+" d="+std::to_string(d)+" fast="+std::to_string(fast));
                compared+=count*4;
                if(fast && d==2560 && (rows==1 || rows==8 || rows==32 || rows==128 || rows==1024))
                  benchmark(("norm-t"+std::to_string(nt)).c_str(),rows,nr,nc,@[input,weight,a],@[input,weight,b],rows*streams,256,d,streams,nt);
                }
              }
            }
          }
        }
      }
      printf("{\"passed\":true,\"compared_bytes\":%zu,\"fast_math_modes\":2}\n",compared);
    } catch (const std::exception &e) { fprintf(stderr,"FAIL: %s\n",e.what());return 1; }
  }
  return 0;
}
