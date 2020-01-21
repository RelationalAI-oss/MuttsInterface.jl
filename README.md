# Mutts.jl

Mutable Until Shared data structures.

`Mutts.jl` provides infrastructure for building versioned data structures that follow the
_mutable-until-shared discipline_, providing all the benefits of purely-functional data
structures (worry-free, lock-free, super fast concurrency), with the pragmatic programming
and performance benefits of mutable data.

The `@mutt` keyword marks a struct as being _mutable until shared_, meaning that it
**_starts out_ mutable, until it is branched-from or manually marked immutable**, after
which it is permanently immutable. This gurantees concurrency-friendly immutable data, while
still allowing in-place construction of complex objects.
```julia
julia> @mutt struct S
           x::Int
       end

julia> Base.copy(rhs::S) = S(rhs.x)

julia> s = S(2)
S(true, 2)

julia> s.x = 3
3

julia> s2 = branch!(s)
S(true, 3)

julia> s
S(false, 3)

julia> s.x = 4
ERROR: AssertionError: ismutable(obj)
```
