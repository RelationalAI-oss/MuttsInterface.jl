using Test

@testset "MuttsInterface.jl" begin
    include("MuttsInterface.jl")
end

# -----------------------------------------------------------
# --- Example packages
# -----------------------------------------------------------

import Pkg

# Run the tests for the packages in examples/...
@testset "examples" begin
    Pkg.activate("../examples/MuttsVersionedTrees")
    Pkg.test(coverage=true)
end

# Done runing example packages
Pkg.activate(".")

# -----------------------------------------------------------
