using QuantumCumulants
using OrdinaryDiffEq
using ModelingToolkit
using Test

@testset "diffeq" begin

hf = FockSpace(:cavity)
ha = NLevelSpace(:atom,(:g,:e))
h = tensor(hf, ha)

@qnumbers a::Destroy(h) σ::Transition(h,:g,:e)

# Single-atom laser
@cnumbers Δ g κ γ ν

H = Δ*a'*a + g*(a'*σ + σ'*a)
J = [a,σ,σ']
he_avg = heisenberg([a'*a,σ'*σ,a*σ'],H,J;rates=[κ,γ,ν])

he_exp = cumulant_expansion(he_avg,2)
@test isequal(he_exp.equations, heisenberg([a'*a,σ'*σ,a*σ'],H,J;rates=[κ,γ,ν],expand=true,order=2).equations)

ps = [Δ,g,κ,γ,ν]
missed = find_missing(he_exp)
@test !any(QuantumCumulants._in(p, missed) for p=ps)

# Exploit phase invariance
subs = Dict([missed; QuantumCumulants._conj.(missed)] .=> 0)
he_nophase = substitute(he_exp, subs)
@test isempty(find_missing(he_nophase))

sys = ODESystem(he_nophase)

# Numerical solution
p0 = ps .=> [0.0,0.5,1.0,0.1,0.9]
u0 = zeros(ComplexF64,3)
tmax = 10.0

prob = ODEProblem(sys,u0,(0.0,tmax),p0,jac=true)
sol = solve(prob,RK4())
n = sol[average(a'*a)]
pe = getindex.(sol.u,2)

@test all(iszero.(imag.(n)))
@test all(iszero.(imag.(pe)))
@test all(real.(n) .>= 0.0)
@test all(1.0 .>= real.(pe) .>= 0.0)

end # testset
