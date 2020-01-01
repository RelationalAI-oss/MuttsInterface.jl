"""
    module Mutts
Explorations of a mutable-until-shared discipline in Julia. (MUTable 'Til Shared)
"""
module Mutts

import MacroTools
using MacroTools: postwalk, @capture

#=
Notes


TODO

- Need some mechanism to ensure that Mutt types can't be shared
  outside the current Task without being marked immutable.
    - Perhaps by injecting a check into `put!(::Channel, ::Mutt)`,
      or by dasserting in setters if the current task has changed.
- Add special casing for empty structs? They are always immutable so don't need the bool..
- Add check (warning or error?) that all fields of Mutts type must also be either Mutts or
  immutable.
=#

export Mutt, @mutt, branch!, ismutable, markimmutable!, getmutableversion!

"""
    abstract type Mutt end
Types created via `@mutt`. This means they implement the _mutable-until-shared_ discipline.
"""
abstract type Mutt end

ismutable(obj :: Mutt) = obj.__mutt_mutable
Base.isimmutable(obj :: Mutt) = !ismutable(obj)

function getmutableversion!(obj :: Mutt)
    ismutable(obj) ? obj : branch!(obj)
end

"""
    branchactions(obj :: Mutt) = nothing

This callback function is called immediately before a Mutt object is branched from (even if
it was already immutable). Users can add methods to this callback to perform arbitrary
actions right before an object is branched.
"""
branchactions(obj :: Mutt) = nothing

"""
    markimmutable!(obj::Mutt)

Freeeze `obj` from further mutations, making it eligible to pass to
other Tasks, branch! from it, or otherwise share it.
"""
function markimmutable! end

markimmutable!(a) = a

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
        obj
    end
end

# Override setproperty! to prevent mutating a Mutt once it's been marked immutable.
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
 - [`getmutableversion!(obj)`](@ref): Return a mutable version of `obj`, either
   `obj` itself if already mutable, or a [`branch!`ed](@ref branch!) copy.
 - [`branchactions(obj::Mutt)`](@ref): Users can override this callback for their
   type with any actions that need to occur when it is branched.

This macro modifies the definition of `S` to include an extra first parameter:
`__mutt_mutable :: Bool`, which tracks at runtime when the value becomes immutable. Inner
constructors are handled automatically, so you not need to construct this generated field.

Example:
```julia
@mutt struct S
    x :: Int
    y
    S(x, y=x+1) = new(x,y)
end
```
"""
macro mutt(expr)
    return _mutt_macro(expr)
end

# Turns `@mutt struct S x end` into:
# ```
# mutable struct S <: Mutt
#     __mutt_mutable :: Bool
#     x
#     ... constructors ...
# end
# ```
function _mutt_macro(expr)
    if MacroTools.isstructdef(expr)
        def = MacroTools.splitstructdef(expr)
        # Mutts structs are julia-mutable
        def[:mutable] = true
        # Add `__mutt_mutable` field to the struct.
        # (Put our inserted variable first so the user's constructor can leave undefined
        # fields if that's a thing they're into.)
        pushfirst!(def[:fields], (:__mutt_mutable, Bool))
        # Initialize the new `__mutt_mutable` boolean in the construtors.
        if isempty(def[:constructors])
            # Add the default constructor(s), if none exist, to initialize __mutt_mutable.
            append!(def[:constructors], default_constructors(def[:name], def[:params], def[:fields][2:end]))
        else
            # Inject `true` to initialize __mutt_mutable in `new()` expressions
            def[:constructors] = map(inject_bool_into_constructor!, def[:constructors])
        end
        # Make this type a Mutt.
        def[:supertype] = Mutt  # TODO: make this a trait instead

        return esc(MacroTools.combinestructdef(def))
   else
       throw(ArgumentError("@mutt macro must be called with a struct definition: @mutt struct S ... end"))
   end
end

function default_constructors(typename, typeparams, fields)
    # TODO: if empty, no bool...?
    typed_args = Tuple(if f[2] == Any f[1] else MacroTools.combinearg(f..., false, nothing) end
                       for f in fields)
    untyped_args = Tuple(f[1] for f in fields)
    function make_constructor(args, argnames)
        ps = typeparams
        if !isempty(ps)
            full_name = :($typename{$(ps...)})
            new_expr = :(new{$(ps...)})
            :(function $full_name($(args...)) where {$(ps...)} ; $new_expr(true, $(argnames...)) end)
        else
            :($typename($(args...)) = new(true, $(argnames...)))
        end
    end
    new_expr = :new
    # If none of the args have types, these will be the same.
    if typed_args == untyped_args
        [make_constructor(untyped_args, untyped_args)]
    else
        [make_constructor(typed_args,   untyped_args),
         make_constructor(untyped_args, untyped_args)]
    end
end
function inject_bool_into_constructor!(constructor)
    function inject_bool_into_new!(expr)
        if @capture(expr, new(args__))
            expr.args = [:new, true, args...]
            expr
        elseif @capture(expr, new{T__}(args__))
            insert!(expr.args, 2, true)
            expr
        else
            expr
        end
    end
    postwalk(inject_bool_into_new!, constructor)
end

end # module
