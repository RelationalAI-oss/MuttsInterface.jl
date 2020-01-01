
module MuttsVersionedTrees

export VTree

using Mutts

"""
    VTree{T}(value; left = nothing, right = nothing)

A versioned, mutable until shared binary branching tree.

```jldoctest
head = VTree{Int}()

head = insert!(head, 5);
head = insert!(head, 1);
head = insert!(head, 10);
head = insert!(head, 2);

println(head)

markimmutable!(head)
println(head)

head = insert!(head, 7);
println(head)

# output

VTreeNode{Int64}(5) ✔︎
├─ VTreeNode{Int64}(1) ✔︎
│  └─ VTreeNode{Int64}(2) ✔︎
└─ VTreeNode{Int64}(10) ✔︎

VTreeNode{Int64}(5) 🔒
├─ VTreeNode{Int64}(1) 🔒
│  └─ VTreeNode{Int64}(2) 🔒
└─ VTreeNode{Int64}(10) 🔒

VTreeNode{Int64}(5) ✔︎
├─ VTreeNode{Int64}(1) 🔒
│  └─ VTreeNode{Int64}(2) 🔒
└─ VTreeNode{Int64}(10) ✔︎
   └─ VTreeNode{Int64}(7) ✔︎
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

VTreeNode{Int}(2)
VTreeNode{Int}(2, left=VTreeNode{Int}(1))
VTreeNode{Int}(2, nothing, VTreeNode{Int}(10))

using AbstractTrees  # For printing
AbstractTrees.children(v::EmptyVTree{T}) where T = VTree{T}[]
AbstractTrees.children(v::VTreeNode) = [v for v in (v.left, v.right) if !(v isa EmptyVTree)]
function AbstractTrees.printnode(io::IO, v::VTreeNode{T}) where T
    mutable_emoji = ismutable(v) ? "✔︎" : "🔒"
    print(io,"VTreeNode{$T}($(v.value)) $mutable_emoji")
end

Base.show(io::IO, v::VTree) = AbstractTrees.print_tree(io, v)

VTreeNode{Int}(10, VTreeNode{Int}(0), VTreeNode{Int}(100))

# ----- Copy needed for Mutts.branch!() ---------------
Base.copy(v::EmptyVTree{T}) where T = EmptyVTree{T}()
Base.copy(v::VTreeNode{T}) where T = VTreeNode{T}(v.value, v.left, v.right)

# --- Insert! -----------------
Base.insert!(::EmptyVTree{T}, x) where T = VTreeNode{T}(x)
function Base.insert!(head::VTreeNode{T}, x) where T
    if !ismutable(head)
        head = branch!(head)
    end
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


end  # module
