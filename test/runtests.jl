using Molly
using Aqua
import BioStructures # Imported to avoid clashing names
using CUDA

using Base.Threads
using DelimitedFiles
using Statistics
using Test

@warn "This file does not include all the tests for Molly.jl due to CI time limits, " *
        "see the test directory for more"

run_visualize_tests = false # GLMakie doesn't work on CI

if run_visualize_tests
    using GLMakie
    @info "The visualization tests will be run as run_visualize_tests is set to true"
else
    @warn "The visualization tests will not be run as run_visualize_tests is set to false"
end

run_parallel_tests = nthreads() > 1
if run_parallel_tests
    @info "The parallel tests will be run as Julia is running on $(nthreads()) threads"
else
    @warn "The parallel tests will not be run as Julia is running on 1 thread"
end

run_gpu_tests = CUDA.functional()
if run_gpu_tests
    @info "The GPU tests will be run as a CUDA-enabled device is available"
else
    @warn "The GPU tests will not be run as a CUDA-enabled device is not available"
end

CUDA.allowscalar(false) # Check that we never do scalar indexing on the GPU

# Some failures due to dependencies but there is an unbound args error
Aqua.test_all(Molly; ambiguities=(recursive=false), unbound_args=false, undefined_exports=false)

data_dir = normpath(@__DIR__, "..", "data")

temp_fp_pdb = tempname(cleanup=true) * ".pdb"
temp_fp_viz = tempname(cleanup=true) * ".mp4"

@testset "Interactions" begin
    c1 = SVector(1.0, 1.0, 1.0)u"nm"
    c2 = SVector(1.3, 1.0, 1.0)u"nm"
    c3 = SVector(1.4, 1.0, 1.0)u"nm"
    a1 = Atom(charge=1.0, σ=0.3u"nm", ϵ=0.2u"kJ * mol^-1")
    box_size = SVector(2.0, 2.0, 2.0)u"nm"
    coords = [c1, c2, c3]
    s = System(atoms=[a1, a1, a1], coords=coords, box_size=box_size)

    @test isapprox(force(LennardJones(), c1, c2, a1, a1, box_size),
                    SVector(16.0, 0.0, 0.0)u"kJ * mol^-1 * nm^-1",
                    atol=1e-9u"kJ * mol^-1 * nm^-1")
    @test isapprox(force(LennardJones(), c1, c3, a1, a1, box_size),
                    SVector(-1.375509739, 0.0, 0.0)u"kJ * mol^-1 * nm^-1",
                    atol=1e-9u"kJ * mol^-1 * nm^-1")
    @test isapprox(potential_energy(LennardJones(), s, 1, 2),
                    0.0u"kJ * mol^-1",
                    atol=1e-9u"kJ * mol^-1")
    @test isapprox(potential_energy(LennardJones(), s, 1, 3),
                    -0.1170417309u"kJ * mol^-1",
                    atol=1e-9u"kJ * mol^-1")

    @test isapprox(force(Coulomb(), c1, c2, a1, a1, box_size),
                    SVector(1543.727311, 0.0, 0.0)u"kJ * mol^-1 * nm^-1",
                    atol=1e-5u"kJ * mol^-1 * nm^-1")
    @test isapprox(force(Coulomb(), c1, c3, a1, a1, box_size),
                    SVector(868.3466125, 0.0, 0.0)u"kJ * mol^-1 * nm^-1",
                    atol=1e-5u"kJ * mol^-1 * nm^-1")
    @test isapprox(potential_energy(Coulomb(), s, 1, 2),
                    463.1181933u"kJ * mol^-1",
                    atol=1e-5u"kJ * mol^-1")
    @test isapprox(potential_energy(Coulomb(), s, 1, 3),
                    347.338645u"kJ * mol^-1",
                    atol=1e-5u"kJ * mol^-1")
    
    b1 = HarmonicBond(b0=0.2u"nm", kb=300_000.0u"kJ * mol^-1 * nm^-2")
    b2 = HarmonicBond(b0=0.6u"nm", kb=100_000.0u"kJ * mol^-1 * nm^-2")
    fs = force(b1, coords[1], coords[2], box_size)
    @test isapprox(fs.f1, SVector(30000.0, 0.0, 0.0)u"kJ * mol^-1 * nm^-1",
                    atol=1e-9u"kJ * mol^-1 * nm^-1")
    @test isapprox(fs.f2, SVector(-30000.0, 0.0, 0.0)u"kJ * mol^-1 * nm^-1",
                    atol=1e-9u"kJ * mol^-1 * nm^-1")
    fs = force(b2, coords[1], coords[3], box_size)
    @test isapprox(fs.f1, SVector(-20000.0, 0.0, 0.0)u"kJ * mol^-1 * nm^-1",
                    atol=1e-9u"kJ * mol^-1 * nm^-1")
    @test isapprox(fs.f2, SVector(20000.0, 0.0, 0.0)u"kJ * mol^-1 * nm^-1",
                    atol=1e-9u"kJ * mol^-1 * nm^-1")
    @test isapprox(potential_energy(b1, coords[1], coords[2], box_size),
                    1500.0u"kJ * mol^-1", atol=1e-9u"kJ * mol^-1")
    @test isapprox(potential_energy(b2, coords[1], coords[3], box_size),
                    2000.0u"kJ * mol^-1", atol=1e-9u"kJ * mol^-1")
