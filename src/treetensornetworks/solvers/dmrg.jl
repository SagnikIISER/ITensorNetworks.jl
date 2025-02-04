function eigsolve_solver(; solver_which_eigenvalue=:SR, kwargs...)
  function solver(H, init; kws...)
    howmany = 1
    which = solver_which_eigenvalue
    solver_kwargs = (;
      ishermitian=get(kwargs, :ishermitian, true),
      tol=get(kwargs, :solver_tol, 1E-14),
      krylovdim=get(kwargs, :solver_krylovdim, 3),
      maxiter=get(kwargs, :solver_maxiter, 1),
      verbosity=get(kwargs, :solver_verbosity, 0),
    )
    vals, vecs, info = eigsolve(H, init, howmany, which; solver_kwargs...)
    psi = vecs[1]
    return psi, info
  end
  return solver
end

"""
Overload of `ITensors.dmrg`.
"""
function dmrg(H, init::AbstractTTN; kwargs...)
  reverse_step = false
  psi = alternating_update(eigsolve_solver(; kwargs...), H, init; reverse_step, kwargs...)
  return psi
end

"""
Overload of `KrylovKit.eigsolve`.
"""
function eigsolve(H, init::AbstractTTN; kwargs...)
  return dmrg(H, init; kwargs...)
end
