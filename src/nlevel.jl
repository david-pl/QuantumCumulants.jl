"""
    NLevelSpace <: HilbertSpace
    NLevelSpace(name::Symbol,levels,GS=1)

Define a [`HilbertSpace`](@ref) for an object consisting of `N` discrete energy
levels. The given `levels` must be an integer specifying the number of levels,
or an iterable collection of levels. The argument `GS` specifies which state
should be treated as ground state and is rewritten using population conservation
during simplification.
See also: [`Transition`](@ref)

Examples:
========
```
julia> ha = NLevelSpace(:a,3)
ℋ(a)

julia> ha = NLevelSpace(:a,(:g,:e))
ℋ(a)
```
"""
struct NLevelSpace{S,L,G} <: HilbertSpace
    name::S
    levels::L
    GS::G
end
NLevelSpace(name,N::Int,GS) = NLevelSpace(name,1:N,GS)
NLevelSpace(name,N::Int) = NLevelSpace(name,1:N,1)
NLevelSpace(name,levels) = NLevelSpace(name,levels,levels[1])
Base.:(==)(h1::T,h2::T) where T<:NLevelSpace = (h1.name==h2.name && h1.levels==h2.levels && h1.GS==h2.GS)
Base.hash(n::NLevelSpace, h::UInt) = hash(n.name, hash(n.levels, hash(n.GS, h)))

levels(h::NLevelSpace) = h.levels
levels(h::NLevelSpace,aon) = levels(h)
levels(h::ProductSpace,aon) = levels(h.spaces[aon])
ground_state(h::NLevelSpace) = h.GS
ground_state(h::NLevelSpace,aon) = h.GS
ground_state(h::ProductSpace,aon) = ground_state(h.spaces[aon])

"""
    Transition <: BasicOperator
    Transition(h::NLevelSpace,name::Symbol,i,j)

Fundamental operator defining a transition from level `j` to level `i` on a
[`NLevelSpace`](@ref). The notation corresponds to Dirac notation, i.e. the
above is equivalent to `|i⟩⟨j|`.

Examples
=======
```
julia> ha = NLevelSpace(:a,(:g,:e))
ℋ(a)

julia> σ = Transition(ha,:σ,:g,:e)
σge
```
"""
struct Transition{H,S,I,A} <: BasicOperator
    hilbert::H
    name::S
    i::I
    j::I
    aon::A
    function Transition{H,S,I,A}(hilbert::H,name::S,i::I,j::I,aon::A) where {H,S,I,A}
        @assert has_hilbert(NLevelSpace,hilbert,aon)
        @assert i∈levels(hilbert,aon) && j∈levels(hilbert,aon)
        op = new(hilbert,name,i,j,aon)
        if !haskey(OPERATORS_TO_SYMS, op)
            sym = SymbolicUtils.Sym{Transition}(gensym(:Transition))
            OPERATORS_TO_SYMS[op] = sym
            SYMS_TO_OPERATORS[sym] = op
        end
        return op
    end
end
Transition(hilbert::H,name::S,i::I,j::I,aon::A) where {H,S,I,A} = Transition{H,S,I,A}(hilbert,name,i,j,aon)
Transition(hilbert::NLevelSpace,name,i,j) = Transition(hilbert,name,i,j,1)

function embed(h::ProductSpace,op::T,aon::Int) where T<:Transition
    check_hilbert(h.spaces[aon],op.hilbert)
    op_ = Transition(h,op.name,op.i,op.j,aon)
    return op_
end
levels(t::Transition,args...) = levels(t.hilbert,args...)
ground_state(t::Transition,args...) = ground_state(t.hilbert,args...)

Base.adjoint(t::Transition) = Transition(t.hilbert,t.name,t.j,t.i,acts_on(t))
Base.:(==)(t1::Transition,t2::Transition) = (t1.hilbert==t2.hilbert && t1.name==t2.name && t1.i==t2.i && t1.j==t2.j && t1.aon==t2.aon)
Base.isequal(t1::Transition,t2::Transition) = (isequal(t1.hilbert,t2.hilbert) && isequal(t1.name,t2.name) && isequal(t1.i,t2.i) && isequal(t1.j,t2.j) && isequal(t1.aon,t2.aon))
Base.hash(t::Transition, h::UInt) = hash(t.hilbert, hash(t.name, hash(t.i, hash(t.j, hash(t.aon, h)))))

# Simplification
istransition(x::Union{T,SymbolicUtils.Sym{T}}) where T<:Transition = true

function merge_transitions(σ1::SymbolicUtils.Sym{<:Transition},σ2::SymbolicUtils.Sym{<:Transition})
    op = merge_transitions(_to_qumulants(σ1), _to_qumulants(σ2))
    return _to_symbolic(op)
end
function merge_transitions(σ1::Transition, σ2::Transition)
    i1,j1 = σ1.i, σ1.j
    i2,j2 = σ2.i, σ2.j
    if j1==i2
        return Transition(σ1.hilbert,σ1.name,i1,j2,σ1.aon)
    else
        return 0
    end
end
function rewrite_gs(t::SymbolicUtils.Sym{<:Transition})
    op = rewrite_gs(_to_qumulants(t))
    return _to_symbolic(op)
end
function rewrite_gs(σ::Transition)
    h = σ.hilbert
    aon = acts_on(σ)
    gs = ground_state(h,aon)
    i,j = σ.i, σ.j
    if i==j==gs
        args = Any[1]
        for k in levels(h,aon)
            (k==i) || push!(args, -1*Transition(h, σ.name, k, k, aon))
        end
        return +(args...)
    else
        return nothing
    end
end
