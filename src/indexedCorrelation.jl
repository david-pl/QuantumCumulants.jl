include("indexedScale.jl")

function _new_operator(op::IndexedOperator,h,aon=acts_on(op)) 
    if op.ind.hilb != h
        return IndexedOperator(Transition(h,op.op.name,op.op.i,op.op.j,aon;op.op.metadata),Index(h,op.ind.name,op.ind.rangeN))
    end
    return IndexedOperator(Transition(h,op.op.name,op.op.i,op.op.j,aon;op.op.metadata),op.ind)
end
_new_operator(nOp::NumberedOperator,h,aon=acts_on(nOp)) = NumberedOperator(Transition(h,nOp.op.name,nOp.op.i,nOp.op.j,aon;nOp.op.metadata),nOp.numb)
function _new_operator(sum::IndexedSingleSum,h,aon) 
    newSumIndex = sum.sumIndex
    if sum.sumIndex.hilb != h
        newSumIndex = Index(h,sum.sumIndex.name,sum.sumIndex.rangeN)
    end
    newSumNonEquals = Index[]
    for ind in sum.nonEqualIndices
        if ind.hilb != h
            push!(newSumNonEquals,Index(h,ind.name,ind.rangeN))
        end
    end
    return IndexedSingleSum(_new_operator(sum.term,h),newSumIndex,newSumNonEquals)
    
end
function _new_operator(sum::IndexedSingleSum,h) 
    newSumIndex = sum.sumIndex
    if sum.sumIndex.hilb != h
        newSumIndex = Index(h,sum.sumIndex.name,sum.sumIndex.rangeN)
    end
    newSumNonEquals = Index[]
    for ind in sum.nonEqualIndices
        if ind.hilb != h
            push!(newSumNonEquals,Index(h,ind.name,ind.rangeN))
        end
    end
    return IndexedSingleSum(_new_operator(sum.term,h),newSumIndex,newSumNonEquals)
    
end

function indexedCorrelationFunction(op1,op2,de0::AbstractMeanfieldEquations;
    steady_state=false, add_subscript=0,
    filter_func=nothing, mix_choice=maximum,
    iv=SymbolicUtils.Sym{Real}(:τ),
    order=nothing,
    extraIndices::Vector=[],
    simplify=true, kwargs...)
    h1 = hilbert(op1)
    h2 = _new_hilbert(hilbert(op2), acts_on(op2))
    h = h1⊗h2

    H0 = de0.hamiltonian
    J0 = de0.jumps
    Jd0 = de0.jumps_dagger

    op1_ = _new_operator(op1, h)
    op2_ = _new_operator(op2, h, length(h.spaces); add_subscript=add_subscript)
    op2_0 = _new_operator(op2, h)
    H = _new_operator(H0, h)
    J = [_new_operator(j, h) for j in J0]
    Jd = [_new_operator(j, h) for j in Jd0]
    lhs_new = [_new_operator(l, h) for l in de0.states]

    order_ = if order===nothing
        if de0.order===nothing
            de0.order
            order_lhs = maximum(get_order(l) for l in de0.states)
            order_corr = get_order(op1_*op2_)
            max(order_lhs, order_corr)
        else
            de0.order
        end
    else
        order
    end
    op_ = op1_*op2_
    @assert get_order(op_) <= order_

    varmap = make_varmap(lhs_new, de0.iv)

    de0_ = begin
        eqs = Symbolics.Equation[]
        eqs_op = Symbolics.Equation[]
        ops = map(undo_average, lhs_new)
        for i=1:length(de0.equations)
            rhs = _new_operator(de0.equations[i].rhs, h)
            rhs_op = _new_operator(de0.operator_equations[i].rhs, h)
            push!(eqs, Symbolics.Equation(lhs_new[i], rhs))
            push!(eqs_op, Symbolics.Equation(ops[i], rhs_op))
        end
        MeanfieldEquations(eqs,eqs_op,lhs_new,ops,H,J,Jd,de0.rates,de0.iv,varmap,order_)
    end

    de = indexedMeanfield([op_],H,J;Jdagger=Jd,rates=de0.rates,iv=iv,order=order_)
    indexed_complete_corr!(de, length(h.spaces), lhs_new, order_, steady_state, de0_;
            filter_func=filter_func,
            mix_choice=mix_choice,
            simplify=simplify,
            extraIndices=extraIndices,
            kwargs...)
    de = scaleME(de)
    de0_ = scaleME(de0_)
    
    return CorrelationFunction(op1_, op2_, op2_0, de0_, de, steady_state)
end

