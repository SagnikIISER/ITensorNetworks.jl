function update_step(
  order::TDVPOrder,
  solver,
  PH,
  time_step::Number,
  psi::AbstractTTN;
  current_time=0.0,
  kwargs...,
)
  directions_ = directions(order)
  sub_time_steps_ = time_step * sub_time_steps(order)
  info = nothing
  for substep in 1:length(sub_time_steps_)
    psi, PH, info = update_sweep(
      directions_[substep],
      solver,
      PH,
      psi;
      current_time,
      substep,
      time_step=sub_time_steps_[substep],
      kwargs...,
    )
    current_time += sub_time_steps_[substep]
  end
  return psi, PH, info
end

isforward(direction::Base.ForwardOrdering) = true
isforward(direction::Base.ReverseOrdering) = false

function update_sweep(
  direction::Base.Ordering,
  solver,
  PH,
  psi::AbstractTTN;
  current_time=0.0,
  cutoff=1E-16,
  maxdim=typemax(Int),
  mindim=1,
  normalize=false,
  nsite=2,
  outputlevel=0,
  reverse_step=true,
  root_vertex=default_root_vertex(underlying_graph(PH)),
  sw=1,
  kwargs...,
)
  PH = copy(PH)
  psi = copy(psi)
  if nv(psi) == 1
    error(
      "`alternating_update` currently does not support system sizes of 1. You can diagonalize the MPO tensor directly with tools like `LinearAlgebra.eigen`, `KrylovKit.exponentiate`, etc.",
    )
  end

  sweep_generator = nothing
  if nsite == 1
    sweep_generator = one_site_sweep
  elseif nsite == 2
    sweep_generator = two_site_sweep
  else
    error("Unsupported value $nsite for nsite keyword argument.")
  end

  observer = get(kwargs, :observer!, nothing)

  maxtruncerr = 0.0
  info = nothing
  for sweep_step in sweep_generator(
    direction, underlying_graph(PH), root_vertex, reverse_step; state=psi, kwargs...
  )
    psi, PH, current_time, spec, info = local_update(
      solver,
      PH,
      psi,
      sweep_step;
      current_time,
      outputlevel,
      cutoff,
      maxdim,
      mindim,
      normalize,
      kwargs...,
    )
    maxtruncerr = isnothing(spec) ? maxtruncerr : max(maxtruncerr, spec.truncerr)
    if outputlevel >= 2
      if time_direction(sweep_step) == +1
        @printf("Sweep %d, direction %s, position (%s,) \n", sw, direction, pos(step))
      end
      print("  Truncated using")
      @printf(" cutoff=%.1E", cutoff)
      @printf(" maxdim=%.1E", maxdim)
      print(" mindim=", mindim)
      print(" current_time=", round(current_time; digits=3))
      println()
      if spec != nothing
        @printf(
          "  Trunc. err=%.2E, bond dimension %d\n",
          spec.truncerr,
          linkdim(psi, edgetype(psi)(pos(step)...))
        )
      end
      flush(stdout)
    end
    if time_direction(sweep_step) == +1
      update!(
        observer;
        psi,
        bond=minimum(pos(sweep_step)),
        sweep=sw,
        half_sweep=isforward(direction) ? 1 : 2,
        spec,
        outputlevel,
        current_time,
        info,
      )
    end
  end
  # Just to be sure:
  normalize && normalize!(psi)
  return psi, PH, TDVPInfo(maxtruncerr)
end

#
# Here extract_local_tensor and insert_local_tensor
# are essentially inverse operations, adapted for different kinds of 
# algorithms and networks.
#
# In the simplest case, exact_local_tensor contracts together a few
# tensors of the network and returns the result, while 
# insert_local_tensors takes that tensor and factorizes it back
# apart and puts it back into the network.
#

function extract_local_tensor(psi::AbstractTTN, pos::Vector)
  return psi, prod(psi[v] for v in pos)
end

function extract_local_tensor(psi::AbstractTTN, e::NamedEdge)
  left_inds = uniqueinds(psi, e)
  U, S, V = svd(psi[src(e)], left_inds; lefttags=tags(psi, e), righttags=tags(psi, e))
  psi[src(e)] = U
  return psi, S * V
end

# sort of multi-site replacebond!; TODO: use dense TTN constructor instead
function insert_local_tensor(psi::AbstractTTN, phi::ITensor, pos::Vector; kwargs...)
  which_decomp::Union{String,Nothing} = get(kwargs, :which_decomp, nothing)
  normalize::Bool = get(kwargs, :normalize, false)
  eigen_perturbation = get(kwargs, :eigen_perturbation, nothing)
  spec = nothing
  for (v, vnext) in IterTools.partition(pos, 2, 1)
    e = edgetype(psi)(v, vnext)
    indsTe = inds(psi[v])
    L, phi, spec = factorize(
      phi, indsTe; which_decomp, tags=tags(psi, e), eigen_perturbation, kwargs...
    )
    psi[v] = L
    eigen_perturbation = nothing # TODO: fix this
  end
  psi[last(pos)] = phi
  psi = set_ortho_center(psi, [last(pos)])
  @assert isortho(psi) && only(ortho_center(psi)) == last(pos)
  normalize && (psi[last(pos)] ./= norm(psi[last(pos)]))
  return psi, spec # TODO: return maxtruncerr, will not be correct in cases where insertion executes multiple factorizations
end

function insert_local_tensor(psi::AbstractTTN, phi::ITensor, e::NamedEdge; kwargs...)
  psi[dst(e)] *= phi
  psi = set_ortho_center(psi, [dst(e)])
  return psi, nothing
end

function local_update(
  solver,
  PH,
  psi,
  sweep_step;
  current_time,
  outputlevel,
  time_step,
  normalize,
  noise,
  kwargs...,
)
  psi = orthogonalize(psi, current_ortho(sweep_step)) # choose the one that is closest to previous ortho center?
  psi, phi = extract_local_tensor(psi, pos(sweep_step))
  PH = set_nsite(PH, nsite(sweep_step))
  PH = position(PH, psi, pos(sweep_step))
  phi, info = solver(
    PH,
    phi;
    current_time,
    time_step=time_step * time_direction(sweep_step),
    outputlevel,
    kwargs...,
  )
  current_time += time_step
  normalize && (phi /= norm(phi))
  drho = nothing
  ortho = "left"
  if noise > 0.0 && isforward(direction)
    drho = noise * noiseterm(PH, phi, ortho) # TODO: actually implement this for trees...
  end
  psi, spec = insert_local_tensor(
    psi, phi, pos(sweep_step); eigen_perturbation=drho, ortho, normalize, kwargs...
  )
  return psi, PH, current_time, spec, info
end