end

@testset "Spatial" begin
    @test vector1D(4.0, 6.0, 10.0) ==  2.0
    @test vector1D(1.0, 9.0, 10.0) == -2.0
    @test vector1D(6.0, 4.0, 10.0) == -2.0
    @test vector1D(9.0, 1.0, 10.0) ==  2.0

    @test vector1D(4.0u"nm", 6.0u"nm", 10.0u"nm") ==  2.0u"nm"
    @test vector1D(1.0u"m" , 9.0u"m" , 10.0u"m" ) == -2.0u"m"
    @test_throws Unitful.DimensionError vector1D(6.0u"nm", 4.0u"nm", 10.0)

    @test vector(SVector(4.0, 1.0, 6.0), SVector(6.0, 9.0, 4.0),
                    SVector(10.0, 10.0, 10.0)) == SVector(2.0, -2.0, -2.0)
    @test vector(SVector(4.0, 1.0, 1.0), SVector(6.0, 4.0, 3.0),
                    SVector(10.0, 5.0, 3.5)) == SVector(2.0, -2.0, -1.5)
    @test vector(SVector(4.0, 1.0), SVector(6.0, 9.0),
                    SVector(10.0, 10.0)) == SVector(2.0, -2.0)
    @test vector(SVector(4.0, 1.0, 6.0)u"nm", SVector(6.0, 9.0, 4.0)u"nm",
                    SVector(10.0, 10.0, 10.0)u"nm") == SVector(2.0, -2.0, -2.0)u"nm"

    @test wrapcoords(8.0 , 10.0) == 8.0
    @test wrapcoords(12.0, 10.0) == 2.0
    @test wrapcoords(-2.0, 10.0) == 8.0

    @test wrapcoords(8.0u"nm" , 10.0u"nm") == 8.0u"nm"
    @test wrapcoords(12.0u"m" , 10.0u"m" ) == 2.0u"m"
    @test_throws ErrorException wrapcoords(-2.0u"nm", 10.0)

    for neighbor_finder in (DistanceNeighborFinder, TreeNeighborFinder, CellListMapNeighborFinder)
        s = System(
            atoms=[Atom(), Atom(), Atom()],
            coords=[SVector(1.0, 1.0, 1.0)u"nm", SVector(2.0, 2.0, 2.0)u"nm",
                    SVector(5.0, 5.0, 5.0)u"nm"],
            box_size=SVector(10.0, 10.0, 10.0)u"nm",
            neighbor_finder=neighbor_finder(nb_matrix=trues(3, 3), n_steps=10, dist_cutoff=2.0u"nm"),
        )
        neighbors = find_neighbors(s, s.neighbor_finder; parallel=false)
        @test neighbors.list == [(2, 1, false)] || neighbors.list == [(1, 2, false)]
        if run_parallel_tests
            neighbors = find_neighbors(s, s.neighbor_finder; parallel=true)
            @test neighbors.list == [(2, 1, false)] || neighbors.list == [(1, 2, false)]
        end
    end

    # Test passing the box_size and coordinates as keyword arguments to CellListMapNeighborFinder
    coords = [SVector(1.0, 1.0, 1.0)u"nm", SVector(2.0, 2.0, 2.0)u"nm", SVector(5.0, 5.0, 5.0)u"nm"]
    box_size = SVector(10.0, 10.0, 10.0)u"nm"
    neighbor_finder=CellListMapNeighborFinder(
        nb_matrix=trues(3, 3), n_steps=10, x0=coords,
        unit_cell=box_size, dist_cutoff=2.0u"nm",
    )
    s = System(
        atoms=[Atom(), Atom(), Atom()],
        coords=coords, box_size=box_size,
        neighbor_finder=neighbor_finder,
    )
    neighbors = find_neighbors(s, s.neighbor_finder; parallel=false)
    @test neighbors.list == [(2, 1, false)] || neighbors.list == [(1, 2, false)]
    if run_parallel_tests
        neighbors = find_neighbors(s, s.neighbor_finder; parallel=true)
        @test neighbors.list == [(2, 1, false)] || neighbors.list == [(1, 2, false)]
    end
end

