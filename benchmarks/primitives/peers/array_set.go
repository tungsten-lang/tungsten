package main
import ("fmt"; "time"; "os")
// Sequential element write over a fixed [1024] array, nested reps times. The
// loop-carried chk + final read-back keep the stores alive; reps carries a side
// effect (len of args) so it can't be folded. Mirrors array_set.w.
func main(){ reps:=int64(976562)+int64(len(os.Args))-1; var tab [1024]int64
 t0:=time.Now()
 chk:=reps
 for r:=int64(0);r<reps;r++{ for k:=int64(0);k<1024;k++{ tab[k]=chk^k; chk=chk+1 } }
 out:=chk^tab[0]^tab[1023]
 ops:=reps*1024
 fmt.Printf("%d\nops: %d\nelapsed: %.6fs\n",out,ops,time.Since(t0).Seconds()) }
