using ITensors, OMEinsumContractionOrders
using ITensorNetworks:
  _root,
  _mps_partition_inds_order,
  _mincut_partitions,
  _is_rooted_directed_binary_tree,
  _contract_deltas_ignore_leaf_partitions

@testset "test mincut functions on top of MPS" begin
  i = Index(2, "i")
  j = Index(2, "j")
  k = Index(2, "k")
  l = Index(2, "l")
  m = Index(2, "m")
  n = Index(2, "n")
  o = Index(2, "o")
  p = Index(2, "p")

  T = randomITensor(i, j, k, l, m, n, o, p)
  M = MPS(T, (i, j, k, l, m, n, o, p); cutoff=1e-5, maxdim=500)
  tn = ITensorNetwork(M[:])
  for out in [binary_tree_structure(tn), path_graph_structure(tn)]
    @test out isa DataGraph
    @test _is_rooted_directed_binary_tree(out)
    @test length(vertex_data(out).values) == 8
  end
  out = _mps_partition_inds_order(tn, [o, p, i, j, k, l, m, n])
  @test out in [[i, j, k, l, m, n, o, p], [p, o, n, m, l, k, j, i]]
  p1, p2 = _mincut_partitions(tn, [k, l], [m, n])
  # When MPS bond dimensions are large, the partition will not across internal inds
  @test (length(p1) == 0) || (length(p2) == 0)

  M = MPS(T, (i, j, k, l, m, n, o, p); cutoff=1e-5, maxdim=2)
  tn = ITensorNetwork(M[:])
  p1, p2 = _mincut_partitions(tn, [k, l], [m, n])
  # When MPS bond dimensions are small, the partition will across internal inds
  @test sort(p1) == [1, 2, 3, 4]
  @test sort(p2) == [5, 6, 7, 8]
end

@testset "test _binary_tree_partition_inds of a 2D network" begin
  N = (3, 3, 3)
  linkdim = 2
  network = randomITensorNetwork(IndsNetwork(named_grid(N)); link_space=linkdim)
  tn = Array{ITensor,length(N)}(undef, N...)
  for v in vertices(network)
    tn[v...] = network[v...]
  end
  tn = ITensorNetwork(vec(tn[:, :, 1]))
  for out in [binary_tree_structure(tn), path_graph_structure(tn)]
    @test out isa DataGraph
    @test _is_rooted_directed_binary_tree(out)
    @test length(vertex_data(out).values) == 9
  end
end

@testset "test partition with mincut_recursive_bisection alg of disconnected tn" begin
  inds = [Index(2, "$i") for i in 1:5]
  tn = ITensorNetwork([randomITensor(i) for i in inds])
  par = partition(tn, binary_tree_structure(tn); alg="mincut_recursive_bisection")
  networks = [Vector{ITensor}(par[v]) for v in vertices(par)]
  network = vcat(networks...)
  @test isapprox(contract(Vector{ITensor}(tn)), contract(network...))
end

@testset "test partition with mincut_recursive_bisection alg and approx_itensornetwork" begin
  i = Index(2, "i")
  j = Index(2, "j")
  k = Index(2, "k")
  l = Index(2, "l")
  m = Index(2, "m")
  for dtype in [Float64, ComplexF64]
    T = randomITensor(dtype, i, j, k, l, m)
    M = MPS(T, (i, j, k, l, m); cutoff=1e-5, maxdim=5)
    network = M[:]
    out1 = contract(network...)
    tn = ITensorNetwork(network)
    inds_btree = binary_tree_structure(tn)
    par = partition(tn, inds_btree; alg="mincut_recursive_bisection")
    par = _contract_deltas_ignore_leaf_partitions(par; root=_root(inds_btree))
    networks = [Vector{ITensor}(par[v]) for v in vertices(par)]
    network2 = vcat(networks...)
    out2 = contract(network2...)
    @test isapprox(out1, out2)
    # test approx_itensornetwork (here we call `contract` to test the interface)
    approx_tn, lognorm = contract(
      tn;
      alg="density_matrix",
      output_structure=binary_tree_structure,
      contraction_sequence_alg="sa_bipartite",
    )
    network3 = Vector{ITensor}(approx_tn)
    out3 = contract(network3...) * exp(lognorm)
    i1 = noncommoninds(network...)
    i3 = noncommoninds(network3...)
    @test (length(i1) == length(i3))
    @test isapprox(out1, out3)
  end
end
