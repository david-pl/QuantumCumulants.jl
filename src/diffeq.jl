# Relevant parts of ODESystem interface
MTK.independent_variable(me::MeanfieldEquations) = me.iv
MTK.states(me::MeanfieldEquations) = me.states

function MTK.equations(me::MeanfieldEquations)
    # Get the MTK variables
    varmap = me.varmap
    vs = MTK.states(me)
    vhash = map(hash, vs)

    # Substitute conjugate variables by explicit conj
    vs′ = map(_conj, vs)
    vs′hash = map(hash, vs′)
    i = 1
    while i <= length(vs′)
        if vs′hash[i] ∈ vhash
            deleteat!(vs′, i)
            deleteat!(vs′hash, i)
        else
            i += 1
        end
    end
    rhs = [substitute_conj(eq.rhs, vs′, vs′hash) for eq∈me.equations]

    # Substitute to MTK variables on rhs
    subs = Dict(varmap)
    rhs = [substitute(r, subs) for r∈rhs]
    vs_mtk = getindex.(varmap, 2)

    # Return equations
    t = MTK.independent_variable(me)
    D = MTK.Differential(t)
    return [Symbolics.Equation(D(vs_mtk[i]), rhs[i]) for i=1:length(vs)]
end

# Substitute conjugate variables
function substitute_conj(t,vs′,vs′hash)
    if SymbolicUtils.istree(t)
        if t isa Average
            if hash(t)∈vs′hash
                t′ = _conj(t)
                return conj(t′)
            else
                return t
            end
        else
            _f = x->substitute_conj(x,vs′,vs′hash)
            args = map(_f, SymbolicUtils.arguments(t))
            return SymbolicUtils.similarterm(t, SymbolicUtils.operation(t), args)
        end
    else
        return t
    end
end

# Conversion to ODESystem
MTK.isparameter(::SymbolicUtils.Sym{<:Parameter}) = true

function MTK.ODESystem(me::MeanfieldEquations, iv=me.iv; kwargs...)
    eqs = MTK.equations(me)
    return MTK.ODESystem(eqs, iv; kwargs...)
end
