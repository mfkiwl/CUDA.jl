using Adapt
using CUDA.CUSPARSE
using LinearAlgebra, SparseArrays

@testset "LinearAlgebra" begin
    @testset "CuSparseVector -- A ± B $elty" for elty in [Float32, Float64, ComplexF32, ComplexF64]
        n = 10
        alpha = rand()
        beta = rand()
        A = sprand(elty, n, 0.3)
        B = sprand(elty, n, 0.7)

        dA = CuSparseVector(A)
        dB = CuSparseVector(B)

        C = alpha * A + beta * B
        dC = axpby(alpha, dA, beta, dB, 'O')
        @test C ≈ collect(dC)

        C = A + B
        dC = dA + dB
        @test C ≈ collect(dC)

        C = A - B
        dC = dA - dB
        @test C ≈ collect(dC)
    end

    for SparseMatrixType in (CuSparseMatrixCSC, CuSparseMatrixCSR)
        @testset "$SparseMatrixType -- A ± B $elty" for elty in [Float32, Float64, ComplexF32, ComplexF64]
            n = 10
            m = 20
            alpha = rand()
            beta = rand()
            A = sprand(elty, n, m, 0.2)
            B = sprand(elty, n, m, 0.5)

            dA = SparseMatrixType(A)
            dB = SparseMatrixType(B)

            C = alpha * A + beta * B
            dC = geam(alpha, dA, beta, dB, 'O')
            @test C ≈ collect(dC)

            C = A + B
            dC = dA + dB
            @test C ≈ collect(dC)

            C = A - B
            dC = dA - dB
            @test C ≈ collect(dC)
        end
    end

    @testset "$f(A)±$h(B) $elty" for elty in [Float32, Float64, ComplexF32, ComplexF64],
                                     f in (identity, transpose), #adjoint),
                                     h in (identity, transpose)#, adjoint)
        # adjoint need the support of broadcast for `conj()` to work with `CuSparseMatrix`.
        n = 10
        alpha = rand()
        beta = rand()
        A = sprand(elty, n, n, rand())
        B = sprand(elty, n, n, rand())

        dA = CuSparseMatrixCSR(A)
        dB = CuSparseMatrixCSR(B)

        C = f(A) + h(B)
        dC = f(dA) + h(dB)
        @test C ≈ collect(dC)

        C = f(A) - h(B)
        dC = f(dA) - h(dB)
        @test C ≈ collect(dC)
    end

    @testset "A±$f(B) $elty" for elty in [Float32, Float64, ComplexF32, ComplexF64],
                                 f in (CuSparseMatrixCSR, CuSparseMatrixCSC, x->CuSparseMatrixBSR(x,1))
        n = 10
        A = sprand(elty, n, n, rand())
        B = sprand(elty, n, n, rand())

        dA = CuSparseMatrixCSR(A)
        dB = CuSparseMatrixCSR(B)

        C = A + B
        dC = dA + f(dB)
        @test C ≈ collect(dC)

        C = B + A
        dC = f(dB) + dA
        @test C ≈ collect(dC)

        C = A - B
        dC = dA - f(dB)
        @test C ≈ collect(dC)

        C = B - A
        dC = f(dB) - dA
        @test C ≈ collect(dC)
    end

    @testset "$f(A)*b $elty" for elty in [Float32, Float64, ComplexF32, ComplexF64],
                                 f in (identity, transpose, adjoint)
        n = 10
        alpha = rand()
        beta = rand()
        A = sprand(elty, n, n, rand())
        b = rand(elty, n)
        c = rand(elty, n)
        alpha = beta = 1.0
        c = zeros(elty, n)

        dA = CuSparseMatrixCSR(A)
        db = CuArray(b)
        dc = CuArray(c)

        # test with empty inputs
        @test Array(dA * CUDA.zeros(elty, n, 0)) == zeros(elty, n, 0)

        mul!(c, f(A), b, alpha, beta)
        mul!(dc, f(dA), db, alpha, beta)
        @test c ≈ collect(dc)

        A = A + transpose(A)
        dA = CuSparseMatrixCSR(A)

        @assert issymmetric(A)
        mul!(c, f(Symmetric(A)), b, alpha, beta)
        mul!(dc, f(Symmetric(dA)), db, alpha, beta)
        @test c ≈ collect(dc)
    end

    @testset "$f(A)*b Complex{$elty}*$elty" for elty in [Float32, Float64],
                                 f in (identity, transpose, adjoint)
        n = 10
        alpha = rand()
        beta = rand()
        A = sprand(Complex{elty}, n, n, rand())
        b = rand(Complex{elty}, n)
        c = rand(Complex{elty}, n)
        alpha = beta = 1.0
        c = zeros(Complex{elty}, n)

        dA = CuSparseMatrixCSR(A)
        db = CuArray(b)
        dc = CuArray(c)

        # test with empty inputs
        @test Array(dA * CUDA.zeros(Complex{elty}, n, 0)) == zeros(Complex{elty}, n, 0)

        mul!(c, f(A), b, alpha, beta)
        mul!(dc, f(dA), db, alpha, beta)
        @test c ≈ collect(dc)

        A = A + transpose(A)
        dA = CuSparseMatrixCSR(A)

        @assert issymmetric(A)
        mul!(c, f(Symmetric(A)), b, alpha, beta)
        mul!(dc, f(Symmetric(dA)), db, alpha, beta)
        @test c ≈ collect(dc)
    end

    @testset "$f(A)*$h(B) $elty" for elty in [Float32, Float64, ComplexF32, ComplexF64],
                                     f in (identity, transpose, adjoint),
                                     h in (identity, transpose, adjoint)
        if CUSPARSE.version() <= v"10.3.1" &&
            (h ∈ (transpose, adjoint) && f != identity) ||
            (h == adjoint && elty <: Complex)
            # These combinations are not implemented in CUDA10
            continue
        end

        n = 10
        alpha = rand()
        beta = rand()
        A = sprand(elty, n, n, rand())
        B = rand(elty, n, n)
        C = rand(elty, n, n)

        dA = CuSparseMatrixCSR(A)
        dB = CuArray(B)
        dC = CuArray(C)

        mul!(C, f(A), h(B), alpha, beta)
        mul!(dC, f(dA), h(dB), alpha, beta)
        @test C ≈ collect(dC)

        A = A + transpose(A)
        dA = CuSparseMatrixCSR(A)

        @assert issymmetric(A)
        mul!(C, f(Symmetric(A)), h(B), alpha, beta)
        mul!(dC, f(Symmetric(dA)), h(dB), alpha, beta)
        @test C ≈ collect(dC)
    end

    @testset "issue #1095 ($elty)" for elty in [Float32, Float64, ComplexF32, ComplexF64]
        # Test non-square matrices
        n, m, p = 10, 20, 4
        alpha = rand()
        beta = rand()
        A = sprand(elty, n, m, rand())
        B = rand(elty, m, p)
        C = rand(elty, n, p)

        dA = CuSparseMatrixCSR(A)
        dB = CuArray(B)
        dC = CuArray(C)

        mul!(C, A, B, alpha, beta)
        mul!(dC, dA, dB, alpha, beta)
        @test C ≈ collect(dC)

        mul!(B, transpose(A), C, alpha, beta)
        mul!(dB, transpose(dA), dC, alpha, beta)
        @test B ≈ collect(dB)

        mul!(B, adjoint(A), C, alpha, beta)
        mul!(dB, adjoint(dA), dC, alpha, beta)
        @test B ≈ collect(dB)
    end

    @testset "CuSparseMatrixCSR($f) $elty" for f in [transpose, adjoint], elty in [Float32, ComplexF32]
        S = f(sprand(elty, 10, 10, 0.1))
        @test SparseMatrixCSC(CuSparseMatrixCSR(S)) ≈ S

        S = sprand(elty, 10, 10, 0.1)
        T = f(CuSparseMatrixCSR(S))
        @test SparseMatrixCSC(CuSparseMatrixCSC(T)) ≈ f(S)

        S = sprand(elty, 10, 10, 0.1)
        T = f(CuSparseMatrixCSC(S))
        @test SparseMatrixCSC(CuSparseMatrixCSR(T)) ≈ f(S)
    end

    VERSION >= v"1.7" && @testset "UniformScaling with $typ($dims)" for
            typ in [CuSparseMatrixCSR, CuSparseMatrixCSC],
            dims in [(10, 10), (5, 10), (10, 5)]
        S = sprand(Float32, dims..., 0.1)
        dA = typ(S)

        @test Array(dA + I) == S + I
        @test Array(I + dA) == I + S

        @test Array(dA - I) == S - I
        @test Array(I - dA) == I - S
    end

    @testset "Diagonal with $typ(10, 10)" for
        typ in [CuSparseMatrixCSR, CuSparseMatrixCSC]
        
        S = sprand(Float32, 10, 10, 0.8)
        D = Diagonal(rand(Float32, 10))
        dA = typ(S)
        dD = adapt(CuArray, D)

        @test Array(dA + dD) == S + D
        @test Array(dD + dA) == D + S

        @test Array(dA - dD) == S - D
        @test Array(dD - dA) == D - S

        @test dA + dD isa typ
        @test dD + dA isa typ
        @test dA - dD isa typ
        @test dD - dA isa typ
    end

    @testset "dot(CuVector, CuSparseVector) and dot(CuSparseVector, CuVector) $elty" for elty in [Float32, Float64, ComplexF32, ComplexF64],
        n = 10
        x = sprand(elty, n, 0.5)
        y = rand(elty, n)

        dx = CuSparseVector(x)
        dy = CuVector(y)

        @test dot(dx,dy) ≈ dot(x,y)
        @test dot(dy,dx) ≈ dot(y,x)
    end

    for SparseMatrixType in (CuSparseMatrixCSC, CuSparseMatrixCSR, CuSparseMatrixBSR)

        @testset "ldiv!($SparseMatrixType, CuVector) $elty" for elty in [Float32,Float64,ComplexF32,ComplexF64]
            for triangle in [LowerTriangular, UnitLowerTriangular, UpperTriangular, UnitUpperTriangular]
                for opa in [identity, transpose, adjoint]
                    SparseMatrixType == CuSparseMatrixCSC && elty <: Complex && opa == adjoint && continue
                    A = sparse(rand(elty, 10, 10))
                    y = rand(elty, 10)
                    dA = SparseMatrixType == CuSparseMatrixBSR ? SparseMatrixType(A, 1) : SparseMatrixType(A)
                    dy = CuArray(y)
                    ldiv!(triangle(opa(A)), y)
                    ldiv!(triangle(opa(dA)), dy)
                    @test y ≈ collect(dy)
                 end
            end
        end

        @testset "ldiv!($SparseMatrixType, CuMatrix) $elty" for elty in [Float32,Float64,ComplexF32,ComplexF64]
            for triangle in [LowerTriangular, UnitLowerTriangular, UpperTriangular, UnitUpperTriangular]
                for opa in [identity, transpose, adjoint]
                    SparseMatrixType == CuSparseMatrixCSC && elty <: Complex && opa == adjoint && continue
                    A = sparse(rand(elty, 10, 10))
                    B = rand(elty, 10, 2)
                    dA = SparseMatrixType == CuSparseMatrixBSR ? SparseMatrixType(A, 1) : SparseMatrixType(A)
                    dB = CuArray(B)
                    ldiv!(triangle(opa(A)), B)
                    ldiv!(triangle(opa(dA)), dB)
                    @test B ≈ collect(dB)
                end
            end
        end
    end

    if CUSPARSE.version() >= v"11.7.0"
        for SparseMatrixType in (CuSparseMatrixCOO,)

            @testset "ldiv!(CuVector, $SparseMatrixType, CuVector) $elty" for elty in [Float32,Float64,ComplexF32,ComplexF64]
                for triangle in [LowerTriangular, UnitLowerTriangular, UpperTriangular, UnitUpperTriangular]
                    for opa in [identity, transpose, adjoint]
                        elty <: Complex && opa == adjoint && continue  # Issue 1610
                        A = sparse(rand(elty, 10, 10))
                        y = rand(elty, 10)
                        x = rand(elty, 10)
                        dA = SparseMatrixType(A)
                        dy = CuArray(y)
                        dx = CuArray(x)
                        ldiv!(x, triangle(opa(A)), y)
                        ldiv!(dx, triangle(opa(dA)), dy)
                        @test x ≈ collect(dx)
                     end
                end
            end

            @testset "ldiv!(CuMatrix, $SparseMatrixType, CuMatrix) $elty" for elty in [Float32,Float64,ComplexF32,ComplexF64]
                for triangle in [LowerTriangular, UnitLowerTriangular, UpperTriangular, UnitUpperTriangular]
                    for opa in [identity, transpose, adjoint]
                        for opb in [identity, transpose, adjoint]
                            elty <: Complex && opa == adjoint && continue # Issue 1610
                            elty <: Complex && opb == adjoint && continue
                            A = sparse(rand(elty, 10, 10))
                            B = opb == identity ? rand(elty, 10, 2) : rand(elty, 2, 10)
                            C = rand(elty, 10, 2)
                            dA = SparseMatrixType(A)
                            dB = CuArray(B)
                            dC = CuArray(C)
                            ldiv!(C, triangle(opa(A)), opb(B))
                            ldiv!(dC, triangle(opa(dA)), opb(dB))
                            @test C ≈ collect(dC)
                        end
                    end
                end
            end
        end
    end
end
