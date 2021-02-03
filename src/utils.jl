"""
    find_missing(rhs::Vector, vs::Vector, vs_adj=get_conj(vs), ps=[])

For a list of expressions contained in `rhs`, check whether all occurring symbols
are contained either in the variables given in `vs`. If a list of parameters `ps`
is provided, parameters that do not occur in the list `ps` are also added to the list.
Returns a list of missing symbols.
"""
function find_missing(rhs::Vector, vs::Vector; vs_adj::Vector=get_conj(vs), ps=[])
    missed = []
    for e=rhs
        append!(missed,get_symbolics(e))
    end
    unique!(missed)
    if isempty(ps)
        filter!(!SymbolicUtils.sym_isa(Parameter), missed)
    end
    filter!(x->!(_in(x, vs) || _in(x, ps) || _in(x, vs_adj)),missed)
    isempty(ps) || (ps_adj = get_conj(ps); filter!(x -> !_in(x,ps_adj), missed))
    return missed
end
function find_missing(de::HeisenbergEquation; kwargs...)
    find_missing(de.rhs, de.lhs; kwargs...)
end

"""
    _in(x, itr)

Same as `Base.in` but uses `isequal` instead of `==`.
"""
function _in(x, itr)
    anymissing = false
    for y in itr
        v = isequal(y, x)
        if ismissing(v)
            anymissing = true
        elseif v
            return true
        end
    end
    return anymissing ? missing : false
end

"""
    get_symbolics(ex)

Find all symbolic numbers occuring in `ex`.
"""
get_symbolics(x::Number) = []
function get_symbolics(t::SymbolicUtils.Symbolic)
    if SymbolicUtils.istree(t)
        if SymbolicUtils.is_operation(average)(t)
            return [t]
        else
            syms = []
            for arg in SymbolicUtils.arguments(t)
                append!(syms, get_symbolics(arg))
            end
            return unique(syms)
        end
    else
        return [t]
    end
end

"""
    complete(de::HeisenbergEquation)

From a set of differential equation of averages, find all averages that are missing
and derive the corresponding equations of motion.
"""
function complete(de::HeisenbergEquation;kwargs...)
    rhs_, lhs_ = complete(de.rhs,de.lhs,de.hamiltonian,de.jumps,de.rates;kwargs...)
    return HeisenbergEquation(lhs_,rhs_,de.hamiltonian,de.jumps,de.rates)
end
function complete(rhs::Vector, vs::Vector, H, J, rates; order=nothing, filter_func=nothing, mix_choice=maximum, kwargs...)
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
    filter!(SymbolicUtils.sym_isa(Average),missed)
    isnothing(filter_func) || filter!(filter_func, missed) # User-defined filter
    while !isempty(missed)
        ops = [SymbolicUtils.arguments(m)[1] for m in missed]
        he = isempty(J) ? heisenberg(ops,H; kwargs...) : heisenberg(ops,H,J;rates=rates, kwargs...)
        he_avg = average(he,order_;mix_choice=mix_choice, kwargs...)
        rhs_ = [rhs_;he_avg.rhs]
        vs_ = [vs_;he_avg.lhs]
        missed = unique_ops(find_missing(rhs_,vs_))
        filter!(SymbolicUtils.sym_isa(Average),missed)
        isnothing(filter_func) || filter!(filter_func, missed) # User-defined filter
    end

    if !isnothing(filter_func)
        # Find missing values that are filtered by the custom filter function,
        # but still occur on the RHS; set those to 0
        missed = unique_ops(find_missing(rhs_, vs_))
        filter!(SymbolicUtils.sym_isa(Average),missed)
        filter!(!filter_func, missed)
        missed_adj = map(get_adjoint, missed)
        subs = Dict(vcat(missed, missed_adj) .=> 0)
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

    all_ops = QNumber[]
    for i=1:order
        for c in combinations(ops, i)
            push!(all_ops, prod(c))
        end
    end

    # Simplify and remove non-operators iteratively
    ops_1 = map(qsimplify, all_ops)
    ops_2 = all_ops
    while !isequal(ops_1,ops_2)
        ops_2 = QNumber[]
        for op in ops_1
            append!(ops_2, _get_operators(op))
        end
        ops_1 = map(qsimplify, ops_2)
    end

    return unique_ops(ops_2)
end
find_operators(op::QNumber,args...) = find_operators(hilbert(op),args...)

"""
    hilbert(::QNumber)

Return the Hilbert space of the operator.
"""
hilbert(op::QSym) = op.hilbert
hilbert(t::QTerm) = hilbert(t.arguments[findfirst(x->isa(x,QNumber), t.arguments)])

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
    get_operators(::QNumber)

Return a list of all [`QSym`](@ref) in an expression.
"""
get_operators(x) = _get_operators(x)
function get_operators(t::QTerm{<:typeof(*)})
    ops = QNumber[]
    for arg in t.arguments
        append!(ops, get_operators(arg))
    end
    return ops
end

_get_operators(::Number) = []
_get_operators(op::QSym) = [op]
_get_operators(op::QTerm{<:typeof(^)}) = [op]
function _get_operators(op::QTerm{<:typeof(*)})
    args = QNumber[]
    for arg in op.arguments
        append!(args, _get_operators(arg))
    end
    isempty(args) && return args
    return [*(args...)]
end
function _get_operators(t::QTerm)
    ops = QNumber[]
    for arg in t.arguments
        append!(ops, _get_operators(arg))
    end
    return ops
end

"""
    unique_ops(ops)

For a given list of operators, return only unique ones taking into account
their adjoints.
"""
function unique_ops(ops)
    seen = eltype(ops)[]
    ops_adj = get_adjoint(ops)
    for (op,op′) in zip(ops,ops_adj)
        if !(_in(op, seen) || _in(op′, seen))
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
function get_solution(avg::SymbolicUtils.Term{<:Average},sol,he::HeisenbergEquation)
    idx = findfirst(isequal(avg),he.lhs)
    if isnothing(idx)
        avg_ = get_adjoint(avg)
        idx_ = findfirst(isequal(avg_),he.lhs)
        isnothing(idx_) && error("Could not find solution for $avg !")
        return [conj(u[idx_]) for u in sol.u]
    else
        return [u[idx] for u in sol.u]
    end
end

# Internal functions
function get_conj(v::SymbolicUtils.Symbolic)
    v_ = conj(v)
    rw = conj_rewriter()
    return rw(v_)
end
function get_conj(v)
    v_ = map(conj, v)
    rw = conj_rewriter()
    return map(rw, v_)
end

get_adjoint(op::QNumber) = adjoint(op)
get_adjoint(x) = get_conj(x)
get_adjoint(v::Vector{<:QNumber}) = map(adjoint, v)

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
_to_expression(op::QSym) = op.name
_to_expression(op::Create) = :(dagger($(op.name)))
_to_expression(op::Transition) = :(Transition($(op.name),$(op.i),$(op.j)) )
_to_expression(t::QTerm) = :( $(Symbol(t.f))($(_to_expression.(t.arguments)...)) )
_to_expression(p::Parameter) = p.name
function _to_expression(s::SymbolicUtils.Symbolic)
    if SymbolicUtils.istree(s)
        f = SymbolicUtils.operation(s)
        args = map(_to_expression, SymbolicUtils.arguments(s))
        return :( $(Symbol(f))($(args...)) )
    else
        return nameof(s)
    end
end
