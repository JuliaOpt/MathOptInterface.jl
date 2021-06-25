module Test

using MathOptInterface
const MOI = MathOptInterface
const MOIU = MOI.Utilities

using Test

# Be wary of adding new fields to this Config struct. Always think: can it be
# achieved a different way?
mutable struct Config{T<:Real}
    atol::T
    rtol::T
    supports_optimize::Bool
    optimal_status::MOI.TerminationStatusCode
    excluded_attributes::Vector{Any}
end

"""
    Config(
        ::Type{T} = Float64;
        atol::Real = Base.rtoldefault(T),
        rtol::Real = Base.rtoldefault(T),
        supports_optimize::Bool = true,
        optimal_status::MOI.TerminationStatusCode = MOI.OPTIMAL,
        excluded_attributes::Vector{Any} = Any[],
    ) where {T}

Return an object that is used to configure various tests.

## Configuration arguments

  * `atol::Real = Base.rtoldefault(T)`: Control the absolute tolerance used
    when comparing solutions.
  * `rtol::Real = Base.rtoldefault(T)`: Control the relative tolerance used
    when comparing solutions.
  * `supports_optimize::Bool = true`: Set to `false` to skip tests requiring a
    call to [`MOI.optimize!`](@ref)
  * `optimal_status = MOI.OPTIMAL`: Set to `MOI.LOCALLY_SOLVED` if the solver
    cannot prove global optimality.

## Examples

For a nonlinear solver that finds local optima and does not support finding
dual variables or constraint names:
```julia
Config(
    Float64;
    optimal_status = MOI.LOCALLY_SOLVED,
    excluded_attributes = Any[
        MOI.ConstraintDual(),
        MOI.VariableName(),
        MOI.ConstraintName(),
    ],
)
```
"""
function Config(
    ::Type{T} = Float64;
    atol::Real = Base.rtoldefault(T),
    rtol::Real = Base.rtoldefault(T),
    supports_optimize::Bool = true,
    optimal_status::MOI.TerminationStatusCode = MOI.OPTIMAL,
    excluded_attributes::Vector{Any} = Any[],
) where {T<:Real}
    return Config{T}(
        atol,
        rtol,
        supports_optimize,
        optimal_status,
        excluded_attributes,
    )
end

function Base.copy(config::Config{T}) where {T}
    return Config{T}(
        config.atol,
        config.rtol,
        config.supports_optimize,
        config.optimal_status,
        copy(config.excluded_attributes),
    )
end

"""
    setup_test(::typeof(f), model::MOI.ModelLike, config::Config)

Overload this method to modify `model` before running the test function `f` on
`model` with `config`. You can also modify the fields in `config` (e.g., to
loosen the default tolerances).

This function should either return `nothing`, or return a function which, when
called with zero arguments, undoes the setup to return the model to its
previous state. You do not need to undo any modifications to `config`.

This function is most useful when writing new tests of the tests for MOI, but it
can also be used to set test-specific tolerances, etc.

See also: [`runtests`](@ref)

## Example

```julia
function MOI.Test.setup_test(
    ::typeof(MOI.Test.test_linear_VariablePrimalStart_partial),
    mock::MOIU.MockOptimizer,
    ::MOI.Test.Config,
)
    MOIU.set_mock_optimize!(
        mock,
        (mock::MOIU.MockOptimizer) -> MOIU.mock_optimize!(mock, [1.0, 0.0]),
    )
    mock.eval_variable_constraint_dual = false

    function reset_function()
        mock.eval_variable_constraint_dual = true
        return
    end
    return reset_function
end
```
"""
setup_test(::Any, ::MOI.ModelLike, ::Config) = nothing

"""
    runtests(
        model::MOI.ModelLike,
        config::Config;
        include::Vector{String} = String[],
        exclude::Vector{String} = String[],
    )

Run all tests in `MathOptInterface.Test` on `model`.

## Configuration arguments

 * `config` is a [`Test.Config`](@ref) object that can be used to modify the
   behavior of tests.
 * If `include` is not empty, only run tests that contain an element from
   `include` in their name.
 * If `exclude` is not empty, skip tests that contain an element from `exclude`
   in their name.
 * `exclude` takes priority over `include`.

See also: [`setup_test`](@ref).

## Example

```julia
config = MathOptInterface.Test.Config()
MathOptInterface.Test.runtests(
    model,
    config;
    include = ["test_linear_"],
    exclude = ["VariablePrimalStart"],
)
```
"""
function runtests(
    model::MOI.ModelLike,
    config::Config;
    include::Vector{String} = String[],
    exclude::Vector{String} = String[],
    warn_unsupported::Bool = false,
)
    for name_sym in names(@__MODULE__; all = true)
        name = string(name_sym)
        if !startswith(name, "test_")
            continue  # All test functions start with test_
        elseif !isempty(include) && !any(s -> occursin(s, name), include)
            continue
        elseif !isempty(exclude) && any(s -> occursin(s, name), exclude)
            continue
        end
        @testset "$(name)" begin
            test_function = getfield(@__MODULE__, name_sym)
            c = copy(config)
            tear_down = setup_test(test_function, model, c)
            # Make sure to empty the model before every test!
            MOI.empty!(model)
            try
                test_function(model, c)
            catch err
                _error_handler(err, name, warn_unsupported)
            end
            if tear_down !== nothing
                tear_down()
            end
        end
    end
    return
