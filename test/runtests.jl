using RuntimeGeneratedFunctions, BenchmarkTools
using Test

function f(_du,_u,_p,_t)
    @inbounds _du[1] = _u[1]
    @inbounds _du[2] = _u[2]
    nothing
end

ex1 = :((_du,_u,_p,_t) -> begin
    @inbounds _du[1] = _u[1]
    @inbounds _du[2] = _u[2]
    nothing
end)

ex2 = :(function f(_du,_u,_p,_t)
    @inbounds _du[1] = _u[1]
    @inbounds _du[2] = _u[2]
    nothing
end)

ex3 = :(function (_du::T,_u::Vector{E},_p::P,_t::Any) where {T<:Vector,E,P}
    @inbounds _du[1] = _u[1]
    @inbounds _du[2] = _u[2]
    nothing
end)

f1 = RuntimeGeneratedFunction(ex1)
f2 = RuntimeGeneratedFunction(ex2)
f3 = RuntimeGeneratedFunction(ex3)

du = rand(2)
u = rand(2)
p = nothing
t = nothing

@test f1(du,u,p,t) === nothing
du == u
du = rand(2)
f2(du,u,p,t)
@test du == u
du = rand(2)
@test f3(du,u,p,t) === nothing
du == u

t1 = @belapsed $f($du,$u,$p,$t)
t2 = @belapsed $f1($du,$u,$p,$t)
t3 = @belapsed $f2($du,$u,$p,$t)
t4 = @belapsed $f3($du,$u,$p,$t)

@test t1 ≈ t2 atol = 3e-9
@test t1 ≈ t3 atol = 3e-9
@test t1 ≈ t4 atol = 3e-9

function no_worldage()
    ex = :(function f(_du,_u,_p,_t)
        @inbounds _du[1] = _u[1]
        @inbounds _du[2] = _u[2]
        nothing
    end)
    f1 = RuntimeGeneratedFunction(ex)
    du = rand(2)
    u = rand(2)
    p = nothing
    t = nothing
    f1(du,u,p,t)
end
@test no_worldage() === nothing
