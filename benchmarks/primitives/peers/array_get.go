package main
import ("fmt"; "time")
func main(){ var n,chk int64=300000000,0; var tab [1024]int64
 for j:=0;j<1024;j++{ tab[j]=int64(j)*2654435761 }
 t0:=time.Now()
 for i:=int64(0);i<n;i++{ chk^=tab[i&1023] }
 fmt.Printf("%d\nops: %d\nelapsed: %.6fs\n",chk,n,time.Since(t0).Seconds()) }
