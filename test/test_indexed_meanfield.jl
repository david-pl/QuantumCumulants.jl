using Test
using QuantumCumulants
using SymbolicUtils
using Symbolics

const qc = QuantumCumulants

@testset "indexed_meanfield" begin

order = 2
@cnumbers Δc η Δa κ

N = 2 #number of atoms
hc = FockSpace(:cavity)
ha = NLevelSpace(Symbol(:atom),2)
h = hc ⊗ ha

#define indices
i_ind = Index(h,:i,N,ha)
j_ind = Index(h,:j,N,ha)
k_ind = Index(h,:k,N,ha)

#define indexed variables
g(k) = IndexedVariable(:g,k)
Γ_ij = DoubleIndexedVariable(:Γ,i_ind,j_ind)
Ω_ij = DoubleIndexedVariable(:Ω,i_ind,j_ind;identical=false)

@qnumbers a::Destroy(h)
σ(i,j,k) = IndexedOperator(Transition(h,:σ,i,j),k)

# Hamiltonian

DSum = Σ(Ω_ij*σ(2,1,i_ind)*σ(1,2,j_ind),j_ind,i_ind;non_equal=true)

@test DSum isa IndexedDoubleSum
@test isequal(Σ(Σ(Ω_ij*σ(2,1,i_ind)*σ(1,2,j_ind),i_ind,[j_ind]),j_ind),DSum)

Hc = Δc*a'a + η*(a' + a)
Ha = Δa*Σ(σ(2,2,i_ind),i_ind) + DSum
Hi = Σ(g(i_ind)*(a'*σ(1,2,i_ind) + a*σ(2,1,i_ind)),i_ind)
H = Hc + Ha + Hi

J = [a, [σ(1,2,i_ind),σ(1,2,j_ind)] ] 
rates = [κ,Γ_ij]

ops = [a, σ(2,2,k_ind), σ(1,2,k_ind)]
eqs = indexed_meanfield(ops,H,J;rates=rates,order=order)

@test isequal([i_ind,j_ind,k_ind],sort(qc.getAllIndices(eqs)))
@test isequal([:i,:j,:k],sort(qc.getIndName.(qc.getAllIndices(eqs))))

@test length(eqs) == 3

ind1 = Index(h,:q,N,ha)
ind2 = Index(h,:r,N,ha)
ind3 = Index(h,:s,N,ha)

eqs_comp = complete(eqs;extra_indices=[ind1,ind2,ind3])
eqs_comp2 = complete(eqs)

@test length(eqs_comp.equations) == length(eqs_comp2.equations)

eqs_ = evaluate(eqs_comp)
eqs_2 = evaluate(eqs_comp2)

@test length(eqs_2) == length(eqs_)

for i = 1:length(eqs_)
    @test length(arguments(eqs_[i].rhs)) == length(arguments(eqs_2[i].rhs))
end

@test length(eqs_) == 18

eqs_4 = indexed_meanfield(ops,H,J;rates=rates,order=4)

@test length(eqs_4) == length(eqs)


end