package main
import ("fmt"; "time")
func main(){ var n,chk int64=300000000,0; var tab [1024]int64; t0:=time.Now()
 for i:=int64(0);i<n;i++{ tab[i&1023]=i^chk; chk=chk+1 }
 fmt.Printf("%d\nops: %d\nelapsed: %.6fs\n",chk^tab[0],n,time.Since(t0).Seconds()) }
