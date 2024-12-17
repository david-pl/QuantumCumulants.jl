import Base: sum

struct Sum{T,I,M} <: QTerm
    term::T
    index::I
    metadata::M
end

const Σ = Sum

# Symbolics interface
SymbolicUtils.operation(::Sum) = Sum
SymbolicUtils.arguments(s::Sum) = [s.term, s.index]
SymbolicUtils.maketerm(::Type{<:Sum}, ::typeof(Sum), args, metadata) = Sum(args; metadata)

# has_index
"""
    has_index(expr, i::Index)

Check if an expression has a specific index.

"""
has_index(x, i::Index) = false
has_index(v::IndexedVariable, i::Index) = isequal(v.ind, i)
has_index(op::IndexedOperator, i::Index) = isequal(op.ind, i)

# TODO: specialization for QAdd, QMul, etc.
function has_index(t::QTerm, i::Index)
    for arg in SymbolicUtils.arguments(t)
        if has_index(arg, i)
            return true
        end
    end
    return false
end

has_index(s::Sum, i::Index) = isequal(s.index, i) || has_index(s.term, i)

function has_index(t::SymbolicUtils.Term, i::Index)
    for arg in SymbolicUtils.arguments(t)
        if has_index(arg, i)
            return true
        end
    end
    return false
end



# Construction of sums with QSyms -- order should be QSym < QMul < Sum < QAdd
Sum(a::QSym, index::Index) = index.range * a

function Sum(a::T, index::I) where {T<:IndexedOperator, I<:Index} 
    if !has_index(a, index)
        return index.range * a
    end
    return Sum(a, index, nothing)
end


function Sum(t::T, index::I) where {T<:QMul, I<:Index}
    if !has_index(t, index)
        return index.range * t
    end

    if !has_index(t, t.args_nc)
        return Sum(*(t.args_c...), index) * *(t.args_nc...)
    end

    return Sum(t, index, nothing)
end

function Sum(t::QAdd, index::Index)
    args = [Sum(arg, index) for arg in SymbolicUtils.arguments(t)]
    return +(args...)
end

# Basic algebra
function +(s1::Sum, s2::Sum)
    return QAdd([s1, s2])
end
function +(s1::QNumber, s2::Sum)
    return QAdd([s1, s2])
end
function +(s1::Sum, s2::QNumber)
    return QAdd([s1, s2])
end

function *(s1::Sum, s2::Sum)
    if isequal(s1.index, s2.index)
        new_index = Index(s2.index.hilbert, gensym(s2.index.name), s2.index.range, s2.index.aon)
        return s1 * change_index(s2, s2.index, new_index)
    end

    return Sum(Sum(s1.term * s2.term, s2.index), s1.index)
end

function *(a::QSym, s::Sum)
    return Sum(a * s.term, s.index)
end
function *(s::Sum, a::QSym)
    return Sum(s.term * a, s.index)
end

function *(a::IndexedOperator, s::Sum)
    if isequal(a.index, s.index)
        new_index = Index(a.index.hilb, gensym(a.index.name), a.index.range, a.index.aon)
        return change_index(a, a.index, new_index) * s
    end
    return Sum(a * s.term, s.index)
end
function *(s::Sum, a::IndexedOperator)
    if isequal(a.index, s.index)
        new_index = Index(a.index.hilb, gensym(a.index.name), a.index.range, a.index.aon)
        return s * change_index(a, a.index, new_index)
    end
    return Sum(s.term * a, s.index)
end

function *(s::Sum, t::QTerm)
    if has_index(t, s.index)
        new_index = Index(s.index.hilb, gensym(s.index.name), s.index.range, s.index.aon)
        return s * change_index(t, s.index, new_index)
    end
    return Sum(s.term * t, s.index)
end
function *(t::QTerm, s::Sum)
    if has_index(t, s.index)
        new_index = Index(s.index.hilb, gensym(s.index.name), s.index.range, s.index.aon)
        return change_index(t, s.index, new_index) * s
    end
    return Sum(t * s.term, s.index)
end

function *(v::SNuN, s::Sum)
    if has_index(v, s.index)
        new_index = Index(s.index.hilb, gensym(s.index.name), s.index.range, s.index.aon)
        return change_index(v, s.index, new_index) * s
    end
    return Sum(v * s.term, s.index)
end
*(s::Sum, v::SNuN) = v * s

# averaging
average(s::Sum) = Sum(average(s.term), s.index)