"""
   module Mutts
Explorations of a mutable-until-shared discipline in Julia.
"""
module Mutts

import MacroTools: postwalk, @capture

#=
Notes

- Constructors
    - Need to initialize __mutt_mutable
    - Easiest if we provide a default fallback constructor
    - But then... I guess inner constructors can't be supported?

TODO

- Need some mechanism to ensure that Mutt types can't be shared
  outside the current Task without being marked immutable.
    - Perhaps by injecting a check into `put!(::Channel, ::Mutt)`,
      or by dasserting in setters if the current task has changed.
=#

export Mutt, @mutt, branch, ismutable, markimmutable, getmutableversion

"""
    abstract type Mutt end
Types created via `@mutt`. This means they implement the _mutable-until-shared_ discipline.
"""
abstract type Mutt end

function mutt(expr)
    function sub(ex)
        if @capture(ex, struct T_ fields__ end)
           :( mutable struct $T <: Mutt
                   $(fields...)
                   __mutt_mutable :: Bool
               end
           )
       else
           ex
       end
    end
    postwalk(sub, expr)
end

"""
    @mutt struct MyType
        fields
    end

Macro to define a _mutable-until-shared_ data type. Mutable-until-shared types
are essentially immutable data structures, that give the flexibility of mutating
them until they are "finished", at which point they are free to be shared with
other Tasks, or other parts of the code.

`Mutt` types act like mutable structs, until the user calls `markimmutable(obj)`,
after which they act like purely immutable types.

The complete API includes:
 - [`markimmutable(obj)`](@ref): Freeze `obj`, preventing any future mutations. 
 - [`branch(obj)`](@ref): Make a _mutable_ shallow copy of `obj`.
 - [`getmutableversion(obj)`](@ref): Return a mutable version of `obj`, either
   `obj` itself if already mutable, or a [`branch`ed](@ref branch) copy.
 - [`branchactions(obj::Mutt)`](@ref): Users can override this callback for their
   type with any actions that need to occur when it is branched.
"""
macro mutt(expr)
    return mutt(expr)
end

ismutable(obj :: Mutt) = obj.__mutt_mutable

function getmutableversion(obj :: Mutt)
    ismutable(obj) ? obj : branch(obj)
end

branchactions(obj :: Mutt) = nothing

"""
    markimmutable(obj::Mutt)

Freeeze `obj` from further mutations, making it eligible to pass to
other Tasks, branch from it, or otherwise share it.
"""
markimmutable(a) = nothing

@generated function markimmutable(obj :: T) where {T <: Mutt}
    as = map(fieldnames(T)) do sym
        :( markimmutable(getfield(obj, $(QuoteNode(sym)))) )
    end

    return quote
        if ismutable(obj)
            # Mark all Mutt fields immutable
            $(as...)

            # Then mark this object immutable
            obj.__mutt_mutable = false
        end
        nothing
    end
end

function setproperty!(obj::Mutt, name::Symbol, x)
    @assert name == :__mutt_mutable || ismutable(obj)
    setfield!(obj, name, x)
end

"""
    branch(obj::Mutt)

Return a mutable shallow copy of `obj`, whose children are all still immutable.
"""
function branch(obj :: Mutt)
    branchactions(obj)
    markimmutable(obj)

    obj = copy(obj)
    obj.__mutt_mutable = true
    obj
end

end # module
