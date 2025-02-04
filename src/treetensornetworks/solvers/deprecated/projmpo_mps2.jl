import ITensors: AbstractProjMPO, makeL!, makeR!, set_nsite!, contract, nsite
import Base: copy

mutable struct ProjMPO_MPS2 <: AbstractProjMPO
  PH::ProjMPO
  Ms::Vector{ProjMPS2}
end

function ProjMPO_MPS2(H::MPO, M::MPS)
  return ProjMPO_MPS2(ProjMPO(H), [ProjMPS2(M)])
end

function ProjMPO_MPS2(H::MPO, Mv::Vector{MPS})
  return ProjMPO_MPS2(ProjMPO(H), [ProjMPS2(m) for m in Mv])
end

copy(P::ProjMPO_MPS2) = ProjMPO_MPS2(copy(P.PH), copy(P.Ms))

nsite(P::ProjMPO_MPS2) = nsite(P.PH)

function set_nsite!(P::ProjMPO_MPS2, nsite)
  set_nsite!(P.PH, nsite)
  for m in P.Ms
    set_nsite!(m, nsite)
  end
  return P
end

function makeL!(P::ProjMPO_MPS2, psi::MPS, k::Int)
  makeL!(P.PH, psi, k)
  for m in P.Ms
    makeL!(m, psi, k)
  end
  return P
end

function makeR!(P::ProjMPO_MPS2, psi::MPS, k::Int)
  makeR!(P.PH, psi, k)
  for m in P.Ms
    makeR!(m, psi, k)
  end
  return P
end

contract(P::ProjMPO_MPS2, v::ITensor) = contract(P.PH, v)

proj_mps(P::ProjMPO_MPS2) = [proj_mps(m) for m in P.Ms]

underlying_graph(P::ProjMPO_MPS2) = chain_lattice_graph(length(P.PH.H)) # tree patch
