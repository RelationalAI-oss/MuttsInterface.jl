"""
    module MuttsInterface
Explorations of a mutable-until-shared discipline in Julia. (MUTable 'Til Shared)
"""
module MuttsInterface

import MacroTools
using MacroTools: postwalk, @capture

#=
Notes

- I've removed the `Base.isimmutable` overload, since I _think_ that's referring to
  specifically the julia "immutable struct" meaning. It may break things to "lie" about
  this. Also, if we do want to support this, we'd have to add an overload for each type
  (exactly like what was done for setproperty!).

TODO

- Need a LICENSE file for this repo
- Need some mechanism to ensure that Mutt types can't be shared
  outside the current Task without being marked immutable.
    - Perhaps by injecting a check into `put!(::Channel, ::Mutt)`,
      or by dasserting in setters if the current task has changed.
- Add special casing for empty structs? They are always immutable so don't need the bool..
- Add check (warning or error?) that all fields of Mutts type must also be either Mutts or
  immutable.
- Should we autogenerate a `copy()` function for @mutt types?
- Try out using different runtime types for mutable & immutable versions instead of
  injecting a boolean: measure performance difference.
=#

export @mutt, is_mutts_type, branch!, is_mutts_mutable, mark_immutable!, mutable_version

"""
    is_mutts_type(t::Type) -> Bool

Returns true if type `t` was created via the `@mutt` macro, meaning it is a Mutable Til
Shared type, and implements the _mutable-until-shared_ discipline. These types start out
mutable, and can be saved in a frozen version via `mark_immutable!` and `branch!`.
"""
is_mutts_type(t::Type) = mutts_trait(t) == MuttsType()

# --- Trait dispatch for Mutt types -----------------------
# Since Mutts types don't inherit from a common abstract type (to allow them to inherit
# from their own base types, e.g. AbstractDict), we use trait-inheritance to write functions
# that want different methods for Mutts and non-Mutts types.
# (For more on Traits in Julia ("Holy Traits"), see this blog post):
# https://invenia.github.io/blog/2019/11/06/julialang-features-part-2/
struct MuttsType end
struct NonMuttsType end
# Types are consider non-Mutts by default, and the @mutt macro will create an overload for
# `mutts_trait(T)` marking them as MuttsType.
mutts_trait(::Type) = NonMuttsType()
mutts_trait(v::T) where T = mutts_trait(T)


is_mutts_mutable(obj::T) where T = is_mutts_mutable(mutts_trait(T), obj)
is_mutts_mutable(::MuttsType, obj) = obj.__mutt_mutable

mutable_version(obj::T) where T = mutable_version(mutts_trait(T), obj)
function mutable_version(::MuttsType, obj)
    is_mutts_mutable(obj) ? obj : branch!(obj)
end

"""
    branchactions(obj) = nothing

This callback function is called immediately before a Mutt object is branched from (even if
it was already immutable). Users can add methods to this callback to perform arbitrary
actions right before an object is branched.
"""
branchactions(obj) = nothing

"""
    mark_immutable!(obj)

Freeze `obj` from further mutations, making it eligible to pass to
other Tasks, branch! from it, or otherwise share it.
"""
function mark_immutable! end

mark_immutable!(o::T) where T = mark_immutable!(mutts_trait(T), o)

mark_immutable!(::NonMuttsType, a) = a

@generated function mark_immutable!(::MuttsType, obj::T) where T
    as = map(fieldnames(T)) do sym
        :( mark_immutable!(getfield(obj, $(QuoteNode(sym)))) )
    end

    return quote
        if is_mutts_mutable(obj)
            # Mark all Mutt fields immutable
            $(as...)

            # Then mark this object immutable
            set_immutable_flag!(obj)
        end
        obj
    end
end

"""
    set_immutable_flag!(obj)

For `MuttsTypes`, sets the `__mutt_mutable` property to `false`. Write a method
for your type with signature `set_immutable_flag!(::MuttsType, o::YourType)` if your
type does not have the `__mutt_mutable` property.
"""
set_immutable_flag!(o::T) where T = set_immutable_flag!(mutts_trait(T), o)
set_immutable_flag!(::MuttsType, o) = o.__mutt_mutable = false

"""
    branch!(obj)

Return a mutable shallow copy of Mutts object `obj`, whose children are all still immutable.
"""
branch!(obj::T) where T = branch!(mutts_trait(T), obj)
function branch!(::MuttsType, obj)
    branchactions(obj)
    mark_immutable!(obj)

    return make_mutable_copy(obj)
end

function make_mutable_copy end
# Overload setproperty! for Mutts types to throw exception if attempting to modify a Mutt
# once it's been marked immutable.
# NOTE: The @mutt macro will overload setproperty!(obj::T, name, x) to call this method.
function Base.setproperty!(::MuttsType, obj, name::Symbol, x)
    @assert is_mutts_mutable(obj)
    setfield!(obj, name, x)
end


"""
    @mutt struct MyType
        fields...
    end

Macro to define a _mutable-until-shared_ data type. Mutable-until-shared types
are essentially immutable data structures, that give the flexibility of mutating
them until they are "finished", at which point they are free to be shared with
other Tasks, or other parts of the code.

`Mutt` types act like mutable structs, until the user calls `mark_immutable!(obj)`,
after which they act like purely immutable types.

The complete API includes:
 - [`mark_immutable!(obj)`](@ref): Freeze `obj`, preventing any future mutations.
 - [`branch!(obj)`](@ref): Make a _mutable_ shallow copy of `obj`.
 - [`mutable_version(obj)`](@ref): Return a mutable version of `obj`, either
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
        typename = def[:name]
        # Mutts structs are julia-mutable
        def[:mutable] = true
        # Add `__mutt_mutable` field to the struct.
        # (Put our inserted variable first so the user's constructor can leave undefined
        # fields if that's a thing they're into.)
        pushfirst!(def[:fields], (:__mutt_mutable, Bool))
        # Initialize the new `__mutt_mutable` boolean in the construtors.
        if isempty(def[:constructors])
            # Add the default constructor(s), if none exist, to initialize __mutt_mutable.
            append!(def[:constructors], default_constructors(typename, def[:params], def[:fields][2:end]))
        else
            # Inject `true` to initialize __mutt_mutable in `new()` expressions
            def[:constructors] = map(inject_bool_into_constructor!, def[:constructors])
        end
        # Mark this type as a Mutt (Register with the trait dispatch).
        push!(def[:constructors],
              # (Note the <:T which covers the case where T is paramaterized)
              :($(@__MODULE__).mutts_trait(::Type{<:$typename}) = $MuttsType()))
        # Override setproperty! to prevent mutating a Mutt once it's been marked immutable.
        push!(def[:constructors],
        :(function $Base.setproperty!(obj::$typename, name::Symbol, x)
            setproperty!($MuttsType(), obj, name, x)
        end))

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
