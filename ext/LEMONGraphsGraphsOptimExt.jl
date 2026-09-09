module LEMONGraphsGraphsOptimExt

using LEMONGraphs
using Graphs
using GraphsOptim
using SparseArrays: sparse

const Lib = LEMONGraphs.Lib
const LEMONAlg = LEMONGraphs.LEMONAlgorithm
const CxxLong = LEMONGraphs.CxxLong

"""
    shortest_path(g, source, target, edge_cost, ::LEMONAlgorithm)

Compute the shortest path using LEMON's Dijkstra backend.

Returns the sequence of vertices from `source` to `target`. Only integer
`edge_cost` matrices are supported, because LEMON's `Dijkstra` binding is
instantiated for C++ `int`.
"""
function GraphsOptim.shortest_path(
    g::AbstractGraph,
    source::Int,
    target::Int,
    edge_cost::AbstractMatrix,
    alg::LEMONAlg,
)
    if !(eltype(edge_cost) <: Integer)
        throw(ArgumentError(
            "LEMON shortest_path only supports integer edge costs. " *
            "Provide an integer cost matrix or use the default GraphsOptim solver backend."
        ))
    end
    state = Graphs.dijkstra_shortest_paths(g, source, edge_cost, alg)
    return _reconstruct_path(state.parents, source, target)
end
"""
    min_vertex_cover(g, ::LEMONAlgorithm; kwargs...)

LEMON does not ship a minimum vertex cover solver, so this method always throws.
It exists so that the `LEMONAlgorithm()` dispatch fails with an actionable
message rather than a bare `MethodError`.
"""
function GraphsOptim.min_vertex_cover(g::AbstractGraph, ::LEMONAlg; kwargs...)
    throw(ArgumentError(
        "LEMON ships no minimum vertex cover solver, so min_vertex_cover has no " *
        "LEMON backend. Drop the LEMONAlgorithm() argument to use GraphsOptim's."
    ))
end

"""
    maximum_weight_clique(g, ::LEMONAlgorithm; kwargs...)

LEMON does not ship a maximum weight clique solver, so this method always
throws, for the same reason as `min_vertex_cover`.
"""
function GraphsOptim.maximum_weight_clique(g::AbstractGraph, ::LEMONAlg; kwargs...)
    throw(ArgumentError(
        "LEMON ships no maximum weight clique solver, so maximum_weight_clique has " *
        "no LEMON backend. Drop the LEMONAlgorithm() argument to use GraphsOptim's."
    ))
end
function _reconstruct_path(parents::AbstractVector{<:Integer}, source::Int, target::Int)
    source == target && return [source]

    path = Int[]
    current = target
    while current != 0
        push!(path, current)
        current == source && break
        current = parents[current]
    end

    if isempty(path) || path[end] != source
        throw(ArgumentError("No path from source to target using LEMON backend"))
    end

    reverse!(path)
    return path
end
# Future algorithms: as more LEMON solvers are exposed by LEMON_jll (it also
# ships the CapacityScaling, CostScaling and CycleCanceling minimum cost flow
# solvers), add the corresponding `LEMONAlgorithm` dispatches here.

end  # module