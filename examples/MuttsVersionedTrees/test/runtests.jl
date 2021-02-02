using MuttsVersionedTrees
using Test
using Documenter

@testset "MuttsVersionedTrees" begin

    @testset "jldoctests" begin
    # Set up trees used in jldoctests
    Documenter.DocMeta.setdocmeta!(
        MuttsVersionedTrees,
        :DocTestSetup,
        quote
            using MuttsVersionedTrees
            using MuttsInterface
            head = VTree{Int}();
        
            head = insert!(head, 5);
            head = insert!(head, 1);
            head = insert!(head, 10);
            head = insert!(head, 2);
        
            println(head)
        
            mark_immutable!(head)
        
            head = insert!(head, 7);
            head = delete!(head, 2);
        
            mark_immutable!(head)
            head2 = branch!(head)
        
            head2 = insert!(head2, 2);
            head2 = insert!(head2, 8);
        end;
        recursive=true)
    
    Documenter.doctest(nothing, [MuttsVersionedTrees,])
    end
end
