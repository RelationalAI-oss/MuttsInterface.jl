"""
    module Mutts
Explorations of a mutable-until-shared discipline in Julia. (MUTable 'Til Shared)
"""
module Mutts

import MacroTools: postwalk, @capture

#=
Notes

- Constructors
    - Need to initialize __mutt_mutable
    - Easiest if we provide a default fallback constructor
    - But then... I guess inner constructors can't be supported?
- TODO(NHDaly): Maybe we can fix this by creating a secret inner type, and storing it in the
  outer type, but preventing anyone from accessing it (since we have overloaded
  getproperty)? ... i dunno, it seems a bit excessive.
    - Hmm, yeah that seems like overkill, and like it would have all sorts of bad
      consequences.
    - Maybe a better approach would be to intercept the inner constructors in the macro
      and add the boolean to them? Maybe that's not terrible. Lemme try that!


TODO

- Need some mechanism to ensure that Mutt types can't be shared
  outside the current Task without being marked immutable.
    - Perhaps by injecting a check into `put!(::Channel, ::Mutt)`,
      or by dasserting in setters if the current task has changed.
- Add special casing for empty structs? They are always immutable so don't need the bool..
- Add check (warning or error?) that all fields of Mutts type must also be either Mutts or
  immutable.
=#

export Mutt, @mutt, branch!, ismutable, markimmutable!, getmutableversion

"""
    abstract type Mutt end
Types created via `@mutt`. This means they implement the _mutable-until-shared_ discipline.
"""
abstract type Mutt end

function mutt(expr)
    if @capture(expr, struct T_ fields__ end)
       :(mutable struct $T <: Mutt
            # Put our inserted variable first so the user's constructor can leave
            # undefined fields if that's a thing they're into.
            __mutt_mutable :: Bool
            $(fields...)
        end)
   else
       throw(ArgumentError("@mutt macro must be called with a struct definition: @mutt struct S ... end"))
   end
end

"""
    @mutt struct MyType
        fields...
    end

Macro to define a _mutable-until-shared_ data type. Mutable-until-shared types
are essentially immutable data structures, that give the flexibility of mutating
them until they are "finished", at which point they are free to be shared with
other Tasks, or other parts of the code.

`Mutt` types act like mutable structs, until the user calls `markimmutable!(obj)`,
after which they act like purely immutable types.

The complete API includes:
 - [`markimmutable!(obj)`](@ref): Freeze `obj`, preventing any future mutations.
 - [`branch!(obj)`](@ref): Make a _mutable_ shallow copy of `obj`.
 - [`getmutableversion(obj)`](@ref): Return a mutable version of `obj`, either
   `obj` itself if already mutable, or a [`branch!`ed](@ref branch!) copy.
 - [`branchactions(obj::Mutt)`](@ref): Users can override this callback for their
   type with any actions that need to occur when it is branched.
"""
macro mutt(expr)
    return mutt(expr)
end

ismutable(obj :: Mutt) = obj.__mutt_mutable
Base.isimmutable(obj :: Mutt) = !ismutable(obj)

function getmutableversion(obj :: Mutt)
    ismutable(obj) ? obj : branch!(obj)
end

branchactions(obj :: Mutt) = nothing

"""
    markimmutable!(obj::Mutt)

Freeeze `obj` from further mutations, making it eligible to pass to
other Tasks, branch! from it, or otherwise share it.
"""
function markimmutable! end

markimmutable!(a) = nothing

@generated function markimmutable!(obj :: T) where {T <: Mutt}
    as = map(fieldnames(T)) do sym
        :( markimmutable!(getfield(obj, $(QuoteNode(sym)))) )
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

function Base.setproperty!(obj::Mutt, name::Symbol, x)
    @assert ismutable(obj)
    setfield!(obj, name, x)
end

"""
    branch!(obj::Mutt)

Return a mutable shallow copy of `obj`, whose children are all still immutable.
"""
function branch!(obj :: Mutt)
    branchactions(obj)
    markimmutable!(obj)

    obj = copy(obj)
    obj.__mutt_mutable = true
    obj
end

end # module
