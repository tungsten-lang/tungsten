program levenshtein_bench
  implicit none
  character(len=:), allocatable :: s, t
  integer :: d

  s = repeat("the quick brown fox jumps over the lazy dog", 20)
  t = repeat("the slow brown fox leaps over the lazy cat", 20)
  d = levenshtein(s, t)
  print '(I0)', d

contains

  function levenshtein(s, t) result(dist)
    character(len=*), intent(in) :: s, t
    integer :: dist
    integer :: m, n, i, j, cost, ins, del, sub, best
    integer, allocatable :: prev(:), curr(:), tmp(:)

    m = len(s); n = len(t)
    if (m == 0) then
      dist = n; return
    end if
    if (n == 0) then
      dist = m; return
    end if

    allocate(prev(0:n), curr(0:n))
    do j = 0, n
      prev(j) = j
    end do

    do i = 1, m
      curr(0) = i
      do j = 1, n
        if (s(i:i) == t(j:j)) then
          cost = 0
        else
          cost = 1
        end if
        ins  = curr(j - 1) + 1
        del  = prev(j) + 1
        sub  = prev(j - 1) + cost
        best = min(ins, del, sub)
        curr(j) = best
      end do
      tmp = prev; prev = curr; curr = tmp
    end do

    dist = prev(n)
    deallocate(prev, curr)
  end function levenshtein

end program levenshtein_bench
