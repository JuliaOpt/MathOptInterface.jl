using Documenter, MathOptInterface

"""
Pass `julia docs/make.jl --fix` to rebuild the doctests.
"""
const _FIX = findfirst(isequal("--fix"), ARGS) !== nothing

makedocs(
    sitename = "MathOptInterface",
    format = Documenter.HTML(
        # See https://github.com/JuliaDocs/Documenter.jl/issues/868
        prettyurls = get(ENV, "CI", nothing) == "true",
        mathengine = Documenter.MathJax2(),
        collapselevel = 1,
    ),
    strict = true,
    modules = [MathOptInterface],
    checkdocs = :exports,
    doctest = _FIX ? :fix : true,
    pages = [
        "Introduction" => "index.md",
        "Manual" => [
            "manual/basic_usage.md",
            "manual/advanced_usage.md",
            "manual/implementing.md",
        ],
        "API Reference" => "reference/reference.md",
        "Submodules" => [
            "Benchmarks" => [
                "Overview" => "submodules/Benchmarks/overview.md",
                "API Reference" => "submodules/Benchmarks/reference.md",
            ],
            "Bridges" => [
                "Overview" => "submodules/Bridges/overview.md",
                "API Reference" => "submodules/Bridges/reference.md",
            ],
            "FileFormats" => [
                "Overview" => "submodules/FileFormats/overview.md",
                "API Reference" => "submodules/FileFormats/reference.md",
            ],
            "Utilities" => [
                "Overview" => "submodules/Utilities/overview.md",
                "API Reference" => "submodules/Utilities/reference.md",
            ],
            "Test" => [
                "Overview" => "submodules/Test/overview.md",
            ],
        ],
    ],
)

deploydocs(
    repo   = "github.com/jump-dev/MathOptInterface.jl.git",
)
