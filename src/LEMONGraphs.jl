module LEMONGraphs

import Graphs
import Graphs:
    Graph, DiGraph, Edge, vertices, edges, nv, ne, src, dst,
    has_vertex, has_edge, inneighbors, outneighbors, is_directed,
    edgetype, AbstractGraph

using CxxWrap

# CxxWrap binding module
module Lib
  using CxxWrap
  import LEMON_jll
  @wrapmodule(LEMON_jll.get_liblemoncxxwrap_path)

  function __init__()
    @initcxx
  end

  # Convenience helpers for node/edge ID extraction
  id(n::ListGraphNodeIt) = id(convert(ListGraphNode, n))
  id(n::ListGraphEdgeIt) = id(convert(ListGraphEdge, n))
  id(n::ListDigraphNodeIt) = id(convert(ListDigraphNode, n))
end

"""
    LEMONGraphs.CxxInt

Julia counterpart of the C++ `int` used by the LEMON maps that are instantiated
for `int` (`Dijkstra`, `MaxWeightedPerfectMatching`).
"""
const CxxInt = Cint

"""
    LEMONGraphs.CxxLong

Julia counterpart of the C++ `long long` used by the LEMON minimum cost flow
solvers, which are instantiated for 64-bit flow and cost values.
"""
const CxxLong = Clonglong

export LEMONGraph, LEMONDiGraph, LEMONAlgorithm, maxweightedperfectmatching

"""
    LEMONGraph{T,G,N,E} <: AbstractGraph{Int}

Wrapper around LEMON's `ListGraph` C++ type providing a Julia interface
conforming to the Graphs.jl `AbstractGraph` API.

The wrapper caches the endpoints of every LEMON edge and an adjacency list on
the Julia side, so that the Graphs.jl API can be served without crossing the
C++ boundary. Construction is `O(nv + ne)`; every subsequent query is as fast
as the equivalent `SimpleGraph` query.

`LEMONGraph(g::AbstractGraph)` wraps an existing graph and `LEMONGraph(n)`
builds an edgeless one on `n` vertices. `add_vertex!` and `add_edge!` grow the
graph; `rem_vertex!` and `rem_edge!` return `false`, because `LEMON_jll` does
not expose `ListGraph::erase`.
"""
struct LEMONGraph{T,G,N,E} <: AbstractGraph{Int}
    graph::G
    nodes::N
    edges::E
    edge_src::Vector{Int}
    edge_dst::Vector{Int}
    adjacency::Vector{Vector{Int}}

    function LEMONGraph(g, ns, es)
        us = Vector{Int}(undef, length(es))
        vs = Vector{Int}(undef, length(es))
        adjacency = [Int[] for _ in eachindex(ns)]
        for (i, e) in enumerate(es)
            # LEMON does not order the endpoints of an undirected edge, so they
            # are normalized to `src <= dst` the way `SimpleGraph` does
            u, v = minmax(Lib.id(Lib.u(g, e)) + 1, Lib.id(Lib.v(g, e)) + 1)
            us[i] = u
            vs[i] = v
            push!(adjacency[u], v)
            u == v || push!(adjacency[v], u)
        end
        foreach(sort!, adjacency)
        return new{eltype(ns),typeof(g),typeof(ns),typeof(es)}(g, ns, es, us, vs, adjacency)
    end
end

"""
    LEMONDiGraph{T,G,N,A} <: AbstractGraph{Int}

Wrapper around LEMON's `ListDigraph` C++ type providing a Julia interface
conforming to the Graphs.jl `AbstractGraph` API.

Like [`LEMONGraph`](@ref) it caches arc endpoints and in/out adjacency lists so
that Graphs.jl algorithms never pay a C++ call per neighbour lookup, and it
supports the same growing-only subset of the mutation API.
"""
struct LEMONDiGraph{T,G,N,A} <: AbstractGraph{Int}
    graph::G
    nodes::N
    arcs::A
    arc_src::Vector{Int}
    arc_dst::Vector{Int}
    fadj::Vector{Vector{Int}}
    badj::Vector{Vector{Int}}

    function LEMONDiGraph(g, ns, as)
        us = Vector{Int}(undef, length(as))
        vs = Vector{Int}(undef, length(as))
        fadj = [Int[] for _ in eachindex(ns)]
        badj = [Int[] for _ in eachindex(ns)]
        for (i, a) in enumerate(as)
            u = Lib.id(Lib.source(g, a)) + 1
            v = Lib.id(Lib.target(g, a)) + 1
            us[i] = u
            vs[i] = v
            push!(fadj[u], v)
            push!(badj[v], u)
        end
        foreach(sort!, fadj)
        foreach(sort!, badj)
        return new{eltype(ns),typeof(g),typeof(ns),typeof(as)}(
            g, ns, as, us, vs, fadj, badj
        )
    end