@testset "Lennard-Jones gas 2D" begin
    n_atoms = 10
    n_steps = 20_000
    temp = 298.0u"K"
    box_size = SVector(2.0, 2.0)u"nm"
    simulator = VelocityVerlet(dt=0.002u"ps", coupling=AndersenThermostat(temp, 10.0u"ps"))

    s = System(
        atoms=[Atom(charge=0.0, mass=10.0u"u", σ=0.3u"nm", ϵ=0.2u"kJ * mol^-1") for i in 1:n_atoms],
        general_inters=(LennardJones(nl_only=true),),
        coords=place_atoms(n_atoms, box_size, 0.3u"nm"; dims=2),
        velocities=[velocity(10.0u"u", temp; dims=2) .* 0.01 for i in 1:n_atoms],
        box_size=box_size,
        neighbor_finder=DistanceNeighborFinder(nb_matrix=trues(n_atoms, n_atoms), n_steps=10, dist_cutoff=2.0u"nm"),
        loggers=Dict("temp" => TemperatureLogger(100),
                     "coords" => CoordinateLogger(100; dims=2)),
    )

    show(devnull, s)

    @time simulate!(s, simulator, n_steps; parallel=false)

    final_coords = last(s.loggers["coords"].coords)
    @test all(all(c .> 0.0u"nm") for c in final_coords)
    @test all(all(c .< box_size) for c in final_coords)
    displacements(final_coords, box_size)
    distances(final_coords, box_size)
    rdf(final_coords, box_size)

    run_visualize_tests && visualize(s.loggers["coords"], box_size, temp_fp_viz)
end

@testset "Lennard-Jones gas" begin
    n_atoms = 100
    n_steps = 20_000
    temp = 298.0u"K"
    box_size = SVector(2.0, 2.0, 2.0)u"nm"
    simulator = VelocityVerlet(dt=0.002u"ps", coupling=AndersenThermostat(temp, 10.0u"ps"))
    parallel_list = run_parallel_tests ? (false, true) : (false,)

    for parallel in parallel_list
        s = System(
            atoms=[Atom(charge=0.0, mass=10.0u"u", σ=0.3u"nm", ϵ=0.2u"kJ * mol^-1") for i in 1:n_atoms],
            atoms_data=[AtomData(atom_name="AR", res_number=i, res_name="AR") for i in 1:n_atoms],
            general_inters=(LennardJones(nl_only=true),),
            coords=place_atoms(n_atoms, box_size, 0.3u"nm"),
            velocities=[velocity(10.0u"u", temp) .* 0.01 for i in 1:n_atoms],
            box_size=box_size,
            neighbor_finder=DistanceNeighborFinder(nb_matrix=trues(n_atoms, n_atoms), n_steps=10, dist_cutoff=2.0u"nm"),
            loggers=Dict("temp"   => TemperatureLogger(100),
                         "coords" => CoordinateLogger(100),
                         "vels"   => VelocityLogger(100),
                         "energy" => EnergyLogger(100),
                         "writer" => StructureWriter(100, temp_fp_pdb)),
        )

        nf_tree = TreeNeighborFinder(nb_matrix=trues(n_atoms, n_atoms), n_steps=10, dist_cutoff=2.0u"nm")
        neighbors = find_neighbors(s, s.neighbor_finder; parallel=parallel)
        neighbors_tree = find_neighbors(s, nf_tree; parallel=parallel)
        @test neighbors.list == neighbors_tree.list

        @time simulate!(s, simulator, n_steps; parallel=parallel)

        final_coords = last(s.loggers["coords"].coords)
        @test all(all(c .> 0.0u"nm") for c in final_coords)
        @test all(all(c .< box_size) for c in final_coords)
        displacements(final_coords, box_size)
        distances(final_coords, box_size)
        rdf(final_coords, box_size)

        traj = read(temp_fp_pdb, BioStructures.PDB)
        rm(temp_fp_pdb)
        @test BioStructures.countmodels(traj) == 200
        @test BioStructures.countatoms(first(traj)) == 100

        run_visualize_tests && visualize(s.loggers["coords"], box_size, temp_fp_viz)
    end
end

@testset "Lennard-Jones gas velocity-free" begin
    n_atoms = 100
    n_steps = 20_000
    box_size = SVector(2.0, 2.0, 2.0)u"nm"
    coords = place_atoms(n_atoms, box_size, 0.3u"nm")
    simulator = StormerVerlet(dt=0.002u"ps")

    s = System(
        atoms=[Atom(charge=0.0, mass=10.0u"u", σ=0.3u"nm", ϵ=0.2u"kJ * mol^-1") for i in 1:n_atoms],
        general_inters=(LennardJones(nl_only=true),),
        coords=coords,
        velocities=[c .+ 0.01 .* rand(SVector{3})u"nm" for c in coords],
        box_size=box_size,
        neighbor_finder=DistanceNeighborFinder(nb_matrix=trues(n_atoms, n_atoms), n_steps=10, dist_cutoff=2.0u"nm"),
        loggers=Dict("coords" => CoordinateLogger(100)),
    )

    @time simulate!(s, simulator, n_steps; parallel=false)
