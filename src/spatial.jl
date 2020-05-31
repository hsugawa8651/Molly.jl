# Spatial calculations

export
    vector1D,
    vector

"Displacement between two 1D coordinate values, accounting for the bounding box."
function vector1D(c1::Real, c2::Real, box_size::Real)
    if c1 < c2
        return (c2 - c1) < (c1 - c2 + box_size) ? (c2 - c1) : (c2 - c1 - box_size)
    else
        return (c1 - c2) < (c2 - c1 + box_size) ? (c2 - c1) : (c2 - c1 + box_size)
    end
end

"Displacement between two coordinate values, accounting for the bounding box."
vector(c1, c2, box_size::Real) = vector1D.(c1, c2, box_size)