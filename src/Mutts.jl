"""
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
    @mutt expr

Macro to define a mutable-until-shared data type.
"""
macro mutt(expr)
    return mutt(expr)
end

ismutable(obj :: Mutt) = obj.__mutt_mutable

function getmutableversion(obj :: Mutt)
    ismutable(obj) ? obj : branch(obj)
end

branchactions(obj :: Mutt) = nothing

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

function branch(obj :: Mutt)
    branchactions(obj)
    markimmutable(obj)

    obj = copy(obj)
    obj.__mutt_mutable = true
    obj
end

end # module
