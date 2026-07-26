package main
import ("fmt"; "time")
func main(){ var n,s int64=300000000,1; t0:=time.Now()
 for i:=int64(0);i<n;i++{ s=s+(s^i) }
 fmt.Printf("%d\nops: %d\nelapsed: %.6fs\n",s,n,time.Since(t0).Seconds()) }