end

function _error_handler(
    err::MOI.UnsupportedConstraint{F,S},
    name::String,
    warn_unsupported::Bool,
) where {F,S}
    if warn_unsupported
        @warn("Skipping: $(name) due to unsupported constraint of $F-in-$S")
    end
    return
end

function _error_handler(
    err::MOI.UnsupportedAttribute{T},
    name::String,
    warn_unsupported::Bool,
) where {T}
    if warn_unsupported
        @warn("Skipping: $(name) due to unsupported attribute $T")
    end
    return
end

_error_handler(err, ::String, ::Bool) = rethrow(err)

###
### The following are helpful utilities for writing tests in MOI.Test.
###

"""
    Base.isapprox(x, y, config::Config)

A three argument version of `isapprox` for use in MOI.Test.
"""
function Base.isapprox(x::T, y::T, config::Config{T}) where {T}
    return Base.isapprox(x, y; atol = config.atol, rtol = config.rtol)
end

function Base.isapprox(x::Vector{T}, y::Vector{T}, config::Config{T}) where {T}
    return Base.isapprox(x, y; atol = config.atol, rtol = config.rtol)
end

"""
    _supports(config::Config, attribute::MOI.AnyAttribute)

Return `true` if the `attribute` is supported by the `config`.

This is helpful when writing tests.

## Example

```julia
if MOI.Test._supports(config, MOI.Silent())
    @test MOI.get(model, MOI.Silent()) == true
end
```
"""
function _supports(config::Config, attribute::MOI.AnyAttribute)
    return !(attribute in config.excluded_attributes)
end

"""
    _test_model_solution(
        model::MOI.ModelLike,
        config::Config;
        objective_value = nothing,
        variable_primal = nothing,
        constraint_primal = nothing,
        constraint_dual = nothing,
    )

Solve, and then test, various aspects of a model.

First, check that `TerminationStatus == MOI.OPTIMAL`.

If `objective_value` is not nothing, check that the attribute `ObjectiveValue()`
is approximately `objective_value`.

If `variable_primal` is not nothing, check that the attribute  `PrimalStatus` is
`MOI.FEASIBLE_POINT`. Then for each `(index, value)` in `variable_primal`, check
that the primal value of the variable `index` is approximately `value`.

If `constraint_primal` is not nothing, check that the attribute  `PrimalStatus`
is `MOI.FEASIBLE_POINT`. Then for each `(index, value)` in `constraint_primal`,
check that the primal value of the constraint `index` is approximately `value`.

Finally, if `config.duals = true`, and if `constraint_dual` is not nothing,
check that the attribute  `DualStatus` is `MOI.FEASIBLE_POINT`. Then for each
`(index, value)` in `constraint_dual`, check that the dual of the constraint
`index` is approximately `value`.

### Example

```julia
MOIU.loadfromstring!(model, \"\"\"
    variables: x
    minobjective: 2.0x + 1.0
    c: x >= 1.0
\"\"\")
x = MOI.get(model, MOI.VariableIndex, "x")
c = MOI.get(
    model,
    MOI.ConstraintIndex{MOI.SingleVariable,MOI.GreaterThan{Float64}},
    "c",
)
_test_model_solution(
    model,
    config;
    objective_value = 3.0,
    variable_primal = [(x, 1.0)],
    constraint_primal = [(c, 1.0)],
    constraint_dual = [(c, 2.0)],
)
```
"""
function _test_model_solution(
    model::MOI.ModelLike,
    config::Config{T};
    objective_value = nothing,
    variable_primal = nothing,
    constraint_primal = nothing,
    constraint_dual = nothing,
) where {T}
    if !config.supports_optimize
        return
    end
    MOI.optimize!(model)
    # No need to check supports. Everyone _must_ implement ObjectiveValue.
    @test MOI.get(model, MOI.TerminationStatus()) == config.optimal_status
    if objective_value !== nothing && _supports(config, MOI.ObjectiveValue())
        @test isapprox(
            MOI.get(model, MOI.ObjectiveValue()),
            objective_value,
            config,
        )
    end
    # No need to check supports. Everyone _must_ implement VariablePrimal.
    if variable_primal !== nothing
        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT
        for (index, solution_value) in variable_primal
            @test isapprox(
                MOI.get(model, MOI.VariablePrimal(), index),
                solution_value,
                config,
            )
        end
    end
    if constraint_primal !== nothing &&
       _supports(config, MOI.ConstraintPrimal())
        @test MOI.get(model, MOI.PrimalStatus()) == MOI.FEASIBLE_POINT
        for (index, solution_value) in constraint_primal
            @test isapprox(
                MOI.get(model, MOI.ConstraintPrimal(), index),
                solution_value,
                config,
            )
        end
    end
    if constraint_dual !== nothing && _supports(config, MOI.ConstraintDual())
        @test MOI.get(model, MOI.DualStatus()) == MOI.FEASIBLE_POINT
        for (index, solution_value) in constraint_dual
            @test isapprox(
                MOI.get(model, MOI.ConstraintDual(), index),
                solution_value,
                config,
            )
        end
    end
    return
end

###
### Include all the test files!
###

for file in readdir(@__DIR__)
    if startswith(file, "test_")
        include(file)
    end
end

end # module
