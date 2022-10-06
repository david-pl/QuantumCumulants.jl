using Test
using QuantumCumulants
using SymbolicUtils
using Symbolics

const qc = QuantumCumulants

@testset "indexed_correlation" begin

order = 2 #order of the cumulant expansion
@cnumbers N Δ g κ Γ R ν M

# Hilbertspace
hc = FockSpace(:cavity)
ha = NLevelSpace(:atom,2)

h = hc ⊗ ha

# Indices and Operators

k = Index(h,:k,N,ha)
l = Index(h,:l,N,ha)
m = Index(h,:m,N,ha)
n = Index(h,:n,N,ha)

extraIndices = [n]

@qnumbers a::Destroy(h)

σ(i,j,k) = IndexedOperator(Transition(h,:σ,i,j),k)

# Define the Hamiltonian
H = -Δ*a'a + g*(Σ(a'*σ(1,2,k),k) + Σ(a*σ(2,1,k),k))

J = [a,σ(1,2,l),σ(2,1,l),σ(2,2,l)]
rates = [κ, Γ, R, ν]
ops = [a'*a,σ(2,2,m)]
eqs = indexedMeanfield(ops,H,J;rates=rates,order=order)

@test length(eqs) == 2

φ(x::Average) = φ(x.arguments[1])
φ(::Destroy) = -1
φ(::Create) =1
φ(x::QTerm) = sum(map(φ, x.args_nc))
φ(x::Transition) = x.i - x.j
φ(x::IndexedOperator) = x.op.i - x.op.j
φ(x::IndexedSingleSum) = φ(x.term)
φ(x::SymbolicUtils.Sym{Parameter, IndexedAverageSum}) = φ(x.metadata.term)
φ(x::SymbolicUtils.Sym{Parameter, SpecialIndexedAverage}) = φ(x.metadata.term)
φ(x::SpecialIndexedAverage) = φ(x.term)
phase_invariant(x) = iszero(φ(x))

eqs_c = complete(eqs;filter_func=phase_invariant,scaling=false,extraIndices=extraIndices);
eqs_c2 = complete(eqs;filter_func=phase_invariant,scaling=false,extraIndices=[:n]);

eqs_sc1 = scale(eqs_c)
eqs_sc2 = scale(eqs_c2)

@test length(eqs_sc1) == 4
@test length(eqs_c) == 4

for i = 1:length(eqs_c)
    @test isequal(length(arguments(eqs_c[i].rhs)),length(arguments(eqs_c2[i].rhs)))
    @test isequal(length(arguments(eqs_sc1[i].rhs)),length(arguments(eqs_sc2[i].rhs)))
end

avrgSum = arguments(arguments(eqs_c[1].rhs)[1])[2]

split0 = splitSums(avrgSum,l,15)

@test isequal(split0,avrgSum)

split1 = splitSums(avrgSum,k,4)

@test split1 isa SymbolicUtils.Mul
@test !isequal(split1,avrgSum)
@test isequal(4,arguments(split1)[1])
@test isequal(N/4,arguments(split1)[2].metadata.sumIndex.rangeN)

split2 = splitSums(avrgSum,k,M)

@test !isequal(split2,split1)
@test !isequal(split2,avrgSum)
@test isequal(M,arguments(split2)[1])
@test isequal(N/M,arguments(split2)[2].metadata.sumIndex.rangeN)

avrgSum2 = arguments(arguments(eqs_c[3].rhs)[1])[2]

_split0 = splitSums(avrgSum2,l,15)

@test isequal(avrgSum2,_split0)
@test isequal(avrgSum2,splitSums(avrgSum2,k,1))

_split1 = splitSums(avrgSum2,k,3)

@test !isequal(_split1,avrgSum2)
@test _split1 isa SymbolicUtils.Add
@test isequal(2,length(arguments(_split1)))

op1 = a'
op2 = a

corr = indexedCorrelationFunction(a', a, eqs_c; steady_state=true, filter_func=phase_invariant,extraIndices=extraIndices,scaling=true);

ps = [N, Δ, g, κ, Γ, R, ν]

@test length(corr.de0) == 4
@test length(corr.de) == 2

mapping = Dict{SymbolicUtils.Sym,Int64}(N=>5)
evals = evaluate(eqs_c;mapping=mapping)

@test length(evals) == 21
@test length(unique(evals.states)) == length(evals.states)

@cnumbers N_

i = Index(h,:i,N_,ha)
j = Index(h,:j,N_,ha)

Γ_ij = DoubleIndexedVariable(:Γ,i,j,true)
Ω_ij = DoubleIndexedVariable(:Ω,i,j,false)
gi = IndexedVariable(:g,i)

ΓMatrix = [1.0 1.0
            1.0 1.0]

ΩMatrix = [0.0 0.5
            0.5 0.0]

gn = [1.0,2.0]
κn = 3.0

ps = [Γ_ij,Ω_ij,gi,κ]
p0 = [ΓMatrix,ΩMatrix,gn,κn]

mapping = Dict{SymbolicUtils.Sym,Int64}(N_=>2)
valmap = createMap(ps,p0;mapping=mapping)

map_ = Dict{SymbolicUtils.Sym{Parameter, Base.ImmutableDict{DataType, Any}},ComplexF64}()
push!(map_,qc.DoubleNumberedVariable(:Γ,1,1)=>1.0)
push!(map_,qc.DoubleNumberedVariable(:Γ,2,1)=>1.0)
push!(map_,qc.DoubleNumberedVariable(:Γ,1,2)=>1.0)
push!(map_,qc.DoubleNumberedVariable(:Γ,2,2)=>1.0)
push!(map_,qc.DoubleNumberedVariable(:Ω,2,2)=>0.0)
push!(map_,qc.DoubleNumberedVariable(:Ω,1,2)=>0.5)
push!(map_,qc.DoubleNumberedVariable(:Ω,1,1)=>0.0)
push!(map_,qc.DoubleNumberedVariable(:Ω,2,1)=>0.5)
push!(map_,qc.SingleNumberedVariable(:g,1)=>1.0)
push!(map_,qc.SingleNumberedVariable(:g,2)=>2.0)
push!(map_,κ=>3.0)



@test length(valmap) == 11
@test length(valmap) == length(map_)
for arg in valmap
    @test arg in map_
end


end