# Chain rules to allow differentiable simulations

@non_differentiable find_neighbors(args...)
@non_differentiable DistanceVecNeighborFinder(args...)
@non_differentiable allneighbors(args...)

function ChainRulesCore.rrule(T::Type{<:SVector}, vs::Number...)
    Y = T(vs...)
    function SVector_pullback(Ȳ)
        return NoTangent(), Ȳ...
    end
    return Y, SVector_pullback
end

function ChainRulesCore.rrule(T::Type{<:Atom}, vs...)
    Y = T(vs...)
    function Atom_pullback(Ȳ)
        return NoTangent(), Ȳ.index, Ȳ.charge, Ȳ.mass, Ȳ.σ, Ȳ.ϵ
    end
    return Y, Atom_pullback
end

function ChainRulesCore.rrule(::typeof(sparsevec), is, vs, l)
    Y = sparsevec(is, vs, l)
    function sparsevec_pullback(Ȳ)
        return NoTangent(), collect(1:length(Ȳ)), Ȳ, length(Ȳ)
    end
    return Y, sparsevec_pullback
end

function ChainRulesCore.rrule(::typeof(accumulateadd), x)
    Y = accumulateadd(x)
    function accumulateadd_pullback(Ȳ)
        return NoTangent(), reverse(accumulate(+, reverse(Ȳ)))
    end
    return Y, accumulateadd_pullback
end

function ChainRulesCore.rrule(::typeof(unsafe_getindex), arr, inds)
    Y = unsafe_getindex(arr, inds)
    function unsafe_getindex_pullback(Ȳ)
        dx = Zygote._zero(arr, eltype(Ȳ))
        dxv = @view dx[inds]
        dxv .= Zygote.accum.(dxv, Zygote._droplike(Ȳ, dxv))
        return NoTangent(), Zygote._project(x, dx), nothing
    end
    return Y, unsafe_getindex_pullback
end

# Only when on the GPU
function ChainRulesCore.rrule(::typeof(getindices_i), arr::CuArray, neighbors)
    Y = getindices_i(arr, neighbors)
    @views @inbounds function getindices_i_pullback(Ȳ)
        return NoTangent(), accumulate_bounds(Ȳ, neighbors.atom_bounds_i), nothing
    end
    return Y, getindices_i_pullback
end

function ChainRulesCore.rrule(::typeof(getindices_j), arr::CuArray, neighbors)
    Y = getindices_j(arr, neighbors)
    @views @inbounds function getindices_j_pullback(Ȳ)
        return NoTangent(), accumulate_bounds(Ȳ[neighbors.sortperm_j], neighbors.atom_bounds_j), nothing
    end
    return Y, getindices_j_pullback
end
