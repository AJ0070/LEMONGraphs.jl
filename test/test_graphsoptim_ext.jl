@testitem "GraphsOptim: LEMON shortest_path dispatch" begin
    using Graphs, GraphsOptim, LEMONGraphs, Test

    g = SimpleDiGraph(4)
    add_edge!(g, 1, 2)
    add_edge!(g, 2, 3)
    add_edge!(g, 1, 3)

    weights = zeros(Int, 4, 4)
    weights[1, 2] = 1
    weights[2, 3] = 2
    weights[1, 3] = 10

    @test GraphsOptim.shortest_path(g, 1, 3, weights, LEMONAlgorithm()) == [1, 2, 3]
    @test GraphsOptim.shortest_path(g, 1, 1, weights, LEMONAlgorithm()) == [1]

    err = @test_throws ArgumentError GraphsOptim.shortest_path(
        g, 1, 4, weights, LEMONAlgorithm()
    )
    @test occursin("No path", sprint(showerror, err.value))

    float_cost = Float64.(weights)
    err = @test_throws ArgumentError GraphsOptim.shortest_path(
        g, 1, 3, float_cost, LEMONAlgorithm()
    )
    @test occursin("integer edge costs", sprint(showerror, err.value))
end

@testitem "GraphsOptim: unimplemented LEMON dispatches raise helpful errors" begin
    using Graphs, GraphsOptim, LEMONGraphs, Test

    ug = path_graph(3)

    err = @test_throws ArgumentError GraphsOptim.min_vertex_cover(ug, LEMONAlgorithm())
    @test occursin("min_vertex_cover", sprint(showerror, err.value))

    err = @test_throws ArgumentError GraphsOptim.maximum_weight_clique(ug, LEMONAlgorithm())
    @test occursin("maximum_weight_clique", sprint(showerror, err.value))
end