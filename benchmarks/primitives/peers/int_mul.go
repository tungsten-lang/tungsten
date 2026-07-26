package main
import ("fmt"; "time")
func main(){ var n int64=300000000; var s uint64=1; t0:=time.Now()
 for i:=int64(0);i<n;i++{ s=s*6364136223846793005+1 }
 fmt.Printf("%d\nops: %d\nelapsed: %.6fs\n",s,n,time.Since(t0).Seconds()) }
