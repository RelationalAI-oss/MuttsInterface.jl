
module MuttsVersionedTrees

using Mutts
using AbstractTrees  # For printing

const insert!, delete! = Base.insert!, Base.delete!  # For export
export VTree, insert!, delete!

const mark_immutable! = Mutts.mark_immutable!  # For export
export mark_immutable!  # From Mutts

"""
    VTree{T}(value; left = nothing, right = nothing)

A versioned, mutable until shared binary branching tree.

```jldoctest
julia> begin
           head = VTree{Int}()
           # Insert elements
           head = insert!(head, 5);
           head = insert!(head, 1);
           head = insert!(head, 10);
           head = insert!(head, 2);
           # Print
           println(head)
           # Freeze `head` -- ready to share to other threads.
           mark_immutable!(head)
           println(head)
           # Keep branching from head
           head = insert!(head, 7);
           head = delete!(head, 1);
           println(head)
       end
VTreeNode{Int64}(5) ✔︎
├─ VTreeNode{Int64}(1) ✔︎
│  ├─ ∅
│  └─ VTreeNode{Int64}(2) ✔︎
└─ VTreeNode{Int64}(10) ✔︎

VTreeNode{Int64}(5) 🔒
├─ VTreeNode{Int64}(1) 🔒
│  ├─ ∅
│  └─ VTreeNode{Int64}(2) 🔒
└─ VTreeNode{Int64}(10) 🔒

VTreeNode{Int64}(5) ✔︎
├─ VTreeNode{Int64}(2) 🔒
└─ VTreeNode{Int64}(10) ✔︎
   ├─ VTreeNode{Int64}(7) ✔︎
   └─ ∅

```
"""
VTree

struct EmptyVTree{T} end
Base.convert(::Type{EmptyVTree{T}}, ::Nothing) where T = EmptyVTree{T}()
Base.show(io::IO, ::EmptyVTree) = print(io, "∅")

@mutt struct VTreeNode{T}
    value :: T
    left  :: Union{EmptyVTree, VTreeNode{T}}
    right :: Union{EmptyVTree, VTreeNode{T}}
    VTreeNode{T}(v, l,r) where T = new{T}(v, l,r)
    VTreeNode{T}(v; left = nothing, right = nothing) where T = new{T}(v, left, right)
end

const VTree{T} = Union{EmptyVTree, VTreeNode{T}}
Base.convert(::Type{VTree{T}}, ::Nothing) where T = EmptyVTree{T}()

# ----- Helper Constructor --------
VTree{T}() where T = EmptyVTree{T}()
VTree{T}(x, args...; kwargs...) where T = VTreeNode{T}(x, args...; kwargs...)

AbstractTrees.children(v::EmptyVTree{T}) where T = VTree{T}[]
function AbstractTrees.children(v::VTreeNode)
    if (v.left isa EmptyVTree && v.right isa EmptyVTree)
        ()
    else
        (v.left, v.right)
    end
end
function AbstractTrees.printnode(io::IO, v::VTreeNode{T}) where T
    mutable_emoji = is_mutts_mutable(v) ? "✔︎" : "🔒"
    print(io,"VTreeNode{$T}($(v.value)) $mutable_emoji")
end

Base.show(io::IO, v::VTree) = AbstractTrees.print_tree(io, v)

# ----- Copy needed for Mutts.branch!() ---------------
Mutts.make_mutable_copy(v::EmptyVTree{T}) where T = EmptyVTree{T}()
Mutts.make_mutable_copy(v::VTreeNode{T}) where T = VTreeNode{T}(v.value, v.left, v.right)

