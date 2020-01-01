module MuttsTest

using Mutts
using Test
using MacroTools

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

Base.copy(v :: Foo) = Foo(v.x, v.y)
g = branch!(f)
@assert !ismutable(f)
@assert ismutable(g)
markimmutable!(g)

@assert !ismutable(g)


mutable struct Bar <: Mutt
    f :: Foo
    z :: Float64
    __mutt_mutable :: Bool
end

Bar(f :: Foo, z :: Float64) = Bar(f, z, true)
Bar(b :: Bar) = Bar(f, z)



# -- Custom Constructors -------------------

# mutable struct __Inner_Baz
#     x :: Int
#     v :: Vector{Int}
#     #__Inner_Baz(x, v=[]) = new(x,v)
# end
# mutable struct Baz <: Mutt
#     _fields :: __Inner_Baz
#     __mutt_mutable :: Bool
#     Baz(x, v=[]) = new(__Inner_Baz(x,v), true)
# end
#
# Baz(2)
#
# Base.getproperty(x::Baz, f::Symbol) = getproperty(getfield(x,:_fields), f)
# Base.setproperty!(x::Baz, f::Symbol, v) = setproperty!(getfield(x,:_fields), f, v)
#
# Baz(2)._fields

# -----------------------------

# Mutts macro expansion

@testset "macro parsing" begin
    @test @macroexpand(@mutt struct S end) isa Expr
    @test @macroexpand(@mutt struct S x end) isa Expr

    # Bad parses
    @test_throws Exception @macroexpand(@mutt 1)
    @test_throws Exception @macroexpand(@mutt begin
        struct A
        end
        struct B
        end
    end)
end

@testset "Inner constructors" begin
    # (eval required to create structs inside a Testset)
    @eval begin
        # Test Inner Constructors
        @mutt struct SimpleFields
            x
            y
        end
        @mutt struct NoCustomInner
            x :: Int
            y
        end
        @mutt struct WithCustomInners
            x :: Int
            y
            WithCustomInners(x, y=2) = new(x,y)
        end
        function make end
        @mutt struct WithInnerFunctions
            x :: Int
            y
            WithInnerFunctions(x, y=2) = new(x,y)
            # Custom inner function
            @__MODULE__().make() = new(1,2)
        end
    end
    @eval begin
        @test ismutable(SimpleFields(1,2))
        @test ismutable(NoCustomInner(1,2))
        @test ismutable(WithCustomInners(1,2))
        @test ismutable(WithCustomInners(1))
        @test ismutable(WithInnerFunctions(1))
        @test ismutable(make())
    end
end

end