end

@testset "Diatomic molecules" begin
    n_atoms = 100
    n_steps = 20_000
    temp = 298.0u"K"
    box_size = SVector(2.0, 2.0, 2.0)u"nm"
    coords = place_atoms(n_atoms ÷ 2, box_size, 0.3u"nm")
    for i in 1:length(coords)
        push!(coords, coords[i] .+ [0.1, 0.0, 0.0]u"nm")
    end
    bonds = InteractionList2Atoms(collect(1:(n_atoms ÷ 2)), collect((1 + n_atoms ÷ 2):n_atoms),
                [HarmonicBond(b0=0.1u"nm", kb=300_000.0u"kJ * mol^-1 * nm^-2") for i in 1:(n_atoms ÷ 2)])
    nb_matrix = trues(n_atoms, n_atoms)
    for i in 1:(n_atoms ÷ 2)
        nb_matrix[i, i + (n_atoms ÷ 2)] = false
        nb_matrix[i + (n_atoms ÷ 2), i] = false
    end
    simulator = VelocityVerlet(dt=0.002u"ps", coupling=AndersenThermostat(temp, 10.0u"ps"))

    s = System(
        atoms=[Atom(charge=0.0, mass=10.0u"u", σ=0.3u"nm", ϵ=0.2u"kJ * mol^-1") for i in 1:n_atoms],
        general_inters=(LennardJones(nl_only=true),),
        specific_inter_lists=(bonds,),
        coords=coords,
        velocities=[velocity(10.0u"u", temp) .* 0.01 for i in 1:n_atoms],
        box_size=box_size,
        neighbor_finder=DistanceNeighborFinder(nb_matrix=trues(n_atoms, n_atoms), n_steps=10, dist_cutoff=2.0u"nm"),
        loggers=Dict("temp" => TemperatureLogger(10),
                        "coords" => CoordinateLogger(10)),
    )

    @time simulate!(s, simulator, n_steps; parallel=false)

    if run_visualize_tests
        visualize(s.loggers["coords"], box_size, temp_fp_viz;
                    connections=[(i, i + (n_atoms ÷ 2)) for i in 1:(n_atoms ÷ 2)],
                    trails=2)
    end
end

@testset "Peptide" begin
    n_steps = 100
    temp = 298.0u"K"
    atoms, atoms_data, specific_inter_lists, general_inters, neighbor_finder, coords, box_size = readinputs(
                joinpath(data_dir, "5XER", "gmx_top_ff.top"),
                joinpath(data_dir, "5XER", "gmx_coords.gro"))
    simulator = VelocityVerlet(dt=0.0002u"ps", coupling=AndersenThermostat(temp, 10.0u"ps"))

    true_n_atoms = 5191
    @test length(atoms) == true_n_atoms
    @test length(coords) == true_n_atoms
    @test size(neighbor_finder.nb_matrix) == (true_n_atoms, true_n_atoms)
    @test size(neighbor_finder.matrix_14) == (true_n_atoms, true_n_atoms)
    @test length(general_inters) == 2
    @test length(specific_inter_lists) == 3
    @test box_size == SVector(3.7146, 3.7146, 3.7146)u"nm"
    show(devnull, first(atoms))

    s = System(
        atoms=atoms,
        atoms_data=atoms_data,
        general_inters=general_inters,
        specific_inter_lists=specific_inter_lists,
        coords=coords,
        velocities=[velocity(a.mass, temp) .* 0.01 for a in atoms],
        box_size=box_size,
        neighbor_finder=neighbor_finder,
        loggers=Dict("temp" => TemperatureLogger(10),
                        "coords" => CoordinateLogger(10),
                        "energy" => EnergyLogger(10),
                        "writer" => StructureWriter(10, temp_fp_pdb)),
    )

    @time simulate!(s, simulator, n_steps; parallel=false)

    traj = read(temp_fp_pdb, BioStructures.PDB)
    rm(temp_fp_pdb)
    @test BioStructures.countmodels(traj) == 10
    @test BioStructures.countatoms(first(traj)) == 5191
end

