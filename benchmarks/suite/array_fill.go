package main
import ("fmt";"time")
func main(){
  t0:=time.Now()
  var n int64=1000000; var rounds int64=200
  a:=make([]int64,n); var chk int64=0
  for r:=int64(0);r<rounds;r++{
    for i:=int64(0);i<n;i++{ a[i]=i*2654435761+r }
    chk^=a[(r*7)%n]
  }
  el:=time.Since(t0).Seconds()
  fmt.Println(chk); fmt.Printf("elapsed: %.6fs\n",el)
}
