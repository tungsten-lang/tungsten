package main
import ("fmt"; "time"; "os")
// Wraparound (masked-index) array read: `tab[i & 1023]` in a flat loop. The
// argv-derived n keeps the trip count runtime-unknown. Mirrors array_mod.w.
func main(){ n:=int64(1000000000)+int64(len(os.Args))-1; var chk int64; var tab [1024]int64
 for j:=0;j<1024;j++{ tab[j]=int64(j)*2654435761 }
 t0:=time.Now()
 for i:=int64(0);i<n;i++{ chk^=tab[i&1023] }
 fmt.Printf("%d\nops: %d\nelapsed: %.6fs\n",chk,n,time.Since(t0).Seconds()) }
