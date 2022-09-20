using QuantumOptics
using OrdinaryDiffEq
using ModelingToolkit
using LinearAlgebra
using Symbolics
using SymbolicUtils
using DifferentialEquations
using Plots
include("../src/indexing.jl")
include("../src/doubleSums.jl")
include("../src/averageSums.jl")
include("../src/indexedMeanfield.jl")
using Test

@testset "index_basic" begin

N = 10
ha = NLevelSpace(Symbol(:atom),2)
hf = FockSpace(:cavity)
h = hf⊗ha

indT(i) = Index(h,i,N,ha) #transition index
indF(i) = Index(h,i,N,hf) #fock index
i_ind = indT(:i)
j_ind = indT(:j)

@test(!isequal(indT(:i),indT(:j)))
@test(!isequal(indT(:i),indF(:j)))
@test(!isequal(indT(:i),indF(:i)))

@test(isequal(indT(:i),Index(h,:i,10,ha)))

g(k) = IndexedVariable(:g,k)
@test(!isequal(g(indT(:i)),g(indT(:j))))
@test(isequal(g(indT(:i)),g(Index(h,:i,10,ha))))

σ(i,j,k) = IndexedOperator(Transition(h,:σ,i,j),k)
σ12i = σ(1,2,indT(:i))
@test(isequal(σ12i,σ(1,2,i_ind)))
@test(!isequal(σ12i,σ(2,2,i_ind)))
@test(!isequal(σ12i,σ(1,2,j_ind)))

@test(isequal(0,σ12i*σ(1,2,i_ind)))
@test(isequal(σ(2,2,i_ind),σ(2,1,i_ind)*σ12i))

#@test(isequal(σ(2,2,i_ind)+σ(1,2,j_ind),σ(1,2,j_ind)+σ(2,2,i_ind)))
#apperently QAdd isequal function is dependant in order of terms inside the addition (?)

@test(isequal(adjoint(σ(1,2,i_ind)),σ(2,1,i_ind)))


@qnumbers a::Destroy(h)
sum1 = IndexedSingleSum(σ(1,2,i_ind)*a',i_ind)
sum2 = IndexedSingleSum(σ(2,1,i_ind)*a,i_ind)
@test(isequal(adjoint(sum1),sum2))

sum3 = IndexedSingleSum(a'*σ(1,2,i_ind) + a*σ(2,1,i_ind),i_ind)
@test(isequal(sum3,(sum1+sum2)))
@test(isequal(acts_on(σ12i),2))
@test(i_ind < j_ind)

k_ind = indT(:k)
Γij = DoubleIndexedVariable(:Γ,i_ind,j_ind,true)

@test(isequal(changeIndex(Γij,j_ind,k_ind), DoubleIndexedVariable(:Γ,i_ind,k_ind,true)))
@test(isequal(changeIndex(σ(1,2,j_ind)*σ(1,2,i_ind),j_ind,i_ind),0))
@test(isequal(changeIndex(g(k_ind),k_ind,j_ind),g(j_ind)))

@test(isequal(
    orderByIndex(σ(1,2,k_ind)*σ(1,2,j_ind)*σ(1,2,i_ind),[i_ind]), σ(1,2,i_ind)*σ(1,2,k_ind)*σ(1,2,j_ind)
    ))

@test(isequal(
    reorder(σ(1,2,k_ind)*σ(1,2,j_ind)*σ(1,2,i_ind),[(i_ind,j_ind)]), 
    SpecialIndexedTerm(σ(1,2,k_ind)*σ(1,2,i_ind)*σ(1,2,j_ind),[(i_ind,j_ind)])
))
@test(isequal(
    σ(1,2,k_ind) * sum1, simplify(IndexedSingleSum(σ(1,2,k_ind)*σ(1,2,i_ind)*a',i_ind))
))
@test(isequal(
    σ(2,1,k_ind) * sum1, simplify(IndexedSingleSum(σ(2,1,k_ind)*σ(1,2,i_ind)*a',i_ind,[k_ind]) + a'*σ(2,2,k_ind))
))
innerSum = IndexedSingleSum(σ(2,1,i_ind)*σ(1,2,j_ind),i_ind)
@test(isequal(
    IndexedDoubleSum(innerSum,j_ind), IndexedDoubleSum(IndexedSingleSum(σ(2,1,i_ind)*σ(1,2,j_ind),i_ind,[j_ind]),j_ind) + IndexedSingleSum(σ(2,2,j_ind),j_ind)
))
@test(isequal(SymbolicUtils.arguments(σ(1,2,indT(:i))*a'),SymbolicUtils.arguments(sum1)))


end

