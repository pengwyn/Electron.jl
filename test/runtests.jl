using Electron
using URIParser
using Base.Test

@testset "Electron" begin

w = Window(URI("file://test.html"))

@test isa(w, Window)

res = run(w, "Math.log(Math.exp(1))")

@test res==1

close(w.app)

end