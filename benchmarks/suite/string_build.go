package main
import ("fmt";"strings";"time")
func main(){ t0:=time.Now(); n:=400000; var sb strings.Builder
  for i:=0;i<n;i++{ sb.WriteString("abcdefghijklmnopqrstuvwxyz") }
  el:=time.Since(t0).Seconds(); fmt.Println(sb.Len()); fmt.Printf("elapsed: %.6fs\n",el) }
