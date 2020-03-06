using Test

import MathOptInterface
const MOI = MathOptInterface

@testset "hs071" begin
    mock = MOI.Utilities.MockOptimizer(
        MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}()),
        eval_objective_value=false
    )
    config = MOI.Test.TestConfig(optimal_status = MOI.LOCALLY_SOLVED)
    MOI.Utilities.set_mock_optimize!(
        mock,
        (mock) -> begin
            MOI.Utilities.mock_optimize!(
                mock, config.optimal_status,
                [1.0, 4.7429996418092970, 3.8211499817883077, 1.379408289755698]
            )
            MOI.set(mock, MOI.ObjectiveValue(), 17.014017145179164)
        end
    )
    MOI.Test.hs071_test(mock, config)
    MOI.Test.hs071_no_hessian_test(mock, config)
end

@testset "mixed_complementarity" begin
    mock = MOI.Utilities.MockOptimizer(
        MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}())
    )
    config = MOI.Test.TestConfig(optimal_status = MOI.LOCALLY_SOLVED)
    MOI.Utilities.set_mock_optimize!(
        mock,
        (mock) -> MOI.Utilities.mock_optimize!(
            mock, config.optimal_status, [2.8, 0.0, 0.8, 1.2]
        )
    )
    MOI.Test.mixed_complementaritytest(mock, config)
end

@testset "math_program_complementarity_constraints" begin
    mock = MOI.Utilities.MockOptimizer(
        MOI.Utilities.UniversalFallback(MOI.Utilities.Model{Float64}())
    )
    config = MOI.Test.TestConfig(optimal_status = MOI.LOCALLY_SOLVED)
    MOI.Utilities.set_mock_optimize!(
        mock,
        (mock) -> MOI.Utilities.mock_optimize!(
            mock, config.optimal_status, [1.0, 0.0, 3.5, 0.0, 0.0, 0.0, 3.0, 6.0]
        )
    )
    MOI.Test.math_program_complementarity_constraintstest(mock, config)
end
