## 11/28/2022
## Implement the holographic quantum circuit for the kicked Ising model
## Test first two sites which is built based on the corner case

using ITensors
using ITensors.HDF5
using ITensors: orthocenter, sites, copy, complex
using Base: Float64
using Base: product
using Random

ITensors.disable_warn_order()


# Sample and reset one two-site MPS
function sample(m::MPS, j::Int)
    mpsLength = length(m)

    # Move the orthogonality center of the MPS to site j
    orthogonalize!(m, j)
    if orthocenter(m) != j
        error("sample: MPS m must have orthocenter(m) == 1")
    end
    # Check the normalization of the MPS
    if abs(1.0 - norm(m[j])) > 1E-8
        error("sample: MPS is not normalized, norm=$(norm(m[1]))")
    end

    projn0_Matrix = [1  0; 0  0]
    projnLower_Matrix = [0  0; 1  0]
    # @show projectionMatrix, sizeof(projectionMatrix)
    result = zeros(Int, 2)
    A = m[j]
    # @show A
    # @show m[j]

    for ind in j:j+1
        tmpS = siteind(m, ind)
        d = dim(tmpS)
        pdisc = 0.0
        r = rand()

        n = 1
        An = ITensor()
        pn = 0.0

        while n <= d
            # @show A
            # @show m[ind]
            projn = ITensor(tmpS)
            projn[tmpS => n] = 1.0
            An = A * dag(projn)
            pn = real(scalar(dag(An) * An))
            pdisc += pn

            (r < pdisc) && break
            n += 1
        end
        result[ind - j + 1] = n
        # @show result[ind - j + 1]
        # @show An

        if ind < mpsLength
            A = m[ind + 1] * An
            A *= (1. / sqrt(pn))
        end

        # @show m[ind]
        if n - 1 < 1E-8
            # tmpReset = ITensor(projn0_Matrix, s, s')
            tmpReset = ITensor(projn0_Matrix, tmpS, tmpS')
        else
            # tmpReset = ITensor(projnLower_Matrix, s, s')
            tmpReset = ITensor(projnLower_Matrix, tmpS, tmpS')
        end
        m[ind] *= tmpReset
        noprime!(m[ind])
        # @show m[ind]
    end
    println("")
    println("")
    println("Measure sites $j and $(j+1)!")
    println("")
    println("")
    return result
end 

# # Implement a long-range two-site gate
# function long_range_gate(tmp_s, position_index::Int)
#     s1 = tmp_s[1]
#     s2 = tmp_s[position_index]
    
#     # Notice the difference in coefficients due to the system is half-infinite chain
#     hj = ?? * op("Sz", s1) * op("Sz", s2) + 2 * h * op("Sz", s1) * op("Id", s2) + h * op("Id", s1) * op("Sz", s2)
#     Gj = exp(-1.0im * tau / 2 * hj)
#     # @show hj
#     # @show Gj
#     @show inds(Gj)

#     # Benchmark gate that employs swap operations
#     benchmarkGate = ITensor[]
#     push!(benchmarkGate, Gj)
    
#     # for ind in 1 : n
#     #     @show s[ind], s[ind]'
#     # end

#     U, S, V = svd(Gj, (tmp_s[1], tmp_s[1]'))
#     @show norm(U*S*V - Gj)
#     # @show S
#     # @show U
#     # @show V

#     # Absorb the S matrix into the U matrix on the left
#     U = U * S
#     # @show U

#     # Make a vector to store the bond indices
#     bondIndices = Vector(undef, n - 1)

#     # Grab the bond indices of U and V matrices
#     if hastags(inds(U)[3], "Link,v") != true           # The original tag of this index of U matrix should be "Link,u".  But we absorbed S matrix into the U matrix.
#         error("SVD: fail to grab the bond indice of matrix U by its tag!")
#     else 
#         replacetags!(U, "Link,v", "i1")
#     end
#     # @show U
#     bondIndices[1] = inds(U)[3]

#     if hastags(inds(V)[3], "Link,v") != true
#         error("SVD: fail to grab the bond indice of matrix V by its tag!")
#     else
#         replacetags!(V, "Link,v", "i" * string(n))
#     end
#     # @show V
#     @show position_index
#     bondIndices[position_index - 1] = inds(V)[3]
#     # @show (bondIndices[1], bondIndices[n - 1])

    

#     #####################################################################################################################################
#     # Construct the long-range two-site gate as an MPO
#     longrangeGate = MPO(n)
#     longrangeGate[1] = U

#     for ind in 2 : position_index - 1
#         # Set up site indices
#         if abs(ind - (position_index - 1)) > 1E-8
#             bondString = "i" * string(ind)
#             bondIndices[ind] = Index(4, bondString)
#         end

#         # Make the identity tensor
#         # @show s[ind], s[ind]'
#         tmpIdentity = delta(s[ind], s[ind]') * delta(bondIndices[ind - 1], bondIndices[ind]) 
#         longrangeGate[ind] = tmpIdentity

#         # @show sizeof(longrangeGate)
#         # @show longrangeGate
#     end

#     @show typeof(V), V
#     longrangeGate[position_index] = V
#     # @show sizeof(longrangeGate)
#     # @show longrangeGate
#     @show typeof(longrangeGate), typeof(benchmarkGate)
#     #####################################################################################################################################
# end

let 
    N = 8
    cutoff = 1E-8
    tau = 1.0
    h = 0.2                                     # an integrability-breaking longitudinal field h 
    
    # Set up the circuit (e.g. number of sites, \Delta\tau used for the TEBD procedure) based on
    floquet_time = 3.0                                        # floquet time = ???? * circuit_time
    circuit_time = 2 * Int(floquet_time)
    # circuit_time = Int(floquet_time / (0.5 * tau))
    @show floquet_time, circuit_time
    num_measurements = 2

    # Implement a long-range two-site gate
    function long_range_gate(tmp_s, position_index::Int)
        s1 = tmp_s[1]
        s2 = tmp_s[position_index]
        
        # Notice the difference in coefficients due to the system is half-infinite chain
        # hj = ?? * op("Sz", s1) * op("Sz", s2) + 2 * h * op("Sz", s1) * op("Id", s2) + h * op("Id", s1) * op("Sz", s2)
        hj = ?? * op("Sz", s1) * op("Sz", s2) + h * op("Sz", s1) * op("Id", s2) + h * op("Id", s1) * op("Sz", s2)
        Gj = exp(-1.0im * tau / 2 * hj)
        # @show hj
        # @show Gj
        # @show inds(Gj)

        # Benchmark gate that employs swap operations
        benchmarkGate = ITensor[]
        push!(benchmarkGate, Gj)
        
        # for ind in 1 : n
        #     @show s[ind], s[ind]'
        # end

        U, S, V = svd(Gj, (tmp_s[1], tmp_s[1]'))
        # @show norm(U*S*V - Gj)
        # @show S
        # @show U
        # @show V

        # Absorb the S matrix into the U matrix on the left
        U = U * S
        # @show U

        # Make a vector to store the bond indices
        bondIndices = Vector(undef, position_index - 1)

        # Grab the bond indices of U and V matrices
        if hastags(inds(U)[3], "Link,v") != true           # The original tag of this index of U matrix should be "Link,u".  But we absorbed S matrix into the U matrix.
            error("SVD: fail to grab the bond indice of matrix U by its tag!")
        else 
            replacetags!(U, "Link,v", "i1")
        end
        # @show U
        bondIndices[1] = inds(U)[3]

        if hastags(inds(V)[3], "Link,v") != true
            error("SVD: fail to grab the bond indice of matrix V by its tag!")
        else
            replacetags!(V, "Link,v", "i" * string(position_index))
        end
        # @show V
        # @show position_index
        bondIndices[position_index - 1] = inds(V)[3]
        # @show (bondIndices[1], bondIndices[n - 1])

        

        #####################################################################################################################################
        # Construct the long-range two-site gate as an MPO
        longrangeGate = MPO(position_index)
        longrangeGate[1] = U

        for ind in 2 : position_index - 1
            # Set up site indices
            if abs(ind - (position_index - 1)) > 1E-8
                bondString = "i" * string(ind)
                bondIndices[ind] = Index(4, bondString)
            end

            # Make the identity tensor
            # @show s[ind], s[ind]'
            tmpIdentity = delta(s[ind], s[ind]') * delta(bondIndices[ind - 1], bondIndices[ind]) 
            longrangeGate[ind] = tmpIdentity

            # @show sizeof(longrangeGate)
            # @show longrangeGate
        end

        # @show typeof(V), V
        longrangeGate[position_index] = V
        # @show sizeof(longrangeGate)
        # @show longrangeGate
        # @show typeof(longrangeGate), typeof(benchmarkGate)
        #####################################################################################################################################
        return longrangeGate
    end
    
    
    ###############################################################################################################################
    ## Constructing gates used in the TEBD algorithm
    ###############################################################################################################################
    # # Construct a two-site gate that implements Ising interaction and longitudinal field
    # gates = ITensor[]
    # for ind in 1:(N - 1)
    #     s1 = s[ind]
    #     s2 = s[ind + 1]

    #     if (ind - 1 < 1E-8)
    #         tmp1 = 2 
    #         tmp2 = 1
    #     elseif (abs(ind - (N - 1)) < 1E-8)
    #         tmp1 = 1
    #         tmp2 = 2
    #     else
    #         tmp1 = 1
    #         tmp2 = 1
    #     end

    #     println("")
    #     println("Coefficients are $(tmp1) and $(tmp2)")
    #     println("Site index is $(ind) and the conditional sentence is $(ind - (N - 1))")
    #     println("")

    #     hj = ?? * op("Sz", s1) * op("Sz", s2) + tmp1 * h * op("Sz", s1) * op("Id", s2) + tmp2 * h * op("Id", s1) * op("Sz", s2)
    #     Gj = exp(-1.0im * tau / 2 * hj)
    #     push!(gates, Gj)
    # end
    # # Append the reverse gates (N -1, N), (N - 2, N - 1), (N - 3, N - 2) ...
    # append!(gates, reverse(gates))


    # # Construct the transverse field as the kicked gate
    # ampo = OpSum()
    # for ind in 1 : N
    #     ampo += ??/2, "Sx", ind
    # end
    # H??? = MPO(ampo, s)
    # Hamiltonian??? = H???[1]
    # for ind in 2 : N
    #     Hamiltonian??? *= H???[ind]
    # end
    # expHamiltoinian??? = exp(-1.0im * Hamiltonian???)
    

    #################################################################################################################################################
    # Construct the holographic quantum dynamics simulation (holoQUADS) circuit
    #################################################################################################################################################
    # Construct time evolution for one floquet time step
    # function timeEvolutionCorner(numGates :: Int, numSites :: Int, tmp_gates)
    #     # In the corner case, two-site gates are applied to site 1 --> site N
    #     # gates = ITensor[]
    #     if 2 * numGates >= numSites
    #         error("the number of time evolution gates is larger than what can be accommodated based on the number of sites!")
    #     end

    #     for ind??? in 1:2
    #         for ind??? in 1:numGates
    #             parity = (ind??? - 1) % 2
    #             s1 = s[2 * ind??? - parity]; @show inds(s1)
    #             s2 = s[2 * ind??? + 1 - parity]; @show inds(s2)

    #             if 2 * ind??? - parity - 1 < 1E-8
    #                 coeff??? = 2
    #                 coeff??? = 1
    #             else
    #                 coeff??? = 1
    #                 coeff??? = 1
    #             end

    #             hj = (?? * op("Sz", s1) * op("Sz", s2) + coeff??? * h * op("Sz", s1) * op("Id", s2) + coeff??? * h * op("Id", s1) * op("Sz", s2))
    #             Gj = exp(-1.0im * tau / 2 * hj)
    #             push!(tmp_gates, Gj)
    #         end
    #     end
    #     # return gates
    # end


    # Construct time evolution for one floquet time step
    function time_evolution_corner(num_gates :: Int, parity :: Int)
        # Time evolution using TEBD for the corner case
        gates = ITensor[]

        for ind??? in 1 : num_gates
            s1 = s[2 * ind??? - parity]
            s2 = s[2 * ind??? + 1 - parity]
            @show inds(s1)
            @show inds(s2)

            if 2 * ind??? - parity - 1 < 1E-8
                coeff??? = 2
                coeff??? = 1
            else
                coeff??? = 1
                coeff??? = 1
            end

            # hj = (?? * op("Sz", s1) * op("Sz", s2) + coeff??? * h * op("Sz", s1) * op("Id", s2) + coeff??? * h * op("Id", s1) * op("Sz", s2))
            # Gj = exp(-1.0im * tau / 2 * hj)
            hj = coeff??? * h * op("Sz", s1) * op("Id", s2) + coeff??? * h * op("Id", s1) * op("Sz", s2)
            Gj = exp(-1.0im * tau * hj)
            push!(gates, Gj)
        end
        return gates
    end

    
    function time_evolution(initialPosition :: Int, numSites :: Int, tmp_sites)
        # General time evolution using TEBD
        gates = ITensor[]
        if initialPosition - 1 < 1E-8
            tmpGate = long_range_gate(tmp_sites, numSites)
            # push!(gates, tmpGate)
            return tmpGate
        else
            # if initialPosition - 2 < 1E-8
            #     coeff??? = 1
            #     coeff??? = 2
            # else
            #     coeff??? = 1
            #     coeff??? = 1
            # end
            s1 = tmp_sites[initialPosition]
            s2 = tmp_sites[initialPosition - 1]
            # hj = (?? * op("Sz", s1) * op("Sz", s2) + coeff??? * h * op("Sz", s1) * op("Id", s2) + coeff??? * h * op("Id", s1) * op("Sz", s2))
            hj = (?? * op("Sz", s1) * op("Sz", s2) + h * op("Sz", s1) * op("Id", s2) + h * op("Id", s1) * op("Sz", s2))
            Gj = exp(-1.0im * tau / 2 * hj)
            push!(gates, Gj)
        end
        return gates
    end

    # Make an array of 'site' indices && quantum numbers are not conserved due to the transverse fields
    s = siteinds("S=1/2", N; conserve_qns = false)

    # # Construct the kicked gate that applies transverse Ising fields at integer time using single-site gate
    # kick_gate = ITensor[]
    # for ind in 1 : N
    #     s1 = s[ind]
    #     hamilt = ?? / 2 * op("Sx", s1)
    #     tmpG = exp(-1.0im * hamilt)
    #     push!(kick_gate, tmpG)
    # end
    
    # Construct the kicked gate that applies transverse Ising fields at integer time using single-site gate
    function build_kick_gates(starting_index :: Int, ending_index :: Int)
        kick_gate = ITensor[]
        for ind in starting_index : ending_index
            s1 = s[ind]; @show ind
            hamilt = ?? / 2 * op("Sx", s1)
            tmpG = exp(-1.0im * hamilt)
            push!(kick_gate, tmpG)
        end
        return kick_gate
    end
    
    # Compute local observables e.g. Sz, Czz 
    # timeSlices = Int(floquet_time / tau) + 1; println("Total number of time slices that need to be saved is : $(timeSlices)")
    # Sx = complex(zeros(timeSlices, N))
    # Sy = complex(zeros(timeSlices, N))
    # Sz = complex(zeros(timeSlices, N))
    # Cxx = complex(zeros(timeSlices, N))
    # Czz = complex(zeros(timeSlices, N))
    # Sz = complex(zeros(num_measurements, N))
    Sz = real(zeros(num_measurements, N))

    # # Initialize the wavefunction
    # states = [isodd(n) ? "Up" : "Dn" for n = 1 : N]
    # ?? = MPS(s, states)
    # Sz??? = expect(??, "Sz"; sites = 1 : N)
    # # Random.seed!(10000)

    # ?? = productMPS(s, n -> isodd(n) ? "Up" : "Dn")
    # @show eltype(??), eltype(??[1])
    
    # # Initializa a random MPS
    # Random.seed!(200); 
    # initialization_s = siteinds("S=1/2", 8; conserve_qns = false)
    # initialization_states = [isodd(n) ? "Up" : "Dn" for n = 1 : 8]
    # initialization_?? = randomMPS(initialization_s, initialization_states, linkdims = 2)
    # ?? = initialization_??[1 : N]
    # # @show maxlinkdim(??)

    Random.seed!(200)
    states = [isodd(n) ? "Up" : "Dn" for n = 1 : N]
    # states = [isodd(n) ? "X+" : "X-" for n = 1 : N]
    ?? = randomMPS(s, states, linkdims = 2)
    Sz??? = expect(??, "Sz"; sites = 1 : N)                    # Take measurements of the initial random MPS
    Random.seed!(10000)

    Sx = complex(zeros(Int(floquet_time), N))
    Sy = complex(zeros(Int(floquet_time), N))
    Sz = complex(zeros(Int(floquet_time), N))

    for measure_ind in 1 : num_measurements
        println("")
        println("")
        println("############################################################################")
        println("#########           PERFORMING MEASUREMENTS LOOP #$measure_ind           ##############")
        println("############################################################################")
        println("")
        println("")

        # Compute the overlap between the original and time evolved wavefunctions
        ??_copy = deepcopy(??)
        ??_overlap = Complex{Float64}[]
        
        @time for ind in 1 : circuit_time
            tmp_overlap = abs(inner(??, ??_copy))
            println("The inner product is: $tmp_overlap")
            append!(??_overlap, tmp_overlap)

            # # Local observables e.g. Sx, Sz
            # tmpSx = expect(??_copy, "Sx"; sites = 1 : N); @show tmpSx; # Sx[index, :] = tmpSx
            # tmpSy = expect(??_copy, "Sy"; sites = 1 : N); @show tmpSy; # Sy[index, :] = tmpSy
            # tmpSz = expect(??_copy, "Sz"; sites = 1 : N); @show tmpSz; # Sz[index, :] = tmpSz

            # # Apply kicked gate at integer times
            # if ind % 2 == 1
            #     ??_copy = apply(kick_gate, ??_copy; cutoff)
            #     normalize!(??_copy)
            #     println("")
            #     println("")
            #     println("Applying the kicked Ising gate at time $(ind)!")
            #     tmp_overlap = abs(inner(??, ??_copy))
            #     @show tmp_overlap
            #     println("")
            #     println("")
            # end

            # Apply a sequence of two-site gates
            tmp_parity = (ind - 1) % 2
            tmp_num_gates = Int(circuit_time / 2) - floor(Int, (ind - 1) / 2) 
            print(""); @show tmp_num_gates; print("")

            # Apply kicked gate at integer times
            if ind % 2 == 1
                tmp_kick_gate = build_kick_gates(1, 2 * tmp_num_gates + 1); @show 2 * tmp_num_gates + 1
                # tmp_kick_gate = build_kick_gates(1, N)
                ??_copy = apply(tmp_kick_gate, ??_copy; cutoff)
                normalize!(??_copy)
                # ??_copy = apply(kick_gate, ??_copy; cutoff)

                println("")
                println("")
                println("Applying the kicked Ising gate at time $(ind)!")
                tmp_overlap = abs(inner(??, ??_copy))
                @show tmp_overlap
                println("")
                println("")
            end
            
            tmp_two_site_gates = ITensor[]
            tmp_two_site_gates = time_evolution_corner(tmp_num_gates, tmp_parity)
            println("")
            println("")
            @show sizeof(tmp_two_site_gates)
            println("")
            println("")
            println("Appling the Ising gate plus longitudinal fields.")
            println("")
            println("")
            # println("")
            # @show tmp_two_site_gates 
            # @show typeof(tmp_two_site_gates)
            # println("")

            # println("")
            # println("")
            # tmp_overlap = abs(inner(??, ??_copy))
            # @show tmp_overlap
            # println("")
            # println("")

            ??_copy = apply(tmp_two_site_gates, ??_copy; cutoff)
            normalize!(??_copy)

            if ind % 2 == 0
                Sx[Int(ind / 2), :] = expect(??_copy, "Sx"; sites = 1 : N)
                Sy[Int(ind / 2), :] = expect(??_copy, "Sy"; sites = 1 : N) 
                Sz[Int(ind / 2), :] = expect(??_copy, "Sz"; sites = 1 : N) 
            end
        end

        println("")
        println("")
        tmp_overlap = abs(inner(??, ??_copy))
        @show tmp_overlap
        println("")
        Sz[measure_ind, 1:2] = sample(??_copy, 1)
        println("")
        tmp_overlap = abs(inner(??, ??_copy))
        @show tmp_overlap
        println("")
        println("")

        @time for ind??? in 1 : Int(N / 2) - 1
            gate_seeds = []
            for gate_ind in 1 : circuit_time
                tmp_ind = (2 * ind??? - gate_ind + N) % N
                if tmp_ind == 0
                    tmp_ind = N
                end
                push!(gate_seeds, tmp_ind)
            end
            println("")
            println("")
            @show gate_seeds
            println("")
            println("")

            for ind??? in 1 : circuit_time
                # tmp_overlap = abs(inner(??, ??_copy))
                # println("The inner product is: $tmp_overlap")
                # append!(??_overlap, tmp_overlap)

                # # Local observables e.g. Sx, Sz
                # tmpSx = expect(??_copy, "Sx"; sites = 1 : N); @show tmpSx; # Sx[index, :] = tmpSx
                # tmpSy = expect(??_copy, "Sy"; sites = 1 : N); @show tmpSy; # Sy[index, :] = tmpSy
                # tmpSz = expect(??_copy, "Sz"; sites = 1 : N); @show tmpSz; # Sz[index, :] = tmpSzz

                # Apply kicked gate at integer times
                if ind??? % 2 == 1
                    ??_copy = apply(kick_gate, ??_copy; cutoff)
                    normalize!(??_copy)
                    println("")
                    tmp_overlap = abs(inner(??, ??_copy))
                    @show tmp_overlap
                    println("")
                end

                # Apply a sequence of two-site gates
                # tmp_two_site_gates = ITensor[]
                tmp_two_site_gates = time_evolution(gate_seeds[ind???], N, s)
                # println("")
                # @show tmp_two_site_gates 
                # @show typeof(tmp_two_site_gates)
                # println("")

                ??_copy = apply(tmp_two_site_gates, ??_copy; cutoff)
                normalize!(??_copy)
                # println("")
                # tmp_overlap = abs(inner(??, ??_copy))
                # @show tmp_overlap
                # println("")
            end
            Sz[measure_ind, 2 * ind??? + 1 : 2 * ind??? + 2] = sample(??_copy, 2 * ind??? + 1) 
            # println("")
            # @show abs(inner(??, ??_copy))
            # println("")
        end

        # @time for ind??? in 1 : Int(N / 2) - 1
        #     gate_seeds = []
        #     for gate_ind in 1 : circuit_time
        #         tmp_ind = (2 * ind??? - gate_ind + N) % N
        #         if tmp_ind == 0
        #             tmp_ind = N
        #         end
        #         push!(gate_seeds, tmp_ind)
        #     end
        #     println("")
        #     println("")
        #     @show gate_seeds
        #     println("")
        #     println("")

        #     for ind??? in 1 : circuit_time
        #         # tmp_overlap = abs(inner(??, ??_copy))
        #         # println("The inner product is: $tmp_overlap")
        #         # append!(??_overlap, tmp_overlap)

        #         # # Local observables e.g. Sx, Sz
        #         # tmpSx = expect(??_copy, "Sx"; sites = 1 : N); @show tmpSx; # Sx[index, :] = tmpSx
        #         # tmpSy = expect(??_copy, "Sy"; sites = 1 : N); @show tmpSy; # Sy[index, :] = tmpSy
        #         # tmpSz = expect(??_copy, "Sz"; sites = 1 : N); @show tmpSz; # Sz[index, :] = tmpSzz

        #         # Apply kicked gate at integer times
        #         if ind??? % 2 == 1
        #             ??_copy = apply(kick_gate, ??_copy; cutoff)
        #             normalize!(??_copy)
        #             println("")
        #             tmp_overlap = abs(inner(??, ??_copy))
        #             @show tmp_overlap
        #             println("")
        #         end

        #         # Apply a sequence of two-site gates
        #         # tmp_two_site_gates = ITensor[]
        #         tmp_two_site_gates = time_evolution(gate_seeds[ind???], N, s)
        #         # println("")
        #         # @show tmp_two_site_gates 
        #         # @show typeof(tmp_two_site_gates)
        #         # println("")

        #         ??_copy = apply(tmp_two_site_gates, ??_copy; cutoff)
        #         normalize!(??_copy)
        #         # println("")
        #         # tmp_overlap = abs(inner(??, ??_copy))
        #         # @show tmp_overlap
        #         # println("")
        #     end
        #     Sz[measure_ind, 2 * ind??? + 1 : 2 * ind??? + 2] = sample(??_copy, 2 * ind??? + 1) 
        #     # println("")
        #     # @show abs(inner(??, ??_copy))
        #     # println("")
        # end
    end
    
    # @show typeof(Sz)
    # @show Sz
    replace!(Sz, 1.0 => 0.5, 2.0 => -0.5)
     

    println("################################################################################")
    println("################################################################################")
    println("Information of the initial random MPS")
    @show Sz???
    println("################################################################################")
    println("################################################################################")
    
    # Store data in hdf5 file
    file = h5open("Data/holoQUADS_Circuit_N$(N)_h$(h)_T$(floquet_time)_Measure$(num_measurements)_Rotations_Only_Random_TESTING.h5", "w")
    # write(file, "Sz", Sz)
    write(file, "Initial Sz", Sz???)
    write(file, "Sx_wavefucntion", Sx)
    write(file, "Sy_wavefunction", Sy)
    write(file, "Sz_wavefunction", Sz)
    # write(file, "Cxx", Cxx)
    # write(file, "Czz", Czz)
    # write(file, "Wavefunction Overlap", ??_overlap)
    close(file)

    return
end  