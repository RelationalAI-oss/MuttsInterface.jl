module Test

using Mutts
using Test

mutable struct Foo <: Mutt
    x :: Int
    y :: Int
    __mutt_mutable :: Bool
end

Foo(x :: Int, y :: Int) = Foo(x, y, true)
Foo(f :: Foo) = Foo(f.x, f.y)

f = Foo(3,5)
@assert ismutable(f)
f.x = 4

g = branch(f)

@assert !ismutable(f)
@assert ismutable(g)

mutable struct Bar <: Mutt
    f :: Foo
    z :: Float64
    __mutt_mutable :: Bool
end

Bar(f :: Foo, z :: Float64) = Bar(f, z, true)
Bar(b :: Bar) = Bar(f, z)



end
