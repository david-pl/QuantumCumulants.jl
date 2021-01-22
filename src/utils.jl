"""
    find_missing(rhs::Vector, vs::Vector, vs_adj=adjoint.(vs), ps=[])

For a list of expressions contained in `rhs`, check whether all occurring symbols
are contained either in the variables given in `vs`. If a list of parameters `ps`
is provided, parameters that do not occur in the list `ps` are also added to the list.
Returns a list of missing symbols.
"""
function find_missing(rhs::Vector{<:Number}, vs::Vector{<:Number}; vs_adj::Vector=adjoint.(vs), ps=[])
    missed = Number[]
    for e=rhs
        append!(missed,get_symbolics(e))
    end
    unique!(missed)
    if isempty(ps)
        filter!(x->!isa(x,Parameter), missed)
    end
    filter!(x->!(x∈vs || x∈ps || x∈vs_adj),missed)
    isempty(ps) || (ps_adj = adjoint.(ps); filter!(x -> !(x∈ps_adj), missed))
    return missed
end
function find_missing(de::AbstractEquation{<:Number,<:Number}; kwargs...)
    find_missing(de.rhs, de.lhs; kwargs...)
end

"""
    get_symbolics(ex)

Find all symbolic numbers occuring in `ex`.
"""
get_symbolics(x::Number) = SymbolicNumber[]
get_symbolics(x::SymbolicNumber) = [x]
function get_symbolics(t::NumberTerm)
    syms = SymbolicNumber[]
    for arg in t.arguments
        append!(syms, get_symbolics(arg))
    end
    return unique(syms)
end

"""
    complete(de::DifferentialEquation)

From a set of differential equation of averages, find all averages that are missing
and derive the corresponding equations of motion.
"""
function complete(de::DifferentialEquation{<:Number,<:Number};kwargs...)
    rhs_, lhs_ = complete(de.rhs,de.lhs,de.hamiltonian,de.jumps,de.rates;kwargs...)
    return DifferentialEquation(lhs_,rhs_,de.hamiltonian,de.jumps,de.rates)
end
function complete(rhs::Vector{<:Number}, vs::Vector{<:Number}, H, J, rates; order=nothing, filter_func=nothing, mix_choice=maximum, kwargs...)
    order_lhs = maximum(get_order.(vs))
    order_rhs = maximum(get_order.(rhs))
    if order isa Nothing
        order_ = max(order_lhs, order_rhs)
    else
        order_ = order
    end
    maximum(order_) >= order_lhs || error("Cannot form cumulant expansion of derivative; you may want to use a higher order!")

    vs_ = copy(vs)
    rhs_ = [cumulant_expansion(r, order_) for r in rhs]
    missed = unique_ops(find_missing(rhs_, vs_))
    filter!(x->isa(x,Average),missed)
    isnothing(filter_func) || filter!(filter_func, missed) # User-defined filter
    while !isempty(missed)
        ops = getfield.(missed, :operator)
        he = isempty(J) ? heisenberg(ops,H; kwargs...) : heisenberg(ops,H,J;rates=rates, kwargs...)
        he_avg = average(he,order_;mix_choice=mix_choice, kwargs...)
        rhs_ = [rhs_;he_avg.rhs]
        vs_ = [vs_;he_avg.lhs]
        missed = unique_ops(find_missing(rhs_,vs_))
        filter!(x->isa(x,Average),missed)
        isnothing(filter_func) || filter!(filter_func, missed) # User-defined filter
    end

    if !isnothing(filter_func)
        # Find missing values that are filtered by the custom filter function,
        # but still occur on the RHS; set those to 0
        missed = unique_ops(find_missing(rhs_, vs_))
        filter!(x->isa(x,Average),missed)
        filter!(!filter_func, missed)
        subs = Dict(missed .=> 0)
        rhs_ = [substitute(r, subs) for r in rhs_]
    end
    return rhs_, vs_
end

"""
    find_operators(::HilbertSpace, order; names=nothing)

Find all operators that fully define a system up to the given `order`.
"""
function find_operators(h::HilbertSpace, order::Int; names=nothing, kwargs...)
    if names isa Nothing && (unique(typeof.(h.spaces))!=typeof.(h.spaces))
        alph = 'a':'z'
        names_ = Symbol.(alph[1:length(h.spaces)])
    else
        names_ = names
    end
    fund_ops = fundamental_operators(h;names=names_, kwargs...)
    fund_ops = unique([fund_ops;adjoint.(fund_ops)])
    ops = copy(fund_ops)
    for i=2:order
        ops = [ops;fund_ops]
    end

    all_ops = AbstractOperator[]
    for i=1:order
        for c in combinations(ops, i)
            push!(all_ops, prod(c))
        end
    end

    # Simplify and remove non-operators iteratively
    ops_1 = simplify_operators.(all_ops)
    ops_2 = all_ops
    while ops_1 != ops_2
        ops_2 = AbstractOperator[]
        for op in ops_1
            append!(ops_2, _get_operators(op))
        end
        ops_1 = simplify_operators.(ops_2)
    end

    return unique_ops(ops_2)
