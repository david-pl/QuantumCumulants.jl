import SymbolicUtils

"""
    AbstractOperator

Abstract type representing any expression involving operators.
"""
abstract type AbstractOperator end

"""
    BasicOperator <: AbstractOperator

Abstract type representing fundamental operator types.
"""
abstract type BasicOperator <: AbstractOperator end

Base.isequal(a::T,b::T) where T<:BasicOperator = isequal(a.hilbert, b.hilbert) && isequal(a.name, b.name) && isequal(a.aon, b.aon)
Base.isless(a::BasicOperator,b::BasicOperator) = a.name < b.name

"""
    OperatorTerm <: AbstractOperator

Symbolic expression tree consisting of [`AbstractOperator`](@ref) and `Number`
arguments.
"""
struct OperatorTerm{F,ARGS} <: AbstractOperator
    f::F
    arguments::ARGS
end
function Base.isequal(t1::OperatorTerm,t2::OperatorTerm)
    t1.f===t2.f || return false
    length(t1.arguments)==length(t2.arguments) || return false
    for (a,b) ∈ zip(t1.arguments, t2.arguments)
        isequal(a,b) || return false
    end
    return true
end
Base.hash(t::OperatorTerm, h::UInt) = hash(t.arguments, hash(t.f, h))

# SymbolicUtils.@number_methods(AbstractOperator, OperatorTerm(f, [a]), OperatorTerm(f, [a, b])); issue with 1/a

for f = [:+,:-,:*]
    @eval Base.$f(a::AbstractOperator,b::AbstractOperator) = (check_hilbert(a,b); OperatorTerm($f, [a,b]))
    @eval Base.$f(a::AbstractOperator,b::Number) = OperatorTerm($f, [a,b])
    @eval Base.$f(a::Number,b::AbstractOperator) = OperatorTerm($f, [a,b])
    @eval Base.$f(a::AbstractOperator,b::SymbolicUtils.Symbolic{<:Number}) = OperatorTerm($f, [a,b])
    @eval Base.$f(a::SymbolicUtils.Symbolic{<:Number},b::AbstractOperator) = OperatorTerm($f, [a,b])
end
Base.:^(a::AbstractOperator,b::Integer) = OperatorTerm(^, [a,b])
Base.:/(a::AbstractOperator,b::Number) = OperatorTerm(/, [a,b])
Base.:/(a::AbstractOperator,b::SymbolicUtils.Symbolic{<:Number}) = OperatorTerm(/, [a,b])

# Variadic methods
Base.:-(x::AbstractOperator) = -1*x
for f in [:+,:*]
    @eval Base.$f(x::AbstractOperator) = x
    @eval Base.$f(x::AbstractOperator, w::AbstractOperator...) = (check_hilbert(x,w...); OperatorTerm($f, [x;w...]))
    @eval Base.$f(x, y::AbstractOperator, w...) = (check_hilbert(x,y,w...); OperatorTerm($f, [x;y;w...]))
    @eval Base.$f(x::AbstractOperator, y::AbstractOperator, w...) = (check_hilbert(x,y,w...); OperatorTerm($f, [x;y;w...]))
end

Base.adjoint(t::OperatorTerm) = OperatorTerm(t.f, adjoint.(t.arguments))
function Base.adjoint(t::OperatorTerm{<:typeof(*)})
    args = reverse(adjoint.(t.arguments))
    is_c = iscommutative.(args)
    args_c = args[is_c]
    args_nc = sort(args[.!is_c], lt=lt_aon)
    return OperatorTerm(t.f, [args_c;args_nc])
end

# Hilbert space checks
check_hilbert(a::BasicOperator,b::BasicOperator) = (a.hilbert == b.hilbert) || error("Incompatible Hilbert spaces $(a.hilbert) and $(b.hilbert)!")
function check_hilbert(a::OperatorTerm,b::BasicOperator)
    a_ = findfirst(x->isa(x,AbstractOperator), a.arguments)
    return check_hilbert(a_,b)
end
function check_hilbert(a::BasicOperator,b::OperatorTerm)
    b_ = findfirst(x->isa(x,AbstractOperator), b.arguments)
    return check_hilbert(a,b_)
end
function check_hilbert(a::OperatorTerm,b::OperatorTerm)
    a_ = findfirst(x->isa(x,AbstractOperator), a.arguments)
    b_ = findfirst(x->isa(x,AbstractOperator), b.arguments)
    return check_hilbert(a_,b_)
end
function check_hilbert(args...)
    for i=1:length(args)-1
        check_hilbert(args[i], args[i+1])
    end
end
check_hilbert(x,y) = true

"""
    acts_on(op::AbstractOperator)

Shows on which Hilbert space `op` acts. For [`BasicOperator`](@ref) types, this
returns an Integer, whereas for a [`OperatorTerm`](@ref) it returns a `Vector{Int}`
whose entries specify all subspaces on which the expression acts.
"""
acts_on(op::BasicOperator) = op.aon # TODO make Int[]
function acts_on(t::OperatorTerm)
    ops = filter(SymbolicUtils.sym_isa(AbstractOperator), t.arguments)
    aon = Int[]
    for op in ops
        append!(aon, acts_on(op))
    end
    unique!(aon)
    sort!(aon)
    return aon
end
acts_on(x) = Int[]

Base.one(::T) where T<:AbstractOperator = one(T)
Base.one(::Type{<:AbstractOperator}) = 1
Base.isone(::AbstractOperator) = false
Base.zero(::T) where T<:AbstractOperator = zero(T)
Base.zero(::Type{<:AbstractOperator}) = 0
Base.iszero(::AbstractOperator) = false

function Base.copy(op::T) where T<:BasicOperator
    fields = [getfield(op, n) for n in fieldnames(T)]
    return T(fields...)
end
function Base.copy(t::OperatorTerm)
    return OperatorTerm(t.f, copy.(t.arguments))
end