# --- Insert! -----------------
"""
    head = insert!(head::VTree, value)

Return a new VTree with `value` inserted into the sorted tree `head`, mutating it if
possible, or returning a new branched copy if needed.

```jldoctest
julia> head1 = mark_immutable!(head)  # Store backup of head
VTreeNode{Int64}(5) 🔒
├─ VTreeNode{Int64}(1) 🔒
└─ VTreeNode{Int64}(10) 🔒
   ├─ VTreeNode{Int64}(7) 🔒
   └─ ∅


julia> head = insert!(head, 2)
VTreeNode{Int64}(5) ✔︎
├─ VTreeNode{Int64}(1) ✔︎
│  ├─ ∅
│  └─ VTreeNode{Int64}(2) ✔︎
└─ VTreeNode{Int64}(10) 🔒
   ├─ VTreeNode{Int64}(7) 🔒
   └─ ∅

julia> head1
VTreeNode{Int64}(5) 🔒
├─ VTreeNode{Int64}(1) 🔒
└─ VTreeNode{Int64}(10) 🔒
   ├─ VTreeNode{Int64}(7) 🔒
   └─ ∅
```
"""
Base.insert!(::EmptyVTree{T}, x) where T = VTreeNode{T}(x)
function Base.insert!(head::VTreeNode{T}, x) where T
    head = mutable_version(head)

    if x <= head.value
        if head.left isa EmptyVTree
            head.left = VTreeNode{T}(x)
        else
            head.left = insert!(head.left, x)
        end
    else
        if head.right isa EmptyVTree
            head.right = VTreeNode{T}(x)
        else
            head.right = insert!(head.right, x)
        end
    end
    return head
end

# --- delete! -----------------
"""
    head = delete!(head::VTree, x)

Return a new VTree with `value` deleted from the sorted tree `head`, mutating it if
possible, or returning a new branched copy if needed.

```jldoctest
julia> head = head2;  # Starting with a different example tree

julia> head1 = mark_immutable!(head)  # Store backup of head
VTreeNode{Int64}(5) 🔒
├─ VTreeNode{Int64}(1) 🔒
│  ├─ ∅
│  └─ VTreeNode{Int64}(2) 🔒
└─ VTreeNode{Int64}(10) 🔒
   ├─ VTreeNode{Int64}(7) 🔒
   │  ├─ ∅
   │  └─ VTreeNode{Int64}(8) 🔒
   └─ ∅


julia> head = delete!(head, 5)
VTreeNode{Int64}(7) ✔︎
├─ VTreeNode{Int64}(1) 🔒
│  ├─ ∅
│  └─ VTreeNode{Int64}(2) 🔒
└─ VTreeNode{Int64}(10) ✔︎
   ├─ VTreeNode{Int64}(8) 🔒
   └─ ∅

julia> head1
VTreeNode{Int64}(5) 🔒
├─ VTreeNode{Int64}(1) 🔒
│  ├─ ∅
│  └─ VTreeNode{Int64}(2) 🔒
└─ VTreeNode{Int64}(10) 🔒
   ├─ VTreeNode{Int64}(7) 🔒
   │  ├─ ∅
   │  └─ VTreeNode{Int64}(8) 🔒
   └─ ∅
```
"""
Base.delete!(e::EmptyVTree, _) = e
function Base.delete!(head::VTreeNode, x)
    head = mutable_version(head)

    if x == head.value
        if head.left isa EmptyVTree
            # Promote right child to parent
            head = head.right
        elseif head.right isa EmptyVTree
            head = head.left
        else
            #
            head.right, popped_val = _pop_leftmost!(head.right)
            head.value = popped_val
        end
    elseif x < head.value
        head.left = delete!(head.left, x)
    else
        head.right = delete!(head.right, x)
    end
    return head
end

# Used in delete!, above
_pop_leftmost!(head::EmptyVTree) = head
function _pop_leftmost!(head::VTreeNode)
    head = mutable_version(head)

    if head.left isa EmptyVTree
        popped_val = head.value
        head = delete!(head, popped_val)
        return (head, popped_val)
    else
        (head.left, popped_val) = _pop_leftmost!(head.left)
        return (head, popped_val)
    end
end


end  # module