@testset "Float32" begin
    n_steps = 100
    temp = 298.0f0u"K"
    atoms, atoms_data, specific_inter_lists, general_inters, neighbor_finder, coords, box_size = readinputs(
                Float32,
                joinpath(data_dir, "5XER", "gmx_top_ff.top"),
                joinpath(data_dir, "5XER", "gmx_coords.gro"))
    simulator = VelocityVerlet(dt=0.0002f0u"ps", coupling=AndersenThermostat(temp, 10.0f0u"ps"))

    s = System(
        atoms=atoms,
        general_inters=general_inters,
        specific_inter_lists=specific_inter_lists,
        coords=coords,
        velocities=[velocity(a.mass, Float32(temp)) .* 0.01f0 for a in atoms],
        box_size=box_size,
        neighbor_finder=neighbor_finder,
        loggers=Dict("temp" => TemperatureLogger(typeof(1.0f0u"K"), 10),
                        "coords" => CoordinateLogger(typeof(1.0f0u"nm"), 10),
                        "energy" => EnergyLogger(typeof(1.0f0u"kJ * mol^-1"), 10)),
    )

    @time simulate!(s, simulator, n_steps; parallel=false)
end

@testset "General interactions" begin
    n_atoms = 100
    n_steps = 20_000
    temp = 298.0u"K"
    box_size = SVector(2.0, 2.0, 2.0)u"nm"
    G = 10.0u"kJ * nm * u^-2 * mol^-1"
    simulator = VelocityVerlet(dt=0.002u"ps", coupling=AndersenThermostat(temp, 10.0u"ps"))
    general_inter_types = (
        LennardJones(nl_only=true), LennardJones(nl_only=false),
        LennardJones(cutoff=DistanceCutoff(1.0u"nm"), nl_only=true),
        LennardJones(cutoff=ShiftedPotentialCutoff(1.0u"nm"), nl_only=true),
        LennardJones(cutoff=ShiftedForceCutoff(1.0u"nm"), nl_only=true),
        SoftSphere(nl_only=true), SoftSphere(nl_only=false),
        Mie(m=5, n=10, nl_only=true), Mie(m=5, n=10, nl_only=false),
        Coulomb(nl_only=true), Coulomb(nl_only=false),
        CoulombReactionField(dist_cutoff=1.0u"nm", nl_only=true),
        CoulombReactionField(dist_cutoff=1.0u"nm", nl_only=false),
        Gravity(G=G, nl_only=true), Gravity(G=G, nl_only=false),
    )

    @testset "$gi" for gi in general_inter_types
        if gi.nl_only
            neighbor_finder = DistanceNeighborFinder(nb_matrix=trues(n_atoms, n_atoms), n_steps=10,
                                                        dist_cutoff=1.5u"nm")
        else
            neighbor_finder = NoNeighborFinder()
        end

        s = System(
            atoms=[Atom(charge=i % 2 == 0 ? -1.0 : 1.0, mass=10.0u"u", σ=0.2u"nm",
                        ϵ=0.2u"kJ * mol^-1") for i in 1:n_atoms],
            general_inters=(gi,),
            coords=place_atoms(n_atoms, box_size, 0.2u"nm"),
            velocities=[velocity(10.0u"u", temp) .* 0.01 for i in 1:n_atoms],
            box_size=box_size,
            neighbor_finder=neighbor_finder,
            loggers=Dict("temp" => TemperatureLogger(100),
                         "coords" => CoordinateLogger(100),
                         "energy" => EnergyLogger(100)),
        )

        @time simulate!(s, simulator, n_steps)
    end
end

@testset "Units" begin
    n_atoms = 100
    n_steps = 2_000 # Does diverge for longer simulations or higher velocities
    temp = 298.0u"K"
    box_size = SVector(2.0, 2.0, 2.0)u"nm"
    coords = place_atoms(n_atoms, box_size, 0.3u"nm")
    velocities = [velocity(10.0u"u", temp) .* 0.01 for i in 1:n_atoms]
    simulator = VelocityVerlet(dt=0.002u"ps")
    simulator_nounits = VelocityVerlet(dt=0.002)

    s = System(
        atoms=[Atom(charge=0.0, mass=10.0u"u", σ=0.3u"nm", ϵ=0.2u"kJ * mol^-1") for i in 1:n_atoms],
        general_inters=(LennardJones(nl_only=true),),
        coords=coords,
        velocities=velocities,
        box_size=box_size,
        neighbor_finder=DistanceNeighborFinder(nb_matrix=trues(n_atoms, n_atoms), n_steps=10, dist_cutoff=2.0u"nm"),
        loggers=Dict("temp" => TemperatureLogger(100),
                     "coords" => CoordinateLogger(100),
                     "energy" => EnergyLogger(100)),
    )

    s_nounits = System(
        atoms=[Atom(charge=0.0, mass=10.0, σ=0.3, ϵ=0.2) for i in 1:n_atoms],
        general_inters=(LennardJones(nl_only=true),),
        coords=ustripvec.(coords),
        velocities=ustripvec.(velocities),
        box_size=ustrip.(box_size),
        neighbor_finder=DistanceNeighborFinder(nb_matrix=trues(n_atoms, n_atoms), n_steps=10, dist_cutoff=2.0),
        loggers=Dict("temp" => TemperatureLogger(Float64, 100),
                     "coords" => CoordinateLogger(Float64, 100),
                     "energy" => EnergyLogger(Float64, 100)),
        force_unit=NoUnits,
        energy_unit=NoUnits,
    )

    neighbors = find_neighbors(s, s.neighbor_finder; parallel=false)
    neighbors_nounits = find_neighbors(s_nounits, s_nounits.neighbor_finder; parallel=false)
    accel_diff = ustripvec.(accelerations(s, neighbors)) .- accelerations(s_nounits, neighbors_nounits)
    @test iszero(accel_diff)

    simulate!(s, simulator, n_steps; parallel=false)
    simulate!(s_nounits, simulator_nounits, n_steps; parallel=false)

    coords_diff = ustripvec.(s.loggers["coords"].coords[end]) .- s_nounits.loggers["coords"].coords[end]
    @test median([maximum(abs.(c)) for c in coords_diff]) < 1e-8

    final_energy = s.loggers["energy"].energies[end]
    final_energy_nounits = s_nounits.loggers["energy"].energies[end]
    @test isapprox(ustrip(final_energy), final_energy_nounits, atol=5e-4)