function indexed_complete_corr!(de,aon0,lhs_new,order,steady_state,de0;
        mix_choice=maximum,
        simplify=true,
        filter_func=nothing,
        extraIndices::Vector=[],
        kwargs...)
    vs = de.states
    H = de.hamiltonian
    J = de.jumps
    Jd = de.jumps_dagger
    rates = de.rates

    vhash = map(hash, vs)
    vs′ = map(_conj, vs)
    vs′hash = map(hash, vs′)
    filter!(!in(vhash), vs′hash)
    missed = find_missing(de.equations, vhash, vs′hash; get_adjoints=false)
    if order != 1
        missed = findMissingSumTerms(missed,de;extraIndices=extraIndices)
        missed = findMissingSpecialTerms(missed,de)
    end
    missed = sortByIndex.(missed)
    isnothing(filter_func) || filter!(filter_func, missed) # User-defined filter

    filter!(x -> (isNotIn(getOps(x),getOps.(de.states)) && isNotIn(getOps(sortByIndex(_conj(x))),getOps.(de.states)) 
                && isNotIn(getOps(x),getOps.(de0.states))&& isNotIn(getOps(sortByIndex(_conj(x))),getOps.(de0.states)))
                , missed)
    indices_ = nothing
    for i = 1:length(de.states)
        indices_ = getIndices(de.states[i])
        isempty(indices_) || break
    end
    sort!(indices_,by=getIndName)

    if !isempty(indices_)
        for i = 1:length(missed)
            mInd_ = getIndices(missed[i])
            isempty(mInd_) && continue
            if indices_[1] ∉ mInd_ #term on lhs does not have the initial index -> change first occuring index into that one
                missed[i] = changeIndex(missed[i],mInd_[1],indices_[1]) #replace missed ops with changed indexed ones
            end
        end
    end
    missed = unique(missed) #no duplicates

    vhash_new = map(hash, lhs_new)
    vhash_new′ = map(hash, _adjoint.(lhs_new))
    filter!(!in(vhash_new), vhash_new′)

    function _filter_aon(x) # Filter values that act only on Hilbert space representing system at time t0
        aon = acts_on(x)
        if aon0 in aon
            length(aon)==1 && return false
            return true
        end
        if steady_state # Include terms without t0-dependence only if the system is not in steady state
        h = hash(x)
            return !(h∈vhash_new || h∈vhash_new′)
        else
            return true
        end
    end
    filter!(_filter_aon, missed)
    isnothing(filter_func) || filter!(filter_func, missed) # User-defined filter

    missed = unique(missed)
    while !isempty(missed)
        ops_ = [SymbolicUtils.arguments(m)[1] for m in missed]
        me = meanfield(ops_,H,J;
            Jdagger=Jd,
            rates=rates,
            simplify=simplify,
            order=order,
            iv=de.iv,
            kwargs...)

        _append!(de, me)

        vhash_ = hash.(me.states)
        vs′hash_ = hash.(_conj.(me.states))
        append!(vhash, vhash_)
        for i=1:length(vhash_)
            vs′hash_[i] ∈ vhash_ || push!(vs′hash, vs′hash_[i])
        end

        missed = find_missing(me.equations, vhash, vs′hash; get_adjoints=false)
        if order != 1
            missed = findMissingSumTerms(missed,de;extraIndices=extraIndices)
            missed = findMissingSpecialTerms(missed,de)
        end
        missed = sortByIndex.(missed)
        isnothing(filter_func) || filter!(filter_func, missed) # User-defined filter
    
        filter!(x -> (isNotIn(getOps(x),getOps.(de.states)) && isNotIn(getOps(sortByIndex(_conj(x))),getOps.(de.states)) 
                && isNotIn(getOps(x),getOps.(de0.states))&& isNotIn(getOps(sortByIndex(_conj(x))),getOps.(de0.states)))
                , missed)
        indices_ = nothing
        for i = 1:length(de.states)
            indices_ = getIndices(de.states[i])
            isempty(indices_) || break
        end
        sort!(indices_,by=getIndName)
        if !isempty(indices_)
            for i = 1:length(missed)
                mInd_ = getIndices(missed[i])
                isempty(mInd_) && continue
                if indices_[1] ∉ mInd_ #term on lhs does not have the initial index -> change first occuring index into that one
                    missed[i] = changeIndex(missed[i],mInd_[1],indices_[1]) #replace missed ops with changed indexed ones
                end
            end
        end
        filter!(_filter_aon, missed)
        isnothing(filter_func) || filter!(filter_func, missed) # User-defined Filter
        missed = unique(missed) #no duplicates
    end

    if !isnothing(filter_func)
        # Find missing values that are filtered by the custom filter function,
        # but still occur on the RHS; set those to 0
        missed = find_missing(de.equations, vhash, vs′hash; get_adjoints=false)
        if order != 1
            missed = findMissingSumTerms(missed,de;extraIndices=extraIndices,checking=false)
            missed = findMissingSpecialTerms(missed,de)
        end
        missed = sortByIndex.(missed)
        filter!(!filter_func, missed)
        missed_adj = map(_adjoint, missed)
        subs = Dict(vcat(missed, missed_adj) .=> 0)
        for i=1:length(de.equations)
            de.equations[i] = substitute(de.equations[i], subs)
            de.states[i] = de.equations[i].lhs
        end
    end

    return de
end