package main
import ("fmt"; "time")
func main(){ var n int64=20000000; f:=0.5; t0:=time.Now()
 for i:=int64(0);i<n;i++{ f=3.9*f*(1.0-f) }
 fmt.Printf("%.10f\nops: %d\nelapsed: %.6fs\n",f,n,time.Since(t0).Seconds()) }