end

@testset "Different implementations" begin
    n_atoms = 400
    atom_mass = 10.0u"u"
    box_size = SVector(6.0, 6.0, 6.0)u"nm"
    temp = 1.0u"K"
    starting_coords = place_diatomics(n_atoms ÷ 2, box_size, 0.2u"nm", 0.2u"nm")
    starting_velocities = [velocity(atom_mass, temp) for i in 1:n_atoms]
    starting_coords_f32 = [Float32.(c) for c in starting_coords]
    starting_velocities_f32 = [Float32.(c) for c in starting_velocities]

    function runsim(nl::Bool, parallel::Bool, gpu_diff_safe::Bool, f32::Bool, gpu::Bool)
        n_atoms = 400
        n_steps = 200
        atom_mass = f32 ? 10.0f0u"u" : 10.0u"u"
        box_size = f32 ? SVector(6.0f0, 6.0f0, 6.0f0)u"nm" : SVector(6.0, 6.0, 6.0)u"nm"
        simulator = VelocityVerlet(dt=f32 ? 0.02f0u"ps" : 0.02u"ps")
        b0 = f32 ? 0.2f0u"nm" : 0.2u"nm"
        kb = f32 ? 10_000.0f0u"kJ * mol^-1 * nm^-2" : 10_000.0u"kJ * mol^-1 * nm^-2"
        bonds = [HarmonicBond(b0=b0, kb=kb) for i in 1:(n_atoms ÷ 2)]
        specific_inter_lists = (InteractionList2Atoms(collect(1:2:n_atoms), collect(2:2:n_atoms),
                                gpu ? cu(bonds) : bonds),)

        neighbor_finder = NoNeighborFinder()
        cutoff = DistanceCutoff(f32 ? 1.0f0u"nm" : 1.0u"nm")
        general_inters = (LennardJones(nl_only=false, cutoff=cutoff, weight_14=f32 ? 1.0f0 : 1.0),)
        if nl
            if gpu_diff_safe
                neighbor_finder = DistanceVecNeighborFinder(nb_matrix=gpu ? cu(trues(n_atoms, n_atoms)) : trues(n_atoms, n_atoms),
                                                            n_steps=10, dist_cutoff=f32 ? 1.5f0u"nm" : 1.5u"nm")
            else
                neighbor_finder = DistanceNeighborFinder(nb_matrix=trues(n_atoms, n_atoms), n_steps=10,
                                                            dist_cutoff=f32 ? 1.5f0u"nm" : 1.5u"nm")
            end
            general_inters = (LennardJones(nl_only=true, cutoff=cutoff, weight_14=f32 ? 1.0f0 : 1.0),)
        end

        if gpu
            coords = cu(deepcopy(f32 ? starting_coords_f32 : starting_coords))
            velocities = cu(deepcopy(f32 ? starting_velocities_f32 : starting_velocities))
            atoms = cu([Atom(charge=f32 ? 0.0f0 : 0.0, mass=atom_mass, σ=f32 ? 0.2f0u"nm" : 0.2u"nm",
                                ϵ=f32 ? 0.2f0u"kJ * mol^-1" : 0.2u"kJ * mol^-1") for i in 1:n_atoms])
        else
            coords = deepcopy(f32 ? starting_coords_f32 : starting_coords)
            velocities = deepcopy(f32 ? starting_velocities_f32 : starting_velocities)
            atoms = [Atom(charge=f32 ? 0.0f0 : 0.0, mass=atom_mass, σ=f32 ? 0.2f0u"nm" : 0.2u"nm",
                            ϵ=f32 ? 0.2f0u"kJ * mol^-1" : 0.2u"kJ * mol^-1") for i in 1:n_atoms]
        end

        s = System(
            atoms=atoms,
            general_inters=general_inters,
            specific_inter_lists=specific_inter_lists,
            coords=coords,
            velocities=velocities,
            box_size=box_size,
            neighbor_finder=neighbor_finder,
            gpu_diff_safe=gpu_diff_safe,
        )

        simulate!(s, simulator, n_steps; parallel=parallel)
        return s.coords
    end

    runs = [
        ("in-place"        , [false, false, false, false, false]),
        ("in-place NL"     , [true , false, false, false, false]),
        ("in-place f32"    , [false, false, false, true , false]),
        ("out-of-place"    , [false, false, true , false, false]),
        ("out-of-place NL" , [true , false, true , false, false]),
        ("out-of-place f32", [false, false, true , true , false]),
    ]
    if run_parallel_tests
        push!(runs, ("in-place parallel"   , [false, true , false, false, false]))
        push!(runs, ("in-place NL parallel", [true , true , false, false, false]))
    end
    if run_gpu_tests
        push!(runs, ("out-of-place gpu"       , [false, false, true , false, true ]))
        push!(runs, ("out-of-place gpu f32"   , [false, false, true , true , true ]))
        push!(runs, ("out-of-place gpu NL"    , [true , false, true , false, true ]))
        push!(runs, ("out-of-place gpu f32 NL", [true , false, true , true , true ]))
    end

    final_coords_ref = Array(runsim(runs[1][2]...))
    for (name, args) in runs
        final_coords = Array(runsim(args...))
        final_coords_f64 = [Float64.(c) for c in final_coords]
        diff = sum(sum(map(x -> abs.(x), final_coords_f64 .- final_coords_ref))) / (3 * n_atoms)
        # Check all simulations give the same result to within some error
        @info "$(rpad(name, 20)) - difference per coordinate $diff"
        @test diff < 1e-4u"nm"
    end
