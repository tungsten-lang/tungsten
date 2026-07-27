package main
import ("fmt"; "time"; "os")
// Sequential element read over a fixed [1024] array, nested reps times. `tab[k]+r`
// varies each outer pass so the reduction can't be shortcut; reps is read via a
// side effect (len of args) so the compiler can't fold. Mirrors array_get.w.
func main(){ reps:=int64(976562)+int64(len(os.Args))-1; var tab [1024]int64
 for j:=0;j<1024;j++{ tab[j]=int64(j)*2654435761+reps }
 t0:=time.Now()
 chk:=reps
 for r:=int64(0);r<reps;r++{ for k:=0;k<1024;k++{ chk^=tab[k]+r } }
 ops:=reps*1024
 fmt.Printf("%d\nops: %d\nelapsed: %.6fs\n",chk,ops,time.Since(t0).Seconds()) }