end
find_operators(op::AbstractOperator,args...) = find_operators(hilbert(op),args...)

"""
    hilbert(::AbstractOperator)

Return the Hilbert space of the operator.
"""
hilbert(op::BasicOperator) = op.hilbert
hilbert(t::OperatorTerm) = hilbert(t.arguments[findfirst(x->isa(x,AbstractOperator), t.arguments)])
hilbert(avg::Average) = hilbert(avg.operator)

"""
    fundamental_operators(::HilbertSpace)

Return all fundamental operators for a given Hilbertspace. For example,
a [`FockSpace`](@ref) only has one fundamental operator, `Destroy`.
"""
function fundamental_operators(h::FockSpace,aon::Int=1;names=nothing)
    name = names isa Nothing ? :a : names[aon]
    a = Destroy(h,name)
    return [a]
end
function fundamental_operators(h::NLevelSpace,aon::Int=1;names=nothing)
    sigmas = Transition[]
    lvls = levels(h)
    name = names isa Nothing ? :σ : names[aon]
    for i=1:length(lvls)
        for j=i:length(lvls)
            (i==j) && lvls[i]==ground_state(h) && continue
            s = Transition(h,name,lvls[i],lvls[j])
            push!(sigmas,s)
        end
    end
    return sigmas
end
function fundamental_operators(h::ProductSpace;kwargs...)
    ops = []
    for i=1:length(h.spaces)
        ops_ = fundamental_operators(h.spaces[i],i;kwargs...)
        ops_ = [embed(h,o,i) for o in ops_]
        append!(ops,ops_)
    end
    return ops
end


"""
    get_operators(::AbstractOperator)

Return a list of all [`BasicOperator`](@ref) in an expression.
"""
get_operators(x) = _get_operators(x)
function get_operators(t::OperatorTerm{<:typeof(*)})
    ops = AbstractOperator[]
    for arg in t.arguments
        append!(ops, get_operators(arg))
    end
    return ops
end

_get_operators(::Number) = []
_get_operators(op::BasicOperator) = [op]
_get_operators(op::OperatorTerm{<:typeof(^)}) = [op]
function _get_operators(op::OperatorTerm{<:typeof(*)})
    args = AbstractOperator[]
    for arg in op.arguments
        append!(args, _get_operators(arg))
    end
    isempty(args) && return args
    return [*(args...)]
end
function _get_operators(t::OperatorTerm)
    ops = AbstractOperator[]
    for arg in t.arguments
        append!(ops, _get_operators(arg))
    end
    return ops
end
_get_operators(avg::Average) = _get_operators(avg.operator)

"""
    unique_ops(ops)

For a given list of operators, return only unique ones taking into account
their adjoints.
"""
function unique_ops(ops)
    seen = eltype(ops)[]
    for op in ops
        if !(op in seen || op' in seen)
            push!(seen, op)
        end
    end
    return seen
end

"""
    get_solution(avg,sol,he)

Find the numerical solution of the average value `avg` stored in the `ODESolution`
`sol` corresponding to the solution of the equations given by `he`.
"""
function get_solution(avg::Average,sol,he::AbstractEquation)
    isa(he, ScaleDifferentialEquation) && (avg = substitute(avg, he.dictionary))
    idx = findfirst(isequal(avg),he.lhs)
    if isnothing(idx)
        idx_ = findfirst(isequal(avg'),he.lhs)
        isnothing(idx_) && error("Could not find solution for $avg !")
        return [conj(u[idx_]) for u in sol.u]
    else
        return [u[idx] for u in sol.u]
    end
end
get_solution(op::AbstractOperator,sol,he::AbstractEquation) = get_solution(average(op),sol,he)

_to_expression(x::Number) = x
function _to_expression(x::Complex) # For brackets when using latexify
    iszero(x) && return x
    if iszero(real(x))
        return :( $(imag(x))*im )
    elseif iszero(imag(x))
        return real(x)
    else
        return :( $(real(x)) + $(imag(x))*im )
    end
end
_to_expression(op::BasicOperator) = op.name
_to_expression(op::Create) = :(dagger($(op.name)))
_to_expression(op::Transition) = :(Transition($(op.name),$(op.i),$(op.j)) )
_to_expression(t::Union{OperatorTerm,NumberTerm}) = :( $(Symbol(t.f))($(_to_expression.(t.arguments)...)) )
_to_expression(p::Parameter) = p.name
function _to_expression(avg::Average)
    ex = _to_expression(avg.operator)
    return :(AVERAGE($ex))
end