end

@testset "OpenMM protein comparison" begin
    ff_dir = joinpath(data_dir, "force_fields")
    openmm_dir = joinpath(data_dir, "openmm_6mrr")

    ff = OpenMMForceField(joinpath.(ff_dir, ["ff99SBildn.xml", "tip3p_standard.xml", "his.xml"])...)

    atoms, atoms_data, specific_inter_lists, general_inters, neighbor_finder, coords, box_size = setupsystem(
        joinpath(data_dir, "6mrr_equil.pdb"), ff)

    for inter in ("bond", "angle", "proptor", "improptor", "lj", "coul", "all")
        if inter == "all"
            gin = general_inters
        elseif inter == "lj"
            gin = general_inters[1:1]
        elseif inter == "coul"
            gin = general_inters[2:2]
        else
            gin = ()
        end

        if inter == "all"
            sils = specific_inter_lists
        elseif inter == "bond"
            sils = specific_inter_lists[1:1]
        elseif inter == "angle"
            sils = specific_inter_lists[2:2]
        elseif inter == "proptor"
            sils = specific_inter_lists[3:3]
        elseif inter == "improptor"
            sils = specific_inter_lists[4:4]
        else
            sils = ()
        end

        s = System(
            atoms=atoms,
            general_inters=gin,
            specific_inter_lists=sils,
            coords=coords,
            box_size=box_size,
            neighbor_finder=neighbor_finder,
        )
        neighbors = find_neighbors(s, s.neighbor_finder)

        forces_molly = ustripvec.(accelerations(s, neighbors; parallel=false) .* mass.(atoms))
        forces_openmm = SVector{3}.(eachrow(readdlm(joinpath(openmm_dir, "forces_$(inter)_only.txt"))))
        # All force terms on all atoms must match at some threshold
        @test !any(d -> any(abs.(d) .> 1e-6), forces_molly .- forces_openmm)

        E_molly = ustrip(potential_energy(s, neighbors))
        E_openmm = readdlm(joinpath(openmm_dir, "energy_$(inter)_only.txt"))[1]
        # Energy must match at some threshold
        @test E_molly - E_openmm < 1e-5
    end

    # Run a short simulation with all interactions
    n_steps = 100
    simulator = VelocityVerlet(dt=0.0005u"ps")
    velocities_start = SVector{3}.(eachrow(readdlm(joinpath(openmm_dir, "velocities_300K.txt"))))u"nm * ps^-1"

    s = System(
        atoms=atoms,
        general_inters=general_inters,
        specific_inter_lists=specific_inter_lists,
        coords=coords,
        velocities=deepcopy(velocities_start),
        box_size=box_size,
        neighbor_finder=neighbor_finder,
    )

    simulate!(s, simulator, n_steps; parallel=true)

    coords_openmm = SVector{3}.(eachrow(readdlm(joinpath(openmm_dir, "coordinates_$(n_steps)steps.txt"))))u"nm"
    vels_openmm   = SVector{3}.(eachrow(readdlm(joinpath(openmm_dir, "velocities_$(n_steps)steps.txt" ))))u"nm * ps^-1"

    coords_diff = s.coords .- wrapcoordsvec.(coords_openmm, (s.box_size,))
    vels_diff = s.velocities .- vels_openmm
    # Coordinates and velocities at end must match at some threshold
    @test maximum(maximum(abs.(v)) for v in coords_diff) < 1e-9u"nm"
    @test maximum(maximum(abs.(v)) for v in vels_diff  ) < 1e-6u"nm * ps^-1"

    # Test the same simulation on the GPU
    if run_gpu_tests
        atoms, atoms_data, specific_inter_lists, general_inters, neighbor_finder, coords, box_size = setupsystem(
            joinpath(data_dir, "6mrr_equil.pdb"), ff; gpu=true)
        
        s = System(
            atoms=atoms,
            general_inters=general_inters,
            specific_inter_lists=specific_inter_lists,
            coords=coords,
            velocities=cu(deepcopy(velocities_start)),
            box_size=box_size,
            neighbor_finder=neighbor_finder,
        )
    
        simulate!(s, simulator, n_steps)

        coords_diff = Array(s.coords) .- wrapcoordsvec.(coords_openmm, (s.box_size,))
        vels_diff = Array(s.velocities) .- vels_openmm
        @test maximum(maximum(abs.(v)) for v in coords_diff) < 1e-9u"nm"
        @test maximum(maximum(abs.(v)) for v in vels_diff  ) < 1e-6u"nm * ps^-1"
    end
