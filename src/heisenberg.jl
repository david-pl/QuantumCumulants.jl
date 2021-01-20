"""
    heisenberg(ops::Vector,H::AbstractOperator)
    heisenberg(op::AbstractOperator,H::AbstractOperator)

Compute a set of Heisenberg equations of the operators in `ops`
under the Hamiltonian `H`.
"""
function heisenberg(a::Vector,H; multithread=false)
    #TODO ClusterSpace - copy from other heisenberg when finished
    if multithread
        lhs = Vector{AbstractOperator}(undef, length(a))
        rhs = Vector{AbstractOperator}(undef, length(a))
        Threads.@threads for i=1:length(a)
            lhs[i] = simplify_operators(a[i])
            rhs[i] = simplify_operators(1.0im*commutator(H,lhs[i];simplify=false))
        end
    else
        lhs = simplify_operators.(a)
        rhs = simplify_operators.([1.0im*commutator(H,a1;simplify=false) for a1=lhs])
    end
    return DifferentialEquation(lhs,rhs,H,AbstractOperator[],Number[])
end
heisenberg(a::AbstractOperator,args...;kwargs...) = heisenberg([a],args...;kwargs...)

"""
    heisenberg(ops::Vector,H::AbstractOperator,J::Vector;
            Jdagger::Vector=adjoint.(J),rates=ones(length(J)))
    heisenberg(op::AbstractOperator,H::AbstractOperator,J::Vector;
            Jdagger::Vector=adjoint.(J),rates=ones(length(J)))

Compute the set of equations for the operators in `ops` under the Hamiltonian
`H` and with loss operators contained in `J`. The resulting equation is
equivalent to the Quantum-Langevin equation where noise is neglected.

# Arguments
*`ops::Vector{<:AbstractVector}`: The operators of which the equations are to be computed.
*`H::AbstractOperatr`: The Hamiltonian describing the reversible dynamics of the
    system.
*`J::Vector{<:AbstractOperator}`: A vector containing the collapse operators of
    the system. A term of the form
    ``\\sum_i J_i^\\dagger O J_i - \\frac{1}{2}\\left(J_i^\\dagger J_i O + OJ_i^\\dagger J_i\\right)``
    is added to the Heisenberg equation.

# Optional argumentes
*`Jdagger::Vector=adjoint.(J)`: Vector containing the hermitian conjugates of
    the collapse operators.
*`rates=ones(length(J))`: Decay rates corresponding to the collapse operators in `J`.
"""
function heisenberg(a::Vector,H,J_;Jdagger::Vector=adjoint.(Iterators.flatten(J_)),rates_=ones(length(J_)),multithread=false)
    if any(isa.(J, Vector))
        J = []; rates = []
        for it=1:length(J_)
            push!(J, J_[it]...); push!(rates, [rates_[it] for i=1:length(J_[it])]...)
        end
    else
        J = J_; rates = rates_
    end
    lhs = Vector{AbstractOperator}(undef, length(a))
    rhs = Vector{AbstractOperator}(undef, length(a))
    if multithread
        Threads.@threads for i=1:length(a)
            lhs[i] = simplify_operators(a[i])
            rhs[i] = simplify_operators(1.0im*commutator(H,lhs[i];simplify=false) + _master_lindblad(lhs[i],J,Jdagger,rates))
        end
    else
        for i=1:length(a)
            lhs[i] = simplify_operators(a[i])
            rhs[i] = simplify_operators(1.0im*commutator(H,lhs[i];simplify=false) + _master_lindblad(lhs[i],J,Jdagger,rates))
        end
    end
    he = DifferentialEquation(lhs,rhs,H,J,rates)
    # Clusters
    h = hilbert(lhs[1])
    any(isa.(h.spaces, FockSpace)) && (return scale(he))
    return he
end
function _master_lindblad(a_,J,Jdagger,rates)
    if isa(rates,Vector)
        da_diss = sum(0.5*rates[i]*(Jdagger[i]*commutator(a_,J[i];simplify=false) + commutator(Jdagger[i],a_;simplify=false)*J[i]) for i=1:length(J))
    elseif isa(rates,Matrix)
        da_diss = sum(0.5*rates[i,j]*(Jdagger[i]*commutator(a_,J[j];simplify=false) + commutator(Jdagger[i],a_;simplify=false)*J[j]) for i=1:length(J), j=1:length(J))
    else
        error("Unknown rates type!")
    end
    return simplify_operators(da_diss)
end

"""
    commutator(a,b; simplify=true, kwargs...)

Computes the commutator `a*b - b*a` of `a` and `b`. If `simplify` is `true`, the
result is simplified using the [`simplify_operators`](@ref) function. Further
keyword arguments are passed to simplification.
"""
function commutator(a::AbstractOperator,b::AbstractOperator; simplify=true, kwargs...)
    # Check on which subspaces each of the operators act
    a_on = acts_on(a)
    b_on = acts_on(b)
    inds = intersect(a_on,b_on)
    isempty(inds) && return zero(a)
    if simplify
        return simplify_operators(a*b + -1*b*a; kwargs...)
    else
        return a*b + -1*b*a
    end
end

# Specialized methods for addition using linearity
function commutator(a::OperatorTerm{<:typeof(+)},b::AbstractOperator; simplify=true, kwargs...)
    args = Any[]
    for arg in a.arguments
        c = commutator(arg,b; simplify=simplify, kwargs...)
        iszero(c) || push!(args, c)
    end
    isempty(args) && return zero(a)
    out = +(args...)
    if simplify
        return simplify_operators(out; kwargs...)
    else
        return out
    end
end
function commutator(a::AbstractOperator,b::OperatorTerm{<:typeof(+)}; simplify=true, kwargs...)
    args = Any[]
    for arg in b.arguments
        c = commutator(a,arg; simplify=simplify, kwargs...)
        iszero(c) || push!(args, c)
    end
    isempty(args) && return zero(a)
    out = +(args...)
    if simplify
        return simplify_operators(out; kwargs...)
    else
        return out
    end
end
function commutator(a::OperatorTerm{<:typeof(+)},b::OperatorTerm{<:typeof(+)}; simplify=true, kwargs...)
    args = Any[]
    for a_arg in a.arguments
        for b_arg in b.arguments
            c = commutator(a_arg,b_arg; simplify=simplify, kwargs...)
            iszero(c) || push!(args, c)
        end
    end
    isempty(args) && return zero(a)
    out = +(args...)
    if simplify
        return simplify_operators(out; kwargs...)
    else
        return out
    end
end
