object Levenshtein {
  def levenshtein(s: String, t: String): Int = {
    val m = s.length
    val n = t.length
    if (m == 0) return n
    if (n == 0) return m

    var prev = Array.range(0, n + 1)
    var curr = new Array[Int](n + 1)

    var i = 0
    while (i < m) {
      curr(0) = i + 1
      val sc = s.charAt(i)
      var j = 0
      while (j < n) {
        val cost = if (sc == t.charAt(j)) 0 else 1
        val ins  = curr(j) + 1
        val del  = prev(j + 1) + 1
        val sub  = prev(j) + cost
        var best = if (ins < del) ins else del
        if (sub < best) best = sub
        curr(j + 1) = best
        j += 1
      }
      val tmp = prev; prev = curr; curr = tmp
      i += 1
    }

    prev(n)
  }

  def main(args: Array[String]): Unit = {
    val s = "the quick brown fox jumps over the lazy dog" * 20
    val t = "the slow brown fox leaps over the lazy cat" * 20
    println(levenshtein(s, t))
  }
}