end

@enum Status susceptible infected recovered

# Custom atom type
mutable struct Person
    i::Int
    status::Status
    mass::Float64
    σ::Float64
    ϵ::Float64
end

Molly.mass(person::Person) = person.mass

# Custom GeneralInteraction
struct SIRInteraction <: GeneralInteraction
    nl_only::Bool
    dist_infection::Float64
    prob_infection::Float64
    prob_recovery::Float64
end

# Custom Logger
struct SIRLogger <: Logger
    n_steps::Int
    fracs_sir::Vector{Vector{Float64}}
end

@testset "Agent-based modelling" begin  
    # Custom force function
    function Molly.force(inter::SIRInteraction, coord_i, coord_j, atom_i, atom_j, box_size)
        if (atom_i.status == infected && atom_j.status == susceptible) ||
                    (atom_i.status == susceptible && atom_j.status == infected)
            # Infect close people randomly
            dr = vector(coord_i, coord_j, box_size)
            r2 = sum(abs2, dr)
            if r2 < inter.dist_infection ^ 2 && rand() < inter.prob_infection
                atom_i.status = infected
                atom_j.status = infected
            end
        end
        # Workaround to obtain a self-interaction
        if atom_i.i == (atom_j.i + 1)
            # Recover randomly
            if atom_i.status == infected && rand() < inter.prob_recovery
                atom_i.status = recovered
            end
        end
        return zero(coord_i)
    end

    # Custom logging function
    function Molly.log_property!(logger::SIRLogger, s, neighbors, step_n)
        if step_n % logger.n_steps == 0
            counts_sir = [
                count(p -> p.status == susceptible, s.atoms),
                count(p -> p.status == infected   , s.atoms),
                count(p -> p.status == recovered  , s.atoms)
            ]
            push!(logger.fracs_sir, counts_sir ./ length(s))
        end
    end

    n_people = 500
    n_steps = 1_000
    box_size = SVector(10.0, 10.0)
    temp = 0.01
    n_starting = 2
    atoms = [Person(i, i <= n_starting ? infected : susceptible, 1.0, 0.1, 0.02) for i in 1:n_people]
    coords = place_atoms(n_people, box_size, 0.1; dims=2)
    velocities = [velocity(1.0, temp; dims=2) for i in 1:n_people]
    general_inters = (LennardJones=LennardJones(nl_only=true), SIR=SIRInteraction(false, 0.5, 0.06, 0.01))
    neighbor_finder = DistanceNeighborFinder(nb_matrix=trues(n_people, n_people), n_steps=10, dist_cutoff=2.0)
    simulator = VelocityVerlet(dt=0.02, coupling=AndersenThermostat(temp, 5.0))

    s = System(
        atoms=atoms,
        general_inters=general_inters,
        coords=coords,
        velocities=velocities,
        box_size=box_size,
        neighbor_finder=neighbor_finder,
        loggers=Dict("coords" => CoordinateLogger(Float64, 10; dims=2),
                        "SIR" => SIRLogger(10, [])),
        force_unit=NoUnits,
        energy_unit=NoUnits,
    )

    @time simulate!(s, simulator, n_steps; parallel=false)
end