end

"""
    LEMONAlgorithm()

Marker type for dispatch to LEMON-backed algorithm implementations.

Pass it as the last positional argument to a Graphs.jl, GraphsMatching.jl or
GraphsOptim.jl function to request the LEMON implementation, e.g.
`dijkstra_shortest_paths(g, 1, distmx, LEMONAlgorithm())`.
"""
struct LEMONAlgorithm end

# Fast conversion helpers
"""
    to_list_graph(g) -> (ListGraph, Vector, Vector)

Fast conversion that caches nodes/edges for reuse in the [`LEMONGraph`](@ref)
wrapper. If `g` is already a `LEMONGraph`, its internal representation is
returned in `O(1)` without copying anything.
"""
function to_list_graph(g::Graph)
    lg = Lib.ListGraph()
    ns = [Lib.addNode(lg) for _ in Graphs.vertices(g)]
    es = [Lib.addEdge(lg, ns[Graphs.src(e)], ns[Graphs.dst(e)]) for e in Graphs.edges(g)]
    return (lg, ns, es)
end

function to_list_graph(g::AbstractGraph)
    is_directed(g) && throw(ArgumentError("LEMON matching currently only supports undirected graphs"))
    return to_list_graph(Graph(g))
end

function to_list_graph(g::LEMONGraph)
    return (g.graph, g.nodes, g.edges)  # O(1) reuse
end

"""
    to_list_digraph(g) -> (ListDigraph, Vector, Vector)

Fast conversion for directed graphs. If `g` is already a [`LEMONDiGraph`](@ref),
its internal representation is returned in `O(1)`.
"""
function to_list_digraph(g::DiGraph)
    dg = Lib.ListDigraph()
    ns = [Lib.addNode(dg) for _ in Graphs.vertices(g)]
    as = [Lib.addArc(dg, ns[Graphs.src(e)], ns[Graphs.dst(e)]) for e in Graphs.edges(g)]
    return (dg, ns, as)
end

function to_list_digraph(g::AbstractGraph)
    return to_list_digraph(DiGraph(g))
end

function to_list_digraph(g::LEMONDiGraph)
    return (g.graph, g.nodes, g.arcs)  # O(1) reuse
end

# Constructors
"""
    LEMONGraph(g::AbstractGraph) -> LEMONGraph

Convert an undirected Graphs.jl graph to a `LEMONGraph` wrapper.
"""
function LEMONGraph(g::Graph)
    lg, ns, es = to_list_graph(g)
    return LEMONGraph(lg, ns, es)
end

function LEMONGraph(g::AbstractGraph)
    lg, ns, es = to_list_graph(g)
    return LEMONGraph(lg, ns, es)
end

"""
    LEMONDiGraph(g::AbstractGraph) -> LEMONDiGraph

Convert a directed Graphs.jl graph to a `LEMONDiGraph` wrapper.
"""
function LEMONDiGraph(g::DiGraph)
    dg, ns, as = to_list_digraph(g)
    return LEMONDiGraph(dg, ns, as)
end

function LEMONDiGraph(g::AbstractGraph)
    dg, ns, as = to_list_digraph(g)
    return LEMONDiGraph(dg, ns, as)
end

# `LEMONGraph(n)` / `LEMONDiGraph(n)` build an edgeless wrapper on `n`
# vertices. The methods are defined on `Type{<:...}` rather than on the
# `UnionAll` alone because generic Graphs.jl algorithms such as
# `induced_subgraph` build their result with `typeof(g)(n)`, which names the
# concrete parameterization.
(::Type{L})(n::Integer) where {L<:LEMONGraph} = LEMONGraph(Graph(Int(n)))
(::Type{L})(n::Integer) where {L<:LEMONDiGraph} = LEMONDiGraph(DiGraph(Int(n)))

end  # module LEMONGraphs
