module MuttsTest

using Mutts
using Test
using MacroTools

#mutable struct Foo <: Mutt
#    x :: Int
#    y :: Int
#    __mutt_mutable :: Bool
#end
#
#Foo(x :: Int, y :: Int) = Foo(x, y, true)
#Foo(f :: Foo) = Foo(f.x, f.y)
#
#f = Foo(3,5)
#@assert is_mutts_mutable(f)
#f.x = 4
#
#Base.copy(v :: Foo) = Foo(v.x, v.y)
#g = branch!(f)
#@assert !is_mutts_mutable(f)
#@assert is_mutts_mutable(g)
#mark_immutable!(g)
#
#@assert !is_mutts_mutable(g)


#mutable struct Bar <: Mutt
#    f :: Foo
#    z :: Float64
#    __mutt_mutable :: Bool
#end
#
#Bar(f :: Foo, z :: Float64) = Bar(f, z, true)
#Bar(b :: Bar) = Bar(f, z)
#
#

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
@testset "Simple Macro Usage" begin
    @eval begin
        @mutt struct S
            x
        end
        s = S(1)
        @test is_mutts_mutable(s)
        mark_immutable!(s)
        @test !is_mutts_mutable(s)
        import Mutts.make_mutable_copy
        Mutts.make_mutable_copy(s::S) = S(s.x)

        s = S(1)
        @test is_mutts_mutable(branch!(s))
        @test !is_mutts_mutable(s)

        # Assignment from mark_immutable! (PR #4)
        s1 = mark_immutable!(s)
        @test s1 == s
    end
end

@mutt struct M
    x
end
@testset "Can't modify immutable Mutts" begin
    m = M(1)
    m.x = 2
    @test m.x == 2
    mark_immutable!(m)
    @test_throws Exception m.x = 3
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
            # keyword arguments constructor
            WithInnerFunctions(; x=1, y=2) = new(x,y)
            # Custom inner function
            @__MODULE__().make() = new(1,2)
        end
        @mutt struct DefaultsWithTypeParams{A,B}
            x :: A
            y :: B
        end
        @mutt struct CustomWithTypeParams{A,B}
            x :: A
            y :: B
            CustomWithTypeParams() = new{Int,Int}(1,2)
            CustomWithTypeParams{A,B}(x,y) where {A,B} = new{A,B}(x,y)
        end
    end
    @eval begin
        @test is_mutts_mutable(SimpleFields(1,2))
        @test is_mutts_mutable(NoCustomInner(1,2))
        @test is_mutts_mutable(WithCustomInners(1,2))
        @test is_mutts_mutable(WithCustomInners(1))

        @test is_mutts_mutable(WithInnerFunctions(1))
        @test is_mutts_mutable(WithInnerFunctions(y=1))
        @test is_mutts_mutable(make())

        @test is_mutts_mutable(DefaultsWithTypeParams{Int,String}(1,""))
        @test is_mutts_mutable(CustomWithTypeParams())
        @test is_mutts_mutable(CustomWithTypeParams{Int,String}(1,""))
    end
end

@testset "structs with supertypes" begin
    @eval begin
        @mutt struct MuttsFloat <: AbstractFloat
            v :: Float64
        end
        @test MuttsFloat <: AbstractFloat
        v = MuttsFloat(2.0)
        @test v isa AbstractFloat

        v.v = 3.0
        @test v.v == 3.0
        mark_immutable!(v)
        @test_throws Exception v.v = 4.0
    end
end

end
