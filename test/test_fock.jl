using Qumulants
using Test

@testset "fock" begin

# Test
hf = FockSpace(:c)

a = Destroy(hf,:a)
ad = a'

# Test conversion to Symbolics
a_sym = Qumulants._to_symbolic(a)
@test Qumulants.acts_on(a_sym)==1
@test Qumulants._to_qumulants(a_sym)==a

b = Destroy(hf,:b)
@test Qumulants._to_symbolic(a) != Qumulants._to_symbolic(b)

@test isequal(a,ad')
@test isequal(simplify_operators(a),a)
@test isequal(simplify_operators(a+a),2*a)
@test isequal(simplify_operators(a*a') , 1+a'*a)
@test isequal(simplify_operators(a*a' + 1) , 2 + a'*a)

@test isequal(simplify_operators(-1*(a'*a + 1)*a + a) , -1*a'*a*a)
@test isequal(simplify_operators(a'*a*a - a*a'*a) , -1*a)

# Single mode
ωc = 0.1313
H = ωc*a'*a
da = simplify_operators(1.0im*(H*a - a*H))
@test isequal(da , -1.0im*ωc*a)

end # testset
