using Test

import SymbolicUtils
import SymbolicUtils: substitute

import Symbolics
import TermInterface

import SciMLBase

import ModelingToolkit
const MTK = ModelingToolkit

using Combinatorics: partitions, combinations
using LinearAlgebra

using QuantumOpticsBase
import QuantumOpticsBase: ⊗, tensor

const NO_METADATA = SymbolicUtils.NO_METADATA

source_metadata(source, name) = 
    Base.ImmutableDict{DataType, Any}(Symbolics.VariableSource, (source, name))

include("../src/hilbertspace.jl")
include("../src/qnumber.jl")
include("../src/cnumber.jl")
include("../src/fock.jl")
include("../src/nlevel.jl")
include("../src/equations.jl")
include("../src/meanfield.jl")
include("../src/average.jl")
include("../src/utils.jl")
include("../src/diffeq.jl")
include("../src/correlation.jl")
include("../src/cluster.jl")
include("../src/scale.jl")
include("../src/latexify_recipes.jl")
include("../src/printing.jl")
include("../src/indexing.jl")
include("../src/doubleSums.jl")
include("../src/averageSums.jl")
include("../src/indexedMeanfield.jl")
include("../src/indexedScale.jl")
include("../src/indexedCorrelation.jl")

@testset "average_sums" begin

N = 2
ha = NLevelSpace(Symbol(:atom),2)
hf = FockSpace(:cavity)
h = hf⊗ha

ind(i) = Index(h,i,N,ha)

g(k) = IndexedVariable(:g,k)
σ(i,j,k) = IndexedOperator(Transition(h,:σ,i,j),k)

@test(isequal(average(2*σ(1,2,ind(:k))),2*average(σ(1,2,ind(:k)))))
@test(isequal(average(g(ind(:k))*σ(2,2,ind(:k))),g(ind(:k))*average(σ(2,2,ind(:k)))))
@test(isequal(average(g(ind(:k))),g(ind(:k))))

sum1 = IndexedSingleSum(σ(1,2,ind(:k)),ind(:k))
σn(i,j,k) = NumberedOperator(Transition(h,:σ,i,j),k)
@test(isequal(evalTerm(average(sum1)),average(σn(1,2,1)) + average(σn(1,2,2))))
@test(isequal(σn(1,2,1)+σn(2,1,1),NumberedOperator(Transition(h,:σ,1,2)+Transition(h,:σ,2,1),1)))

@test(isequal(sum1,undo_average(average(sum1))))

#test insertIndex
@test(isequal(σn(2,2,1),insertIndex(σ(2,2,ind(:j)),ind(:j),1)))
@test(isequal(σ(1,2,ind(:j)),insertIndex(σ(1,2,ind(:j)),ind(:k),2)))
@test(isequal(1,insertIndex(1,ind(:k),1)))

sum2 = average(sum1*σ(1,2,ind(:l)))

@test(!isequal(σn(2,2,1),insertIndex(sum2,ind(:j),1)))


end

